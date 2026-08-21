package proxy

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
	"time"

	"tg-ws-proxy-go/internal/faketls"
	"tg-ws-proxy-go/internal/mtproto"
	"tg-ws-proxy-go/internal/stats"
	"tg-ws-proxy-go/internal/utils"
	"tg-ws-proxy-go/internal/wsconn"
)

const (
	ipFailCooldown   = 3600 * time.Second
	dcFailCooldown   = 60 * time.Second
	wsFailTimeout    = 2 * time.Second
	handshakeTimeout = 10 * time.Second
)

func setSockOpts(c net.Conn) {
	tc, ok := c.(*net.TCPConn)
	if !ok {
		return
	}
	_ = tc.SetNoDelay(true)
	_ = tc.SetReadBuffer(256 * 1024)
	_ = tc.SetWriteBuffer(256 * 1024)
}

func readExact(br *bufio.Reader, n int) ([]byte, error) {
	out := make([]byte, n)
	_, err := io.ReadFull(br, out)
	return out, err
}

func readLineLimit(br *bufio.Reader, limit int) ([]byte, error) {
	var buf []byte
	for {
		b, err := br.ReadByte()
		if err != nil {
			return buf, err
		}
		buf = append(buf, b)
		if len(buf) > limit {
			return buf, io.ErrShortBuffer
		}
		if b == '\n' {
			return buf, nil
		}
	}
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

type clientInit struct {
	handshake []byte
	end       endConn
	label     string
}

// readClientInit performs the Fake TLS / plain MTProto handshake read. A nil
// result means the connection was handled by masking or a redirect and must
// be closed by the caller.
func (p *Proxy) readClientInit(conn net.Conn, br *bufio.Reader, label string) *clientInit {
	if p.Cfg.ProxyProtocol {
		_ = conn.SetReadDeadline(time.Now().Add(handshakeTimeout))
		line, err := readLineLimit(br, 108)
		if err != nil {
			p.Log.Debugf("[%s] disconnected during PROXY header", label)
			return nil
		}
		text := strings.TrimSpace(string(line))
		if strings.HasPrefix(text, "PROXY ") {
			parts := strings.Fields(text)
			if len(parts) >= 6 {
				label = parts[2] + ":" + parts[4]
			}
			p.Log.Debugf("[%s] PROXY protocol: %s", label, text)
		} else {
			p.Log.Debugf("[%s] expected PROXY header, got: %q", label, truncate(text, 60))
		}
	}

	_ = conn.SetReadDeadline(time.Now().Add(handshakeTimeout))
	first, err := readExact(br, 1)
	if err != nil {
		p.Log.Debugf("[%s] client disconnected before handshake", label)
		return nil
	}

	masking := p.Cfg.FakeTlsDomain
	if first[0] == faketls.TLSRecordHandshake && masking != "" {
		hdr, err := readExact(br, 4)
		if err != nil {
			p.Log.Debugf("[%s] incomplete TLS record header", label)
			return nil
		}
		tlsHeader := append(append([]byte(nil), first...), hdr...)
		recLen := int(tlsHeader[3])<<8 | int(tlsHeader[4])
		body, err := readExact(br, recLen)
		if err != nil {
			p.Log.Debugf("[%s] incomplete TLS record body", label)
			return nil
		}
		clientHello := append(tlsHeader, body...)

		clientRandom, sessionID, ts, ok := faketls.VerifyClientHello(clientHello, p.secret)
		if !ok {
			p.Log.Debugf("[%s] Fake TLS verify failed (size=%d rec=%d) -> masking",
				label, len(clientHello), recLen)
			p.proxyToMasking(conn, br, clientHello, masking, label)
			return nil
		}
		p.Log.Debugf("[%s] Fake TLS handshake ok (ts=%d)", label, ts)

		serverHello := faketls.BuildServerHello(p.secret, clientRandom, sessionID)
		_, _ = conn.Write(serverHello)

		tlsStream := faketls.NewFakeTlsStream(br, conn)
		handshake, err := tlsStream.Readexactly(mtproto.HandshakeLen)
		if err != nil {
			p.Log.Debugf("[%s] incomplete obfs2 init inside TLS", label)
			return nil
		}
		_ = conn.SetReadDeadline(time.Time{})
		return &clientInit{handshake: handshake, end: tlsStream, label: label}
	}

	if masking != "" {
		p.Log.Debugf("[%s] non-TLS byte 0x%02X -> HTTP redirect", label, first[0])
		redirect := fmt.Sprintf(
			"HTTP/1.1 301 Moved Permanently\r\n"+
				"Location: https://%s/\r\n"+
				"Content-Length: 0\r\n"+
				"Connection: close\r\n\r\n", masking)
		_, _ = conn.Write([]byte(redirect))
		return nil
	}

	rest, err := readExact(br, mtproto.HandshakeLen-1)
	if err != nil {
		p.Log.Debugf("[%s] client disconnected before handshake", label)
		return nil
	}
	_ = conn.SetReadDeadline(time.Time{})
	return &clientInit{
		handshake: append(first, rest...),
		end:       &clientHalf{r: br, w: conn, c: conn},
		label:     label,
	}
}

// proxyToMasking relays the connection verbatim to the masking domain —
// used when Fake TLS verification fails.
func (p *Proxy) proxyToMasking(conn net.Conn, br *bufio.Reader, initial []byte, domain, label string) {
	up, err := net.DialTimeout("tcp", net.JoinHostPort(domain, "443"), handshakeTimeout)
	if err != nil {
		p.Log.Warnf("[%s] masking: cannot connect to %s:443: %s", label, domain, err)
		return
	}
	p.Log.Debugf("[%s] masking -> %s:443", label, domain)
	stats.Current.ConnectionsMasked.Add(1)

	relay := func(src io.Reader, dst io.Writer) {
		buf := make([]byte, 16384)
		for {
			n, err := src.Read(buf)
			if n > 0 {
				if _, wErr := dst.Write(buf[:n]); wErr != nil {
					break
				}
			}
			if err != nil {
				break
			}
		}
	}

	if len(initial) > 0 {
		_, _ = up.Write(initial)
	}
	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); relay(up, conn) }()
	relay(br, up)
	wg.Done()
	wg.Wait()
	_ = up.Close()
	_ = conn.Close()
}

