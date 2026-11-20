package proxy

import (
	"reflect"
	"testing"
)

// The seed must carry every relay VK named so a cold pool has another
// relay to move to when the first answers TURN but does not forward.
func TestSeedCredsCarriesEveryRelayWithoutDuplicates(t *testing.T) {
	const own = "203.0.113.1:3478"
	second := "203.0.113.2:3478"
	for _, c := range []struct {
		name string
		in   []string
		want []string
	}{
		{"no list: the old one-relay seed", nil, nil},
		{"VK's two relays", []string{own, second}, []string{own, second}},
		{"the own relay stands first", []string{second, own}, []string{own, second}},
		{"duplicates are dropped", []string{own, second, second, own}, []string{own, second}},
		{"malformed entries are dropped", []string{"", "no-port", second}, []string{own, second}},
	} {
		t.Run(c.name, func(t *testing.T) {
			got := SeedCreds(own, "user", "pw", c.in)
			if got.Address != own || got.Username != "user" || got.Password != "pw" {
				t.Fatalf("the seed's own fields: %+v", *got)
			}
			if !reflect.DeepEqual(got.Addresses, c.want) {
				t.Fatalf("Addresses = %v, want %v", got.Addresses, c.want)
			}
		})
	}
}
