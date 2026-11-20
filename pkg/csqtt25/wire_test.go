package csqtt25

import (
	"testing"
	"time"
)

func TestWireClockMeasuresTheStretches(t *testing.T) {
	const s = int64(time.Second)
	var q wireClock
	q.begin(100 * s)
	q.note(101*s, true)
	q.note(105*s, false) // 4 s: a quiet one
	q.note(105*s+s/2, true)
	if got, want := q.take(107*s), (WireQuiet{Span: 7 * time.Second, Out: 2, In: 1, Longest: 4 * time.Second, Quiet: 1}); got != want {
		t.Fatalf("first take %+v, want %+v", got, want)
	}
	if got, want := q.take(120*s), (WireQuiet{Span: 13 * time.Second, Longest: 14*time.Second + 500*time.Millisecond}); got != want {
		t.Fatalf("idle take %+v, want %+v", got, want)
	}
	q.note(121*s, false)
	if got, want := q.take(122*s), (WireQuiet{Span: 2 * time.Second, In: 1, Longest: 15*time.Second + 500*time.Millisecond, Quiet: 1}); got != want {
		t.Fatalf("the take a long stretch ended in %+v, want %+v", got, want)
	}

	// The floor: one nanosecond short is not quiet, the floor itself is.
	var b wireClock
	b.begin(0)
	b.note(int64(QuietFloor)-1, true)
	b.note(2*int64(QuietFloor)-1, true)
	if got, want := b.take(2*int64(QuietFloor)), (WireQuiet{Span: 2 * QuietFloor, Out: 2, Longest: QuietFloor, Quiet: 1}); got != want {
		t.Fatalf("at the floor %+v, want %+v", got, want)
	}

	// An older reading behind a newer one ends no stretch.
	var r wireClock
	r.begin(10 * s)
	r.note(12*s, true)
	r.note(11*s, false)
	if got, want := r.take(12*s), (WireQuiet{Span: 2 * time.Second, Out: 1, In: 1, Longest: 2 * time.Second}); got != want {
		t.Fatalf("an older reading %+v, want %+v", got, want)
	}
}
