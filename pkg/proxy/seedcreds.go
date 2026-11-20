package proxy

import "net"

// SeedCreds builds the credential the app's pre-bootstrap probe hands the
// pool as its seed: the relay the probe names (address) and, when the app
// passes them, every relay returned with the credential (addresses) —
// the seed's own relay first, each once, an entry that is not host:port
// dropped.
//
// Until 2026-11-18 the seed named one relay: a cold cache had nowhere to
// move when that relay answered TURN but did not forward. With no list the
// result is exactly the old one (Address alone, Addresses nil): a cached
// seed's twin in the pool's disk cache still supplies the rest.
func SeedCreds(address, username, password string, addresses []string) *TURNCreds {
	c := &TURNCreds{Username: username, Password: password, Address: address}
	var named []string
	for _, a := range addresses {
		if _, _, err := net.SplitHostPort(a); err == nil {
			named = append(named, a)
		}
	}
	if len(named) > 0 {
		c.Addresses = dedupeAddrs(append([]string{address}, named...))
	}
	return c
}
