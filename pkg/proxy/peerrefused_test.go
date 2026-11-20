package proxy

import (
	"errors"
	"testing"
)

func TestPeerRefusedIsOnlyTheRelaysOwnRefusal(t *testing.T) {
	for _, c := range []struct {
		err  string
		want bool
	}{
		{"CreatePermission error response", true},
		{"turn create permission: CreatePermission error response", true},
		{"turn create permission: CreatePermission error response (error 403: Forbidden)", true},
		{"turn create permission: CreatePermission error response (error 400: Bad Request)", false},
		{"turn create permission: CreatePermission error response (error 437: Allocation Mismatch)", false},
		{"turn create permission: CreatePermission error response (error 401: Unauthorized)", false},
		{"turn allocate: Allocate error response (error 403: Forbidden)", false},
		{"turn create permission: all retransmissions failed", false},
	} {
		if got := IsPeerRefused(errors.New(c.err)); got != c.want {
			t.Errorf("IsPeerRefused(%q) = %v, want %v", c.err, got, c.want)
		}
	}
	if IsPeerRefused(nil) {
		t.Error("no error is a refusal")
	}
	if isAuthError(errors.New("turn create permission: CreatePermission error response")) {
		t.Error("a 403 on the permission is not a dead credential")
	}
}

func TestRelayReaderEndedIgnoresOurOwnClose(t *testing.T) {
	for _, c := range []struct {
		msg  string
		want bool
	}{
		{"Failed to read: read udp x: connection refused. Exiting loop", true},
		{"Failed to handle inbound message: unexpected EOF. Exiting loop", true},
		{"Failed to read: read udp x: use of closed network connection. Exiting loop", false},
		{"Failed to read: something", false},
		{"Refresh done. Exiting loop", false},
	} {
		if got := relayReaderEnded(c.msg); got != c.want {
			t.Errorf("relayReaderEnded(%q) = %v, want %v", c.msg, got, c.want)
		}
	}
}
