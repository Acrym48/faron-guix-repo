// Package wsconn wraps gorilla/websocket with the small surface the proxy
// needs: dial to a pinned IP with a custom SNI, per-message binary send,
// message receive and close handling.
package wsconn

import (
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"os"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

const maxMessageLen = 16 * 1024 * 1024

// ErrWsTimeout signals a TCP/WS handshake timeout.
var ErrWsTimeout = errors.New("websocket handshake timeout")

// WsHandshakeError carries the HTTP status of a failed WS upgrade.
type WsHandshakeError struct {
	StatusCode int
	StatusLine string
	Location   string
}

func (e *WsHandshakeError) Error() string {
	return fmt.Sprintf("HTTP %d: %s", e.StatusCode, e.StatusLine)
}

// IsRedirect reports whether the status is a redirect that the proxy should
// treat as "WS unavailable here".
func (e *WsHandshakeError) IsRedirect() bool {
	switch e.StatusCode {
	case 301, 302, 303, 307, 308:
		return true
	default:
		return false
	}
}

// RawWebSocket is a gorilla-backed WebSocket with the same methods the
// Python caller used.
type RawWebSocket struct {
	conn   *websocket.Conn
	closed atomic.Bool
	mu     sync.Mutex // guards WriteMessage
}

func dialTimeout(timeout time.Duration) time.Duration {
	if timeout <= 0 || timeout > 10*time.Second {
		return 10 * time.Second
	}
	return timeout
}

// Dial connects to targetHost:443 (an IP or hostname) and performs the WS
// upgrade on wss://domain+path with SNI=domain (or sni when explicitly set).
//
// Errors are normalized: timeouts become ErrWsTimeout, non-101 HTTP
// responses become *WsHandshakeError.
func Dial(targetHost, domain, path string, timeout time.Duration, sni string) (*RawWebSocket, error) {
	if targetHost == "" {
		targetHost = domain
	}
	if sni == "" {
		sni = domain
	}
	netTimeout := dialTimeout(timeout)

	d := &websocket.Dialer{
		HandshakeTimeout: timeout,
		Subprotocols:     []string{"binary"},
		TLSClientConfig: &tls.Config{
			ServerName:         sni,
			InsecureSkipVerify: true,
		},
		NetDial: func(network, addr string) (net.Conn, error) {
			n, err := net.DialTimeout("tcp", net.JoinHostPort(targetHost, "443"), netTimeout)
			if err != nil {
				return nil, err
			}
			if tc, ok := n.(*net.TCPConn); ok {
				_ = tc.SetNoDelay(true)
				_ = tc.SetReadBuffer(256 * 1024)
				_ = tc.SetWriteBuffer(256 * 1024)
			}
			return n, nil
		},
	}

	ws, resp, err := d.Dial("wss://"+domain+path, nil)
	if err == nil {
		rw := &RawWebSocket{conn: ws}
		rw.conn.SetReadLimit(maxMessageLen)
		return rw, nil
	}

	if resp != nil {
		return nil, &WsHandshakeError{
			StatusCode: resp.StatusCode,
			StatusLine: resp.Status,
			Location:   resp.Header.Get("Location"),
		}
	}
	if isTimeoutErr(err) {
		return nil, ErrWsTimeout
	}
	return nil, err
}

func isTimeoutErr(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, os.ErrDeadlineExceeded) {
		return true
	}
	var ne net.Error
	if errors.As(err, &ne) {
		return ne.Timeout()
	}
	return false
}

// Send writes one binary message.
func (w *RawWebSocket) Send(data []byte) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.closed.Load() {
		return errors.New("websocket closed")
	}
	return w.conn.WriteMessage(websocket.BinaryMessage, data)
}

// SendBatch writes separate binary messages for each part.
func (w *RawWebSocket) SendBatch(parts [][]byte) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.closed.Load() {
		return errors.New("websocket closed")
	}
	for _, p := range parts {
		if err := w.conn.WriteMessage(websocket.BinaryMessage, p); err != nil {
			return err
		}
	}
	return nil
}

// Recv returns the next application message payload. A nil, nil result
// signals a graceful upstream close (matches the Python `None`).
func (w *RawWebSocket) Recv() ([]byte, error) {
	_, data, err := w.conn.ReadMessage()
	if err != nil {
		if isCloseError(err) {
			w.closed.Store(true)
			return nil, nil
		}
		return nil, err
	}
	return data, nil
}

func isCloseError(err error) bool {
	if err == nil {
		return false
	}
	if websocket.IsCloseError(err,
		websocket.CloseNormalClosure,
		websocket.CloseGoingAway,
		websocket.CloseNoStatusReceived,
		websocket.CloseAbnormalClosure,
	) {
		return true
	}
	return websocket.IsUnexpectedCloseError(err) || errors.Is(err, websocket.ErrCloseSent)
}

// Close sends a close frame and tears down the connection.
func (w *RawWebSocket) Close() {
	w.mu.Lock()
	if !w.closed.Load() {
		w.closed.Store(true)
		_ = w.conn.WriteMessage(websocket.CloseMessage,
			websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
	}
	w.mu.Unlock()
	_ = w.conn.Close()
}

// IsClosed reports whether the socket has been marked closed.
func (w *RawWebSocket) IsClosed() bool { return w.closed.Load() }
