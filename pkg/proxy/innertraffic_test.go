package proxy

import (
	"strings"
	"testing"
	"time"
)

func ipTCP(src, dst [4]byte, sport, dport uint16, flags byte) []byte {
	b := make([]byte, 40)
	b[0] = 0x45
	b[2], b[3] = 0, 40
	b[8], b[9] = 64, 6
	copy(b[12:16], src[:])
	copy(b[16:20], dst[:])
	b[20], b[21] = byte(sport>>8), byte(sport)
	b[22], b[23] = byte(dport>>8), byte(dport)
	b[33] = flags
	return b
}

func TestInnerTrafficLogsCountsWithoutAddresses(t *testing.T) {
	c := newInnerTraffic()
	c.setOn(true)
	now := time.Now()
	a, b := [4]byte{10, 0, 0, 1}, [4]byte{10, 0, 0, 2}
	c.note(ipTCP(a, b, 1234, 80, 0x02), true, now)  // SYN out
	c.note(ipTCP(b, a, 80, 1234, 0x12), false, now) // SYN|ACK in
	c.note(ipTCP(a, b, 1234, 80, 0x18), true, now.Add(time.Second)) // ACK out

	out := captureLog(t)
	c.take(now.Add(time.Minute))
	line := out()
	for _, want := range []string{"tcp: 1 attempted, 1 answered", "2 pkt out / 1 in"} {
		if !strings.Contains(line, want) {
			t.Fatalf("the line %q does not say %q", line, want)
		}
	}
	for _, leak := range []string{"10.0.0.1", "10.0.0.2"} {
		if strings.Contains(line, leak) {
			t.Fatalf("the line leaks the address %s: %q", leak, line)
		}
	}
}

func TestInnerTrafficOffByDefault(t *testing.T) {
	c := newInnerTraffic()
	out := captureLog(t)
	c.note(ipTCP([4]byte{1, 1, 1, 1}, [4]byte{2, 2, 2, 2}, 1, 2, 0x02), true, time.Now())
	c.take(time.Now().Add(time.Hour))
	if s := out(); strings.Contains(s, "inner, the last") {
		t.Fatalf("the summary was logged while off: %q", s)
	}
}
