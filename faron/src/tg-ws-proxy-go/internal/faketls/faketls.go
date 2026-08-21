// Package faketls implements the Fake TLS ("ee" secret) masking feature:
// a server-side TLS facade that authenticates TDesktop's ClientHello with
// HMAC-SHA256, answers with a fake ServerHello, and afterward carries the
// obfuscated MTProto stream inside TLS application-data records.
package faketls

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"io"
	"math"
	"net"
	"time"
)

const (
	TLSRecordHandshake = 0x16
	TLSRecordCCS       = 0x14
	TLSRecordAppdata   = 0x17

	ClientRandomOffset = 11
	ClientRandomLen    = 32
	SessionIDOffset    = 44
	SessionIDLen       = 32

	TimestampTolerance = 120

	TLSAppdataMax = 16384
)

var ccsFrame = []byte{0x14, 0x03, 0x03, 0x00, 0x01, 0x01}

// serverHelloTemplate (127 bytes) with zero placeholders.
var serverHelloTemplate = []byte{
	0x16, 0x03, 0x03, 0x00, 0x7a,
	0x02, 0x00, 0x00, 0x76,
	0x03, 0x03,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x20,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x13, 0x01, 0x00,
	0x00, 0x2e,
	0x00, 0x33, 0x00, 0x24, 0x00, 0x1d, 0x00, 0x20,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x2b, 0x00, 0x02, 0x03, 0x04,
}

const (
	shRandomOff = 11
	shSessidOff = 44
	shPubkeyOff = 89
)

// VerifyClientHello authenticates a TLS ClientHello record against the
// proxy secret and freshness. Returns (clientRandom, sessionID, timestamp)
// on success, nil otherwise.
func VerifyClientHello(data, secret []byte) ([]byte, []byte, int64, bool) {
	n := len(data)
	if n < 43 {
		return nil, nil, 0, false
	}
	if data[0] != TLSRecordHandshake {
		return nil, nil, 0, false
	}
	if data[5] != 0x01 {
		return nil, nil, 0, false
	}

	clientRandom := clone(data[ClientRandomOffset : ClientRandomOffset+ClientRandomLen])

	zeroed := clone(data)
	for i := 0; i < ClientRandomLen; i++ {
		zeroed[ClientRandomOffset+i] = 0
	}

	mac := hmac.New(sha256.New, secret)
	mac.Write(zeroed)
	expected := mac.Sum(nil)

	if !hmac.Equal(expected[:28], clientRandom[:28]) {
		return nil, nil, 0, false
	}

	tsBytes := [4]byte{}
	for i := 0; i < 4; i++ {
		tsBytes[i] = clientRandom[28+i] ^ expected[28+i]
	}
	timestamp := int64(binary.LittleEndian.Uint32(tsBytes[:]))

	now := time.Now().Unix()
	if math.Abs(float64(now-timestamp)) > TimestampTolerance {
		return nil, nil, 0, false
	}

	sessionID := make([]byte, SessionIDLen)
	if n >= SessionIDOffset+SessionIDLen && data[43] == 0x20 {
		copy(sessionID, data[SessionIDOffset:SessionIDOffset+SessionIDLen])
	}
	return clientRandom, sessionID, timestamp, true
}

// BuildServerHello produces the fake ServerHello bound to the client random.
func BuildServerHello(secret, clientRandom, sessionID []byte) []byte {
	sh := clone(serverHelloTemplate)
	copy(sh[shSessidOff:shSessidOff+SessionIDLen], sessionID)
	pub := make([]byte, 32)
	_, _ = rand.Read(pub)
	copy(sh[shPubkeyOff:shPubkeyOff+32], pub)

	encSize := 1900 + int(randByte()%201)
	enc := make([]byte, encSize)
	_, _ = rand.Read(enc)
	appRecord := append([]byte{TLSRecordAppdata, 0x03, 0x03},
		byte(encSize>>8), byte(encSize))
	appRecord = append(appRecord, enc...)

	response := append(append(append([]byte(nil), sh...), ccsFrame...), appRecord...)

	mac := hmac.New(sha256.New, secret)
	mac.Write(clientRandom)
	mac.Write(response)
	serverRandom := mac.Sum(nil)

	final := clone(response)
	copy(final[shRandomOff:shRandomOff+32], serverRandom)
	return final
}

