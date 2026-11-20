package proxy

// Inner traffic summary — a once-a-minute line of what the phone's own
// traffic meets inside the tunnel. Counts only, from IP headers: no address
// and no name ever leaves the device in the line. Off by default.

import (
	"log"
	"sync"
	"time"

	"golang.zx2c4.com/wireguard/tun"
)

type innerKey struct {
	src, dst                 [4]byte
	sport, dport             uint16
	proto                    byte
}

type innerFlow struct {
	out, in   int64
	last      time.Time
	answered  bool
	counted   bool
	syn, rst  int64
}

type innerTraffic struct {
	mu     sync.Mutex
	on     bool
	span   time.Time
	pktOut int64
	pktIn  int64

	tcpAttempt, tcpAnswered, tcpRefused, tcpSilent, tcpStalled, tcpResent int64
	dnsQueries, dnsAnswers                                               int64
	udpFlows, udpUnanswered                                              int64
	icmpIn                                                               int64
	other                                                                int64

	seen map[innerKey]innerFlow
}

func newInnerTraffic() *innerTraffic {
	return &innerTraffic{seen: map[innerKey]innerFlow{}, span: time.Now()}
}

func (c *innerTraffic) setOn(on bool) {
	c.mu.Lock()
	c.on = on
	c.span = time.Now()
	c.mu.Unlock()
}

// note inspects only IPv4 header bytes. No payload is read.
func (c *innerTraffic) note(pkt []byte, out bool, now time.Time) {
	if len(pkt) < 20 || pkt[0]>>4 != 4 {
		return
	}
	ihl := int(pkt[0]&0x0f) * 4
	if ihl < 20 || len(pkt) < ihl {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.on {
		return
	}
	if out {
		c.pktOut++
	} else {
		c.pktIn++
	}
	var src, dst [4]byte
	copy(src[:], pkt[12:16])
	copy(dst[:], pkt[16:20])
	proto := pkt[9]
	k := innerKey{src: src, dst: dst, proto: proto}
	if proto == 6 || proto == 17 {
		if len(pkt) < ihl+4 {
			return
		}
		k.sport = uint16(pkt[ihl])<<8 | uint16(pkt[ihl+1])
		k.dport = uint16(pkt[ihl+2])<<8 | uint16(pkt[ihl+3])
	}
	if !out {
		k.src, k.dst = k.dst, k.src
		k.sport, k.dport = k.dport, k.sport
	}
	f := c.seen[k]
	if out {
		f.out++
	} else {
		f.in++
		f.answered = true
	}
	f.last = now
	if proto == 6 && len(pkt) >= ihl+13 {
		flags := pkt[ihl+13]
		syn, ack, rst := flags&0x02 != 0, flags&0x10 != 0, flags&0x04 != 0
		if out && syn && !ack {
			f.syn++
			c.tcpAttempt++
			if !f.counted {
				c.tcpSilent++
				f.counted = true
			}
		}
		if !out && syn && ack {
			c.tcpAnswered++
		}
		if rst {
			f.rst++
			c.tcpRefused++
		}
		if out && !syn && f.out > f.syn+1 {
			c.tcpResent++
		}
	}
	if proto == 17 {
		if out && k.dport == 53 {
			c.dnsQueries++
		}
		if !out && k.sport == 53 {
			c.dnsAnswers++
		}
		if out && !f.counted {
			c.udpFlows++
			f.counted = true
		}
	}
	if proto == 1 && !out {
		c.icmpIn++
	} else if proto != 6 && proto != 17 && proto != 1 {
		c.other++
	}
	c.seen[k] = f
}

// take prints one summary and resets the counters. Call once a minute.
func (c *innerTraffic) take(now time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.on {
		return
	}
	for _, f := range c.seen {
		if f.in == 0 {
			c.udpUnanswered++
		}
		if !f.answered && now.Sub(f.last) >= 10*time.Second {
			c.tcpStalled++
		}
	}
	log.Printf("inner, the last %v: %d pkt out / %d in; tcp: %d attempted, %d answered, %d refused, %d silent, %d stalled 10s+, %d re-sent; dns: %d queries, %d answers; udp: %d flows, %d never answered; icmp in: %d; other: %d",
		now.Sub(c.span).Round(time.Second), c.pktOut, c.pktIn,
		c.tcpAttempt, c.tcpAnswered, c.tcpRefused, c.tcpSilent, c.tcpStalled, c.tcpResent,
		c.dnsQueries, c.dnsAnswers, c.udpFlows, c.udpUnanswered, c.icmpIn, c.other)
	// Reset the counters in place: assigning a fresh struct would replace the
	// mutex that the deferred Unlock above is holding.
	c.span = now
	c.pktOut, c.pktIn = 0, 0
	c.tcpAttempt, c.tcpAnswered, c.tcpRefused = 0, 0, 0
	c.tcpSilent, c.tcpStalled, c.tcpResent = 0, 0, 0
	c.dnsQueries, c.dnsAnswers = 0, 0
	c.udpFlows, c.udpUnanswered = 0, 0
	c.icmpIn, c.other = 0, 0
	c.seen = map[innerKey]innerFlow{}
}

// innerTUN wraps tun.Device transparently. Only the byte slices handed to
// Read/Write are observed; the device's own behaviour is unchanged.
type innerTUN struct {
	tun.Device
	counter *innerTraffic
}

func (t *innerTUN) Read(bufs [][]byte, sizes []int, offset int) (int, error) {
	n, err := t.Device.Read(bufs, sizes, offset)
	now := time.Now()
	for i := 0; i < n; i++ {
		t.counter.note(bufs[i][offset:offset+sizes[i]], false, now)
	}
	return n, err
}

func (t *innerTUN) Write(bufs [][]byte, offset int) (int, error) {
	for _, b := range bufs {
		t.counter.note(b[offset:], true, time.Now())
	}
	return t.Device.Write(bufs, offset)
}

// wrapTUNForInnerWith wraps dev only when the counter is on.
func wrapTUNForInnerWith(dev tun.Device, c *innerTraffic) tun.Device {
	c.mu.Lock()
	on := c.on
	c.mu.Unlock()
	if !on {
		return dev
	}
	return &innerTUN{Device: dev, counter: c}
}

// WrapTUNForInner wraps dev only when the toggle is on; off by default.
func WrapTUNForInner(dev tun.Device) tun.Device {
	return wrapTUNForInnerWith(dev, globalInnerTraffic)
}
