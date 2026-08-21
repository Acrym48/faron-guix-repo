package faketls

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"testing"
	"time"
)

var testSecret = []byte{0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
	0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff}

func buildClientHello(t *testing.T, secret []byte, timestamp int64, sessionID []byte) []byte {
	t.Helper()
	if timestamp == 0 {
		timestamp = time.Now().Unix()
	}
	if sessionID == nil {
		sessionID = make([]byte, SessionIDLen)
		rand.Read(sessionID)
	}

	body := make([]byte, 517)
	body[0] = TLSRecordHandshake
	body[1] = 0x03
	body[2] = 0x01
	binary.BigEndian.PutUint16(body[3:5], uint16(len(body)-5))
	body[5] = 0x01
	body[43] = 0x20
	copy(body[SessionIDOffset:], sessionID)

	mac := hmac.New(sha256.New, secret)
	mac.Write(body)
	digest := mac.Sum(nil)

	clientRandom := make([]byte, ClientRandomLen)
	copy(clientRandom, digest[:ClientRandomLen])
	tsBytes := make([]byte, 4)
	binary.LittleEndian.PutUint32(tsBytes, uint32(timestamp))
	for i := 0; i < 4; i++ {
		clientRandom[28+i] = digest[28+i] ^ tsBytes[i]
	}
	copy(body[ClientRandomOffset:], clientRandom)
	return body
}

func TestVerifyClientHelloAcceptsWellFormed(t *testing.T) {
	sessionID := make([]byte, SessionIDLen)
	rand.Read(sessionID)
	now := time.Now().Unix()

	cr, gotSession, ts, ok := VerifyClientHello(buildClientHello(t, testSecret, now, sessionID), testSecret)
	if !ok {
		t.Fatal("rejected well-formed hello")
	}
	if len(cr) != ClientRandomLen {
		t.Errorf("client random len=%d", len(cr))
	}
	if !bytes.Equal(gotSession, sessionID) {
		t.Error("session id mismatch")
	}
	if ts != now {
		t.Errorf("timestamp mismatch: got %d want %d", ts, now)
	}
}

func TestVerifyClientHelloRejectsWrongSecret(t *testing.T) {
	other := bytes.Repeat([]byte{0xFF}, 16)
	if _, _, _, ok := VerifyClientHello(buildClientHello(t, testSecret, 0, nil), other); ok {
		t.Fatal("accepted hello with wrong secret")
	}
}

func TestVerifyClientHelloRejectsStaleTimestamp(t *testing.T) {
	stale := time.Now().Unix() - 3600
	if _, _, _, ok := VerifyClientHello(buildClientHello(t, testSecret, stale, nil), testSecret); ok {
		t.Fatal("accepted stale hello")
	}
}

func TestVerifyClientHelloRejectsTamperedBody(t *testing.T) {
	hello := buildClientHello(t, testSecret, 0, nil)
	hello[300] ^= 0xFF
	if _, _, _, ok := VerifyClientHello(hello, testSecret); ok {
		t.Fatal("accepted tampered hello")
	}
}

func TestVerifyClientHelloRejectsShortAndNonHandshake(t *testing.T) {
	if _, _, _, ok := VerifyClientHello([]byte{0x16, 0x03, 0x01, 0x00, 0x10}, testSecret); ok {
		t.Fatal("accepted short hello")
	}

	hello := buildClientHello(t, testSecret, 0, nil)
	hello[0] = 0x17
	if _, _, _, ok := VerifyClientHello(hello, testSecret); ok {
		t.Fatal("accepted appdata record")
	}

	hello = buildClientHello(t, testSecret, 0, nil)
	hello[5] = 0x02
	if _, _, _, ok := VerifyClientHello(hello, testSecret); ok {
		t.Fatal("accepted non-handshake type")
	}
}

func TestBuildServerHelloEchoesSessionAndBindsClientRandom(t *testing.T) {
	sessionID := make([]byte, SessionIDLen)
	rand.Read(sessionID)
	clientRandom := make([]byte, ClientRandomLen)
	rand.Read(clientRandom)

	response := BuildServerHello(testSecret, clientRandom, sessionID)

	if response[0] != TLSRecordHandshake {
		t.Error("response does not start with a handshake record")
	}
	if !bytes.Equal(response[SessionIDOffset:SessionIDOffset+SessionIDLen], sessionID) {
		t.Error("session id not echoed")
	}

	zeroed := append([]byte(nil), response...)
	for i := 0; i < 32; i++ {
		zeroed[11+i] = 0
	}
	mac := hmac.New(sha256.New, testSecret)
	mac.Write(clientRandom)
	mac.Write(zeroed)
	expected := mac.Sum(nil)
	if !bytes.Equal(response[11:43], expected) {
		t.Error("server random not bound to client_random")
	}
}

func TestBuildServerHelloPaddingVaries(t *testing.T) {
	sizes := make(map[int]struct{})
	for i := 0; i < 20; i++ {
		cr := make([]byte, 32)
		sid := make([]byte, 32)
		rand.Read(cr)
		rand.Read(sid)
		sizes[len(BuildServerHello(testSecret, cr, sid))] = struct{}{}
	}
	if len(sizes) <= 1 {
		t.Fatal("padding length does not vary")
	}
}

func TestWrapTlsRecordShortPayload(t *testing.T) {
	wrapped := WrapTlsRecord([]byte("hello"))
	want := append([]byte{0x17, 0x03, 0x03, 0x00, 0x05}, []byte("hello")...)
	if !bytes.Equal(wrapped, want) {
		t.Errorf("got %x want %x", wrapped, want)
	}
}

func TestWrapTlsRecordLongPayloadChunked(t *testing.T) {
	payload := make([]byte, TLSAppdataMax+100)
	rand.Read(payload)
	wrapped := WrapTlsRecord(payload)

	var chunks [][]byte
	for off := 0; off < len(wrapped); {
		if wrapped[off] != 0x17 {
			t.Fatal("bad record type")
		}
		length := int(binary.BigEndian.Uint16(wrapped[off+3 : off+5]))
		if length > TLSAppdataMax {
			t.Fatalf("record too long: %d", length)
		}
		chunks = append(chunks, wrapped[off+5:off+5+length])
		off += 5 + length
	}
	if len(chunks) != 2 {
		t.Fatalf("expected 2 chunks, got %d", len(chunks))
	}
	if !bytes.Equal(bytes.Join(chunks, nil), payload) {
		t.Fatal("chunks do not reconstruct payload")
	}
}

func TestWrapTlsRecordEmpty(t *testing.T) {
	if out := WrapTlsRecord(nil); len(out) != 0 {
		t.Fatal("empty payload should produce no records")
	}
}
