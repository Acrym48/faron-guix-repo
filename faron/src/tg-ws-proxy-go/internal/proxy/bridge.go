// Package proxy implements the MTProto-to-WebSocket bridge server: client
// handshake handling, re-encryption bridges, fallback routing and the TCP
// listener lifecycle.
package proxy

import (
	"errors"
	"io"
	"net"
	"net/url"
	"sync"
	"time"

	"tg-ws-proxy-go/internal/balancer"
	"tg-ws-proxy-go/internal/config"
	"tg-ws-proxy-go/internal/mtproto"
	"tg-ws-proxy-go/internal/splitter"
	"tg-ws-proxy-go/internal/stats"
	"tg-ws-proxy-go/internal/utils"
	"tg-ws-proxy-go/internal/wsconn"
)

// endConn is the client-side endpoint used by the bridges: either the raw
// TCP connection or a FakeTlsStream that wraps writes in TLS records.
type endConn interface {
	io.Reader
	io.Writer
	io.Closer
}

// clientHalf adapts a buffered reader + a writer into an endConn, keeping the
// read side buffered so leftover handshake bytes are not lost.
type clientHalf struct {
	r io.Reader
	w io.Writer
	c net.Conn
}

func (h *clientHalf) Read(p []byte) (int, error)  { return h.r.Read(p) }
func (h *clientHalf) Write(p []byte) (int, error) { return h.w.Write(p) }
func (h *clientHalf) Close() error                { return h.c.Close() }

const readChunkSize = 65536

func newSplitter(relayInit []byte, proto uint32) *splitter.MsgSplitter {
	s, err := splitter.NewMsgSplitter(relayInit, proto)
	if err != nil {
		return nil
	}
	return s
}

func isEOF(err error) bool { return errors.Is(err, io.EOF) }

// bridgeWS re-encrypts bidirectionally between the client endpoint and a
// WebSocket upstream. Each inbound MTProto packet is sent as one WS frame.
func (p *Proxy) bridgeWS(clientR, clientW endConn, ws *wsconn.RawWebSocket,
	ctx *mtproto.CryptoCtx, spr *splitter.MsgSplitter, label, dcTag string) {

	var (
		mu                 sync.Mutex
		upBytes, downBytes int64
		upPkts, downPkts   int64
	)
	closeReason := ""
	started := time.Now()

	done := make(chan struct{})
	var once sync.Once
	finish := func() { once.Do(func() { close(done) }) }

	go func() {
		defer finish()
		buf := make([]byte, readChunkSize)
		for {
			n, err := clientR.Read(buf)
			chunk := buf[:n]
			if n > 0 {
				n64 := int64(n)
				stats.Current.BytesUp.Add(n64)
				plain := make([]byte, n)
				ctx.CltDec.XORKeyStream(plain, chunk)
				relay := make([]byte, n)
				ctx.TgEnc.XORKeyStream(relay, plain)

				var sErr error
				if spr != nil {
					parts := spr.Split(relay)
					if len(parts) > 1 {
						sErr = ws.SendBatch(parts)
					} else if len(parts) == 1 {
						sErr = ws.Send(parts[0])
					}
				} else {
					sErr = ws.Send(relay)
				}
				if sErr != nil {
					mu.Lock()
					closeReason = "client error: " + typeName(sErr)
					mu.Unlock()
					return
				}
				mu.Lock()
				upBytes += n64
				upPkts++
				mu.Unlock()
			}

			if err != nil {
				if isEOF(err) {
					if spr != nil {
						if tail := spr.Flush(); len(tail) > 0 {
							_ = ws.Send(tail)
						}
					}
					mu.Lock()
					closeReason = "client closed"
					mu.Unlock()
					return
				}
				mu.Lock()
				closeReason = "client error: " + typeName(err)
				mu.Unlock()
				return
			}
		}
	}()

	go func() {
		defer finish()
		for {
			data, err := ws.Recv()
			if data == nil {
				mu.Lock()
				if closeReason == "" {
					closeReason = "upstream closed"
				}
				mu.Unlock()
				return
			}
			if err != nil {
				mu.Lock()
				closeReason = "upstream error: " + typeName(err)
				mu.Unlock()
				return
			}
			n64 := int64(len(data))
			stats.Current.BytesDown.Add(n64)
			plain := make([]byte, len(data))
			ctx.TgDec.XORKeyStream(plain, data)
			out := make([]byte, len(data))
			ctx.CltEnc.XORKeyStream(out, plain)
			if _, wErr := clientW.Write(out); wErr != nil {
				mu.Lock()
				closeReason = "client error: " + typeName(wErr)
				mu.Unlock()
				return
			}
			mu.Lock()
			downBytes += n64
			downPkts++
			mu.Unlock()
		}
	}()

	<-done
	// Stop whatever goroutine is still blocked.
	if c, ok := clientW.(io.Closer); ok {
		_ = c.Close()
	}
	ws.Close()

	mu.Lock()
	elapsed := time.Since(started)
	reason := closeReason
	if reason == "" {
		reason = "closed"
	}
	upB, upP, downB, downP := upBytes, upPkts, downBytes, downPkts
	mu.Unlock()

	p.Log.Infof("[%s] %s ended (%s): \u2191%s (%d %s) \u2193%s (%d %s) in %.1fs",
		label, dcTag, reason,
		utils.HumanBytes(upB), upP, pluralPkts(upP),
		utils.HumanBytes(downB), downP, pluralPkts(downP),
		elapsed.Seconds())
}

