package csqtt25

// The rhythm of a client on the wire, for the log. Counters say how much a
// client spoke; a phone's radio sees WHEN. An idle client still speaks —
// keepalives and probes — so thirty streams in step leave seconds of quiet
// where thirty spread streams do not. This clock measures those stretches.
//
// Measured: every datagram a stream writes through its wrapper (send) and
// every authentic one a READY stream hears (receive). Not measured: the
// handshake's own datagrams and the relay client's refreshes.

import (
	"sync/atomic"
	"time"
)

// QuietFloor is how long the wire must be without a datagram for a stretch
// to count as a quiet one.
const QuietFloor = 3 * time.Second

// WireQuiet is one take of the measure (Client.WireQuiet).
type WireQuiet struct {
	Span    time.Duration // since the take before this one, or the client's start
	Out, In int64         // datagrams written and heard in it
	Longest time.Duration // longest stretch without one, the still-open one included
	Quiet   int64         // stretches of QuietFloor and more that ENDED in it
}

// wireClock keeps the measure between two takes. Its readings are the
// streams' own wall-clock nanoseconds; a suspension is a stretch like any
// other.
type wireClock struct {
	since   atomic.Int64
	last    atomic.Int64
	out, in atomic.Int64
	longest atomic.Int64
	quiet   atomic.Int64
}

func (q *wireClock) begin(now int64) {
	q.since.Store(now)
	q.last.Store(now)
}

// note records one datagram. A reading older than the previous one ends
// no stretch — two streams may read the clock concurrently.
func (q *wireClock) note(now int64, out bool) {
	if out {
		q.out.Add(1)
	} else {
		q.in.Add(1)
	}
	gap := now - q.last.Swap(now)
	for {
		cur := q.longest.Load()
		if gap <= cur || q.longest.CompareAndSwap(cur, gap) {
			break
		}
	}
	if gap >= int64(QuietFloor) {
		q.quiet.Add(1)
	}
}

// take hands out the measure since the last take and starts the next.
func (q *wireClock) take(now int64) WireQuiet {
	r := WireQuiet{
		Span:    time.Duration(now - q.since.Swap(now)),
		Out:     q.out.Swap(0),
		In:      q.in.Swap(0),
		Longest: time.Duration(q.longest.Swap(0)),
		Quiet:   q.quiet.Swap(0),
	}
	if open := time.Duration(now - q.last.Load()); open > r.Longest {
		r.Longest = open
	}
	return r
}

// WireQuiet takes the rhythm since the previous take. A take starts the
// next stretch, so it has ONE reader: whoever logs it at a steady pace.
func (c *Client) WireQuiet() WireQuiet {
	return c.wire.take(time.Now().UnixNano())
}
