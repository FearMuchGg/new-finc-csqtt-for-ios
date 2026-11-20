package proxy

// A relay that REFUSES the permission for our peer. It accepts the Allocate
// and answers CreatePermission with an error in milliseconds: that answer
// is neither silence (relayhealth.go) nor a quota/auth failure, and the
// session never reaches the peer-handshake logic. It is the relay's own
// word that it will not relay to this server and needs no witness.
//
// Narrow by design: only CreatePermission answered with NO error code
// (pion's handler refusal) or 403 Forbidden. Never 400 or 437 — those say
// the mapping changed — and never 401/438, which are about credentials.
// A 403 on the permission is also not an auth error: the credential made
// the allocation a moment earlier.

import (
	"log"
	"strings"
	"time"
)

const permissionErrorResponse = "CreatePermission error response"

// isPeerRefused reports whether err is the relay's refusal of a permission
// for our peer.
func isPeerRefused(err error) bool {
	if err == nil {
		return false
	}
	s := err.Error()
	i := strings.Index(s, permissionErrorResponse)
	if i < 0 {
		return false
	}
	rest := s[i+len(permissionErrorResponse):]
	if !strings.HasPrefix(rest, " (error ") {
		return true // no code: the server's handler refused the peer
	}
	return strings.HasPrefix(rest, " (error 403:")
}

// IsPeerRefused is the pool's public form of isPeerRefused (csqtt bridge).
func IsPeerRefused(err error) bool { return isPeerRefused(err) }

// notePeerRefused gives the relay the peer mark at once. A refusal of an
// already marked relay leaves the mark and its recovery schedule alone;
// an attempt begun on the old network says nothing about the current one.
func (cp *credPool) notePeerRefused(connIdx int, relay string, start time.Time) {
	if cp == nil || relay == "" {
		return
	}
	cp.mu.Lock()
	defer cp.mu.Unlock()
	if start.Before(cp.health.pathChangedAt) {
		return
	}
	if cp.health.isDead(relay) {
		log.Printf("credpool: conn %d: relay %s refused the permission for our peer again — its mark stands", connIdx, relay)
		return
	}
	// A refusal is the relay's own answer about this peer, so it needs no
	// corroborating answer from another relay. Reuse the existing TURN relay
	// mark: the pool's selection, recovery checks and path-change reset already
	// work through it. Marking is done under cp.mu here; the hook is invoked
	// after unlocking so it can end sessions without re-entering the lock.
	cp.health.markLocked(cp.health.record(relay), cp.health.now())
	log.Printf("credpool: conn %d: relay %s REFUSED the permission for our peer — marked at once (its own answer needs no witness): new attempts go elsewhere, recovery checks apart", connIdx, relay)
	if cp.onRelayMarked == nil {
		return
	}
	stamp := cp.stampLocked()
	go cp.onRelayMarked(relay, stamp)
}

// NotePeerRefused tells the pool that addr refused a permission for our peer
// on an attempt begun at start. Used by the csqtt bridge's lease.
func (p *CredPool) NotePeerRefused(connIdx int, addr string, start time.Time) {
	p.cp.notePeerRefused(connIdx, addr, start)
}

// relayRefusedPeer is the relay leg's way out on a failed CreatePermission:
// a REFUSAL is told to the pool; the original error is returned unchanged.
func (p *Proxy) relayRefusedPeer(connIdx int, turnAddr string, attempt time.Time, err error) error {
	if isPeerRefused(err) {
		p.credPool.notePeerRefused(connIdx, turnAddr, attempt)
	}
	return err
}