// bridgeTCP re-encrypts between the client endpoint and a raw TCP upstream.
func (p *Proxy) bridgeTCP(clientR, clientW endConn, remote io.ReadWriteCloser,
	ctx *mtproto.CryptoCtx, label string) {

	var (
		mu                 sync.Mutex
		upBytes, downBytes int64
	)
	closeReason := ""
	started := time.Now()
	done := make(chan struct{})
	var once sync.Once
	finish := func() { once.Do(func() { close(done) }) }

	go func() {
		defer finish()
		buf := make([]byte, readChunkSize)
		for {
			n, err := clientR.Read(buf)
			if n > 0 {
				stats.Current.BytesUp.Add(int64(n))
				plain := make([]byte, n)
				ctx.CltDec.XORKeyStream(plain, buf[:n])
				relay := make([]byte, n)
				ctx.TgEnc.XORKeyStream(relay, plain)
				if _, wErr := remote.Write(relay); wErr != nil {
					mu.Lock()
					closeReason = "client error: " + typeName(wErr)
					mu.Unlock()
					return
				}
				mu.Lock()
				upBytes += int64(n)
				mu.Unlock()
			}
			if err != nil {
				if isEOF(err) {
					mu.Lock()
					closeReason = "client closed"
					mu.Unlock()
				} else {
					mu.Lock()
					closeReason = "client error: " + typeName(err)
					mu.Unlock()
				}
				return
			}
		}
	}()

	go func() {
		defer finish()
		buf := make([]byte, readChunkSize)
		for {
			n, err := remote.Read(buf)
			if n > 0 {
				stats.Current.BytesDown.Add(int64(n))
				plain := make([]byte, n)
				ctx.TgDec.XORKeyStream(plain, buf[:n])
				out := make([]byte, n)
				ctx.CltEnc.XORKeyStream(out, plain)
				if _, wErr := clientW.Write(out); wErr != nil {
					mu.Lock()
					closeReason = "client error: " + typeName(wErr)
					mu.Unlock()
					return
				}
				mu.Lock()
				downBytes += int64(n)
				mu.Unlock()
			}
			if err != nil {
				if isEOF(err) {
					mu.Lock()
					closeReason = "upstream closed"
					mu.Unlock()
				} else {
					mu.Lock()
					closeReason = "upstream error: " + typeName(err)
					mu.Unlock()
				}
				return
			}
		}
	}()

	<-done
	if c, ok := clientW.(io.Closer); ok {
		_ = c.Close()
	}
	_ = remote.Close()

	mu.Lock()
	elapsed := time.Since(started)
	reason := closeReason
	if reason == "" {
		reason = "closed"
	}
	upB, downB := upBytes, downBytes
	mu.Unlock()

	p.Log.Infof("[%s] TCP ended (%s): \u2191%s \u2193%s in %.1fs",
		label, reason, utils.HumanBytes(upB), utils.HumanBytes(downB), elapsed.Seconds())
}

// doFallback tries the fallback chain in order:
// cf_worker -> cf proxy -> direct tcp. Mirrors `do_fallback`.
func (p *Proxy) doFallback(clientR, clientW endConn, relayInit []byte,
	label string, dc int, isTestDC, isMedia bool, mediaTag string,
	ctx *mtproto.CryptoCtx, spr *splitter.MsgSplitter) bool {

	ipTable := config.DCTestIPs
	if !isTestDC {
		ipTable = config.DCDefaultIPs
	}
	fallbackDst := ipTable[dc]
	useCf := p.Cfg.FallbackCfproxy && !isTestDC
	workerDomains := p.Cfg.CfproxyWorkerDomains

	var methods []string
	if p.Cfg.FallbackSet {
		// Explicit --fallback chain wins; availability still applies.
		for _, m := range p.Cfg.FallbackMethods {
			switch m {
			case "cf_worker":
				if len(workerDomains) > 0 && fallbackDst != "" {
					methods = append(methods, m)
				}
			case "cf":
				methods = append(methods, m)
			case "tcp":
				if fallbackDst != "" {
					methods = append(methods, m)
				}
			}
		}
	} else {
		if len(workerDomains) > 0 && fallbackDst != "" {
			methods = append(methods, "cf_worker")
		}
		if useCf {
			methods = append(methods, "cf")
		}
		if fallbackDst != "" {
			methods = append(methods, "tcp")
		}
	}

	for _, method := range methods {
		switch method {
		case "cf_worker":
			ok := p.cfWorkerFallback(clientR, clientW, relayInit, label, ctx,
				dc, isTestDC, isMedia, fallbackDst, spr)
			if ok {
				return true
			}
		case "cf":
			ok := p.cfFallback(clientR, clientW, relayInit, label, ctx,
				dc, isMedia, spr)
			if ok {
				return true
			}
		case "tcp":
			p.Log.Infof("[%s] DC%d%s -> TCP fallback to %s:443", label, dc, mediaTag, fallbackDst)
			ok := p.tcpFallback(clientR, clientW, fallbackDst, 443, relayInit, label, ctx)
			if ok {
				return true
			}
		}
	}
	return false
}