func (p *Proxy) dcKeyFailBefore(dcKey string) time.Time {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.dcFailUntil[dcKey]
}

func (p *Proxy) ipFailBefore(target string) time.Time {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.ipFailUntil[target]
}

func (p *Proxy) handleClient(conn net.Conn) {
	stats.Current.ConnectionsTotal.Add(1)
	stats.Current.ConnectionsActive.Add(1)
	defer stats.Current.ConnectionsActive.Add(-1)
	defer conn.Close()

	setSockOpts(conn)
	br := bufio.NewReaderSize(conn, 64*1024)
	label := conn.RemoteAddr().String()

	init := p.readClientInit(conn, br, label)
	if init == nil {
		return
	}
	handshake := init.handshake
	client := init.end
	label = init.label

	dc, isMedia, protoTag, cltDecPrekeyIV, err := mtproto.TryHandshake(handshake, p.secret)
	if err != nil {
		stats.Current.ConnectionsBad.Add(1)
		p.Log.Warnf("[%s] bad handshake (wrong secret or proto)", label)
		return
	}

	isTestDC := p.Cfg.ForceTestDC || dc >= 10000
	if dc >= 10000 {
		p.Log.Infof("[%s] test DC%d -> DC%d", label, dc, dc-10000)
		dc -= 10000
	}

	var protoInt uint32
	switch {
	case bytes.Equal(protoTag, mtproto.ProtoTagAbridged):
		protoInt = mtproto.ProtoAbridgedInt
	case bytes.Equal(protoTag, mtproto.ProtoTagIntermediate):
		protoInt = mtproto.ProtoIntermediateInt
	default:
		protoInt = mtproto.ProtoPaddedIntermediateInt
	}

	dcIdx := int16(dc)
	if isMedia {
		dcIdx = -dcIdx
	}

	relayInit, err := mtproto.GenerateRelayInit(protoTag, dcIdx)
	if err != nil {
		p.Log.Errorf("[%s] failed to build relay init: %s", label, err)
		return
	}
	ctx := mtproto.BuildCryptoCtx(cltDecPrekeyIV, p.secret, relayInit)

	dcKey := utils.DCKey(dc, isTestDC, isMedia)
	mediaTag := ""
	if isMedia {
		mediaTag = " media"
	}
	now := time.Now()
	wsPath := utils.WSPath
	if isTestDC {
		wsPath = utils.WSPathTest
	}
	target := p.Cfg.DCRedirects[dc]
	isAnyCfFallback := p.Cfg.FallbackCfproxy || len(p.Cfg.CfproxyWorkerDomains) > 0

	p.mu.Lock()
	_, inConfig := p.Cfg.DCRedirects[dc]
	_, blacklisted := p.wsBlacklist[dcKey]
	ipFailAt := p.ipFailUntil[target]
	p.mu.Unlock()

	needFallback := !inConfig || blacklisted || (now.Before(ipFailAt) && isAnyCfFallback)
	if needFallback {
		if !inConfig {
			p.Log.Infof("[%s] DC%d not in config -> fallback", label, dc)
		} else if blacklisted {
			p.Log.Infof("[%s] DC%d%s WS blacklisted -> fallback", label, dc, mediaTag)
		} else {
			p.Log.Infof("[%s] DC%d%s WS connect to %s was timed out -> fallback", label, dc, mediaTag, target)
		}
		spr := newSplitter(relayInit, protoInt)
		ok := p.doFallback(client, client, relayInit, label, dc, isTestDC, isMedia, mediaTag, ctx, spr)
		if !ok {
			p.Log.Warnf("[%s] DC%d%s no fallback available", label, dc, mediaTag)
		}
		return
	}

	wsTimeout := 5 * time.Second
	if now.Before(p.dcKeyFailBefore(dcKey)) {
		wsTimeout = wsFailTimeout
	}

	domains := utils.WSDomains(dc, isMedia)
	allowPoolRefill := !now.Before(p.ipFailBefore(target))

	ws := (*wsconn.RawWebSocket)(nil)
	wsFailedRedirect, wsTimedOut := false, false
	allRedirects := true

	if !isTestDC {
		ws = p.WsPool.Get(dc, isMedia, target, domains, allowPoolRefill)
	}
	if ws != nil {
		p.Log.Infof("[%s] DC%d%s -> pool hit via %s", label, dc, mediaTag, target)
	} else {
		for _, domain := range domains {
			p.Log.Infof("[%s] DC%d%s -> %s via %s", label, dc, mediaTag, "wss://"+domain+wsPath, target)
			w, err := wsconn.Dial(target, domain, wsPath, wsTimeout, "")
			if err == nil {
				allRedirects = false
				ws = w
				break
			}
			if hs, ok := err.(*wsconn.WsHandshakeError); ok {
				stats.Current.WSErrors.Add(1)
				if hs.IsRedirect() {
					wsFailedRedirect = true
					p.Log.Warnf("[%s] DC%d%s got %d from %s -> %s",
						label, dc, mediaTag, hs.StatusCode, domain, hs.Location)
					continue
				}
				allRedirects = false
				p.Log.Warnf("[%s] DC%d%s WS handshake: %s", label, dc, mediaTag, hs.StatusLine)
			} else if errors.Is(err, wsconn.ErrWsTimeout) {
				stats.Current.WSErrors.Add(1)
				wsTimedOut = true
				p.Log.Warnf("[%s] DC%d%s WS connect timed out via %s", label, dc, mediaTag, domain)
				break
			} else {
				stats.Current.WSErrors.Add(1)
				allRedirects = false
				p.Log.Warnf("[%s] DC%d%s WS connect failed: %s", label, dc, mediaTag, err)
			}
		}
	}

	if ws == nil {
		p.mu.Lock()
		if wsTimedOut {
			p.ipFailUntil[target] = now.Add(ipFailCooldown)
			p.Log.Infof("[%s] DC%d%s WS connect to %s timed out, cooldown for %ds",
				label, dc, mediaTag, target, int(ipFailCooldown/time.Second))
		}
		if wsFailedRedirect && allRedirects {
			p.wsBlacklist[dcKey] = struct{}{}
			p.Log.Warnf("[%s] DC%d%s blacklisted for WS (all 302)", label, dc, mediaTag)
		} else if wsFailedRedirect {
			p.dcFailUntil[dcKey] = now.Add(dcFailCooldown)
		} else {
			p.dcFailUntil[dcKey] = now.Add(dcFailCooldown)
			p.Log.Infof("[%s] DC%d%s WS cooldown for %ds", label, dc, mediaTag, int(dcFailCooldown/time.Second))
		}
		p.mu.Unlock()

		spr := newSplitter(relayInit, protoInt)
		ok := p.doFallback(client, client, relayInit, label, dc, isTestDC, isMedia, mediaTag, ctx, spr)
		if ok {
			p.Log.Infof("[%s] DC%d%s fallback closed", label, dc, mediaTag)
		}
		return
	}

	p.mu.Lock()
	delete(p.dcFailUntil, dcKey)
	delete(p.ipFailUntil, target)
	p.mu.Unlock()
	p.WsPool.ReportSuccess(dc, isMedia)
	stats.Current.ConnectionsWS.Add(1)

	spr := newSplitter(relayInit, protoInt)
	if err := ws.Send(relayInit); err != nil {
		p.Log.Warnf("[%s] DC%d%s failed to send relay init: %s", label, dc, mediaTag, err)
		ws.Close()
		return
	}

	dcTag := "DC" + itoa(dc) + mediaTag
	p.bridgeWS(client, client, ws, ctx, spr, label, dcTag)
}