func randByte() byte {
	buf := make([]byte, 1)
	_, _ = rand.Read(buf)
	return buf[0]
}

// WrapTlsRecord splits payload into TLS application-data records.
func WrapTlsRecord(data []byte) []byte {
	if len(data) == 0 {
		return nil
	}
	var out []byte
	for len(data) > 0 {
		n := len(data)
		if n > TLSAppdataMax {
			n = TLSAppdataMax
		}
		chunk := data[:n]
		hdr := []byte{TLSRecordAppdata, 0x03, 0x03, byte(n >> 8), byte(n)}
		out = append(out, hdr...)
		out = append(out, chunk...)
		data = data[n:]
	}
	return out
}

func clone(b []byte) []byte {
	out := make([]byte, len(b))
	copy(out, b)
	return out
}

// FakeTlsStream presents a fire-and-forget TLS facade: reads unwrap TLS
// application-data records, writes wrap payloads back into records.
type FakeTlsStream struct {
	r io.Reader
	c net.Conn

	readBuf  []byte
	readLeft int
}

// NewFakeTlsStream wraps the underlying conn; reads come from r (which may
// be a buffered reader holding leftover handshake bytes).
func NewFakeTlsStream(r io.Reader, c net.Conn) *FakeTlsStream {
	return &FakeTlsStream{r: r, c: c}
}

// Readexactly returns exactly n unwrapped bytes (the obfuscated init packet).
func (t *FakeTlsStream) Readexactly(n int) ([]byte, error) {
	for len(t.readBuf) < n {
		payload, err := t.readTLSPayload()
		if err != nil {
			return nil, err
		}
		if len(payload) == 0 {
			return nil, io.ErrUnexpectedEOF
		}
		t.readBuf = append(t.readBuf, payload...)
	}
	out := make([]byte, n)
	copy(out, t.readBuf[:n])
	t.readBuf = t.readBuf[n:]
	return out, nil
}

// Read implements io.Reader over the unwrapped record stream.
func (t *FakeTlsStream) Read(p []byte) (int, error) {
	if len(t.readBuf) > 0 {
		n := copy(p, t.readBuf)
		t.readBuf = t.readBuf[n:]
		return n, nil
	}
	payload, err := t.readTLSPayload()
	if err != nil {
		return 0, err
	}
	if len(payload) == 0 {
		return 0, io.EOF
	}
	if len(payload) > len(p) {
		n := copy(p, payload[:len(p)])
		t.readBuf = append(t.readBuf, payload[len(p):]...)
		return n, nil
	}
	return copy(p, payload), nil
}

func (t *FakeTlsStream) readTLSPayload() ([]byte, error) {
	if t.readLeft > 0 {
		data := make([]byte, t.readLeft)
		n, err := io.ReadFull(t.r, data)
		if err != nil && err != io.EOF {
			return nil, err
		}
		if n == 0 {
			return nil, nil
		}
		t.readLeft -= n
		return data[:n], nil
	}

	for {
		hdr := make([]byte, 5)
		if _, err := io.ReadFull(t.r, hdr); err != nil {
			return nil, err
		}
		recLen := int(hdr[3])<<8 | int(hdr[4])

		switch hdr[0] {
		case TLSRecordCCS:
			if recLen > 0 {
				skip := make([]byte, recLen)
				if _, err := io.ReadFull(t.r, skip); err != nil {
					return nil, err
				}
			}
			continue
		case TLSRecordAppdata:
			n := recLen
			if n > 65536 {
				n = 65536
			}
			data := make([]byte, n)
			n, err := io.ReadFull(t.r, data[:n])
			if err != nil && err != io.EOF {
				return nil, err
			}
			if n == 0 {
				return nil, nil
			}
			remaining := recLen - n
			if remaining > 0 {
				t.readLeft = remaining
			}
			return data[:n], nil
		default:
			// any other record type terminates the stream (matches python)
			return nil, nil
		}
	}
}

// Write wraps payload into TLS application records and sends it.
func (t *FakeTlsStream) Write(p []byte) (int, error) {
	wrapped := WrapTlsRecord(p)
	_, err := t.c.Write(wrapped)
	return len(p), err
}

// Close closes the underlying connection.
func (t *FakeTlsStream) Close() error { return t.c.Close() }