func (p *Proxy) cfWorkerFallback(clientR, clientW endConn, relayInit []byte,
	label string, ctx *mtproto.CryptoCtx, dc int, isTestDC, isMedia bool,
	fallbackDst string, spr *splitter.MsgSplitter) bool {

	mediaTag := ""
	if isMedia {
		mediaTag = " media"
	}
	workerDomains := p.Cfg.CfproxyWorkerDomains
	if len(workerDomains) == 0 {
		return false
	}

	var ws *wsconn.RawWebSocket
	var workerDomain string
	if !isTestDC {
		ws, workerDomain = p.CfPool.Get(dc, fallbackDst, workerDomains)
	}
	if ws == nil && workerDomain != "" {
		p.Log.Infof("[%s] DC%d%s -> CF worker pool hit via %s for %s", label, dc, mediaTag, workerDomain, fallbackDst)
	} else if ws == nil {
		path := "/apiws?" + url.Values{"dst": {fallbackDst}, "dc": {itoa(dc)}}.Encode()
		for _, candidate := range p.CfPool.AvailableDomains(workerDomains) {
			p.Log.Infof("[%s] DC%d%s -> trying CF worker %s for %s", label, dc, mediaTag, candidate, fallbackDst)
			w, err := wsconn.Dial(candidate, candidate, path, 10*time.Second, "")
			if err != nil {
				p.CfPool.ReportFailure(candidate, err)
				p.Log.Warnf("[%s] DC%d%s CF worker %s failed: %s", label, dc, mediaTag, candidate, err)
				continue
			}
			ws = w
			workerDomain = candidate
			break
		}
		if ws == nil {
			return false
		}
	}

	stats.Current.ConnectionsCfproxy.Add(1)
	if err := ws.Send(relayInit); err != nil {
		ws.Close()
		return false
	}
	dcTag := "DC" + itoa(dc)
	p.bridgeWS(clientR, clientW, ws, ctx, nil, label, dcTag)
	return true
}

func (p *Proxy) cfFallback(clientR, clientW endConn, relayInit []byte,
	label string, ctx *mtproto.CryptoCtx, dc int, isMedia bool, spr *splitter.MsgSplitter) bool {

	mediaTag := ""
	if isMedia {
		mediaTag = " media"
	}
	p.Log.Infof("[%s] DC%d%s -> trying CF proxy", label, dc, mediaTag)

	chosenDomain := ""
	var ws *wsconn.RawWebSocket
	for _, baseDomain := range balancer.Default.DomainsForDC(dc) {
		domain := "kws" + itoa(dc) + "." + baseDomain
		w, err := wsconn.Dial(domain, domain, utils.WSPath, 10*time.Second, "")
		if err != nil {
			p.Log.Warnf("[%s] DC%d%s CF proxy failed: %s", label, dc, mediaTag, err)
			continue
		}
		ws = w
		chosenDomain = baseDomain
		break
	}
	if ws == nil {
		return false
	}

	if chosenDomain != "" && balancer.Default.UpdateDomainForDC(dc, chosenDomain) {
		p.Log.Infof("[%s] Switched active CF domain", label)
	}

	stats.Current.ConnectionsCfproxy.Add(1)
	if err := ws.Send(relayInit); err != nil {
		ws.Close()
		return false
	}
	dcTag := "DC" + itoa(dc)
	p.bridgeWS(clientR, clientW, ws, ctx, spr, label, dcTag)
	return true
}

func (p *Proxy) tcpFallback(clientR, clientW endConn, dst string, port int,
	relayInit []byte, label string, ctx *mtproto.CryptoCtx) bool {

	remote, err := net.DialTimeout("tcp", net.JoinHostPort(dst, itoa(port)), 10*time.Second)
	if err != nil {
		p.Log.Warnf("[%s] TCP fallback to %s:%d failed: %s", label, dst, port, err)
		return false
	}
	if tc, ok := remote.(*net.TCPConn); ok {
		_ = tc.SetNoDelay(true)
	}

	stats.Current.ConnectionsTCPFallback.Add(1)
	if _, err := remote.Write(relayInit); err != nil {
		remote.Close()
		return false
	}
	p.bridgeTCP(clientR, clientW, remote, ctx, label)
	return true
}

func typeName(err error) string {
	if err == nil {
		return ""
	}
	return errName(err)
}
