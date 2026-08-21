// Package pool manages reusable WebSocket connections: the main WS pool per
// DC (media/non-media) and the Cloudflare Worker fallback pool.
package pool

import (
	"context"
	"log/slog"
	"math/rand"
	"sync"
	"time"

	"tg-ws-proxy-go/internal/config"
	"tg-ws-proxy-go/internal/stats"
	"tg-ws-proxy-go/internal/utils"
	"tg-ws-proxy-go/internal/wsconn"
)

const (
	maxIdleAge        = 120 * time.Second
	refillBackoffBase = 60 * time.Second
	refillBackoffMax  = 3600 * time.Second
	cfIdleAge         = 100 * time.Second
	cfPerDCLimit      = 1
)

type dcWsKey struct {
	dc      int
	isMedia bool
}

type idleWs struct {
	ws      *wsconn.RawWebSocket
	created time.Time
}

// WsPool mirrors the Python `_WsPool`.
type WsPool struct {
	cfg *config.Config
	log *slog.Logger

	mu            sync.Mutex
	idle          map[dcWsKey][]idleWs
	refilling     map[dcWsKey]bool
	rotating      map[dcWsKey]bool
	refillFails   map[dcWsKey]int
	refillAfter   map[dcWsKey]time.Time
	tryFrontFirst bool

	ctx    context.Context
	cancel context.CancelFunc
}

func NewWsPool(cfg *config.Config, log *slog.Logger) *WsPool {
	ctx, cancel := context.WithCancel(context.Background())
	return &WsPool{
		cfg:         cfg,
		log:         log,
		idle:        make(map[dcWsKey][]idleWs),
		refilling:   make(map[dcWsKey]bool),
		rotating:    make(map[dcWsKey]bool),
		refillFails: make(map[dcWsKey]int),
		refillAfter: make(map[dcWsKey]time.Time),
		ctx:         ctx,
		cancel:      cancel,
	}
}

// Get pops a live pooled connection for the DC, or schedules a refill.
func (p *WsPool) Get(dc int, isMedia bool, targetIP string, domains []string, allowRefill bool) *wsconn.RawWebSocket {
	key := dcWsKey{dc, isMedia}
	now := time.Now()

	p.mu.Lock()
	bucket := p.idle[key]
	for len(bucket) > 0 {
		item := bucket[len(bucket)-1]
		bucket = bucket[:len(bucket)-1]
		if now.Sub(item.created) > maxIdleAge || item.ws.IsClosed() {
			go item.ws.Close()
			continue
		}
		p.idle[key] = bucket
		p.reportSuccessLocked(key, now)
		p.mu.Unlock()
		stats.Current.PoolHits.Add(1)
		if allowRefill {
			p.scheduleRefill(key, targetIP, domains)
		}
		return item.ws
	}
	p.idle[key] = bucket
	p.mu.Unlock()

	stats.Current.PoolMisses.Add(1)
	if allowRefill {
		p.scheduleRefill(key, targetIP, domains)
	}
	return nil
}

func (p *WsPool) reportSuccess(key dcWsKey, now time.Time) {
	p.refillFails[key] = 0
	delete(p.refillAfter, key)
}

// reportSuccessLocked resets the failure backoff; caller holds p.mu.
func (p *WsPool) reportSuccessLocked(key dcWsKey, now time.Time) {
	p.refillFails[key] = 0
	delete(p.refillAfter, key)
}

// ReportSuccess resets the failure backoff for a DC bucket.
func (p *WsPool) ReportSuccess(dc int, isMedia bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.reportSuccessLocked(dcWsKey{dc, isMedia}, time.Now())
}

func (p *WsPool) scheduleRefill(key dcWsKey, targetIP string, domains []string) {
	p.mu.Lock()
	refilling := p.refilling[key]
	backoff := p.refillAfter[key]
	p.mu.Unlock()
	if refilling || time.Now().Before(backoff) {
		return
	}
	p.mu.Lock()
	if p.refilling[key] {
		p.mu.Unlock()
		return
	}
	p.refilling[key] = true
	ctx := p.ctx
	p.mu.Unlock()
	go p.refill(ctx, key, targetIP, domains)
}

func (p *WsPool) refill(ctx context.Context, key dcWsKey, targetIP string, domains []string) {
	defer func() {
		p.mu.Lock()
		p.refilling[key] = false
		p.mu.Unlock()
	}()

	// reconnect the bucket from a fresh slice to avoid stale cap
	p.mu.Lock()
	bucket := cloneIdle(p.idle[key])
	needed := p.cfg.PoolSize - len(bucket)
	p.mu.Unlock()
	if needed <= 0 {
		return
	}

	connected := 0
	var wg sync.WaitGroup
	var mu sync.Mutex
	for i := 0; i < needed; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ws := p.connectOne(ctx, targetIP, domains)
			if ws == nil {
				return
			}
			mu.Lock()
			if connected < needed {
				connected++
				p.mu.Lock()
				p.idle[key] = append(p.idle[key], idleWs{ws: ws, created: time.Now()})
				p.mu.Unlock()
				p.scheduleRotation(key)
			} else {
				go ws.Close()
			}
			mu.Unlock()
		}()
	}
	wg.Wait()

	p.mu.Lock()
	if connected > 0 {
		p.reportSuccessLocked(key, time.Now())
	} else {
		p.refillFails[key]++
		fails := p.refillFails[key]
		delay := refillBackoffBase * time.Duration(1<<minInt(fails-1, 6))
		if delay > refillBackoffMax {
			delay = refillBackoffMax
		}
		p.refillAfter[key] = time.Now().Add(delay)
		p.log.Info("WS pool refill failed",
			"dc", key.dc, "media", key.isMedia, "retry", delay.Round(time.Second))
	}
	p.mu.Unlock()
}

func (p *WsPool) connectOne(ctx context.Context, targetIP string, domains []string) *wsconn.RawWebSocket {
	for _, domain := range domains {
		if p.tryFrontFirst {
			if ws := p.connectOption(ctx, targetIP, domain, 7*time.Second, "sprinthost.ru"); ws != nil {
				stats.Current.ConnectionsFronting.Add(1)
				p.mu.Lock()
				p.tryFrontFirst = true
				p.mu.Unlock()
				return ws
			}
		}
		ws, err := wsconn.Dial(targetIP, domain, utils.WSPath, 8*time.Second, "")
		if err == nil {
			p.mu.Lock()
			p.tryFrontFirst = false
			p.mu.Unlock()
			return ws
		}
		if isCtxDone(ctx) {
			return nil
		}
		if hs, ok := err.(*wsconn.WsHandshakeError); ok {
			if hs.IsRedirect() {
				continue
			}
			return nil
		}
		if wsconn.ErrWsTimeout == err {
			// relay-side connect timed out -> try the fronting trick
			if ws := p.connectOption(ctx, targetIP, domain, 7*time.Second, "sprinthost.ru"); ws != nil {
				stats.Current.ConnectionsFronting.Add(1)
				p.mu.Lock()
				p.tryFrontFirst = true
				p.mu.Unlock()
				return ws
			}
			continue
		}
		return nil
	}
	return nil
}

func (p *WsPool) connectOption(ctx context.Context, targetIP, domain string, timeout time.Duration, sni string) *wsconn.RawWebSocket {
	if isCtxDone(ctx) {
		return nil
	}
	ws, err := wsconn.Dial(targetIP, domain, utils.WSPath, timeout, sni)
	if err != nil {
		return nil
	}
	return ws
}

func (p *WsPool) scheduleRotation(key dcWsKey) {
	p.mu.Lock()
	if p.rotating[key] {
		p.mu.Unlock()
		return
	}
	p.rotating[key] = true
	ctx := p.ctx
	p.mu.Unlock()
	go p.rotate(ctx, key)
}

func (p *WsPool) rotate(ctx context.Context, key dcWsKey) {
	defer func() {
		p.mu.Lock()
		delete(p.rotating, key)
		p.mu.Unlock()
	}()

	check := time.NewTicker(5 * time.Second)
	defer check.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-check.C:
			p.mu.Lock()
			bucket := p.idle[key]
			var keep []idleWs
			var expired []*wsconn.RawWebSocket
			for _, item := range bucket {
				if time.Since(item.created) >= maxIdleAge || item.ws.IsClosed() {
					expired = append(expired, item.ws)
				} else {
					keep = append(keep, item)
				}
			}
			p.idle[key] = keep
			empty := len(keep) == 0
			p.mu.Unlock()

			for _, ws := range expired {
				go ws.Close()
			}
			if len(expired) > 0 {
				p.scheduleRefill(key, p.cfg.DCRedirects[key.dc], utils.WSDomains(key.dc, key.isMedia))
			}
			if empty {
				return
			}
		}
	}
}

// Warmup pre-fills every configured DC bucket.
func (p *WsPool) Warmup() {
	for dc, ip := range p.cfg.DCRedirects {
		for _, isMedia := range []bool{false, true} {
			key := dcWsKey{dc, isMedia}
			p.scheduleRefill(key, ip, utils.WSDomains(dc, isMedia))
		}
	}
	p.log.Info("WS pool warmup started")
}

// Reset cancels background tasks and clears state (mirrors Python reset).
func (p *WsPool) Reset() {
	p.cancel()
	p.mu.Lock()
	for _, bucket := range p.idle {
		for _, item := range bucket {
			go item.ws.Close()
		}
	}
	p.idle = make(map[dcWsKey][]idleWs)
	p.refilling = make(map[dcWsKey]bool)
	p.rotating = make(map[dcWsKey]bool)
	p.refillFails = make(map[dcWsKey]int)
	p.refillAfter = make(map[dcWsKey]time.Time)
	p.tryFrontFirst = false
	p.mu.Unlock()
	p.ctx, p.cancel = context.WithCancel(context.Background())
}

type cfIdle struct {
	ws           *wsconn.RawWebSocket
	created      time.Time
	workerDomain string
}

// CfWorkerPool mirrors the Python `_CfWorkerPool`.
type CfWorkerPool struct {
	cfg *config.Config
	log *slog.Logger

	mu             sync.Mutex
	idle           map[int][]cfIdle
	refilling      map[int]bool
	exhaustedUntil map[string]time.Time

	ctx    context.Context
	cancel context.CancelFunc
}

func NewCfWorkerPool(cfg *config.Config, log *slog.Logger) *CfWorkerPool {
	ctx, cancel := context.WithCancel(context.Background())
	return &CfWorkerPool{
		cfg:            cfg,
		log:            log,
		idle:           make(map[int][]cfIdle),
		refilling:      make(map[int]bool),
		exhaustedUntil: make(map[string]time.Time),
		ctx:            ctx,
		cancel:         cancel,
	}
}

// Get returns a pooled worker connection for the DC, if any.
func (p *CfWorkerPool) Get(dc int, fallbackDst string, workerDomains []string) (*wsconn.RawWebSocket, string) {
	now := time.Now()
	p.mu.Lock()
	bucket := p.idle[dc]
	for len(bucket) > 0 {
		item := bucket[len(bucket)-1]
		bucket = bucket[:len(bucket)-1]
		if now.Sub(item.created) > cfIdleAge || item.ws.IsClosed() {
			go item.ws.Close()
			continue
		}
		p.idle[dc] = bucket
		domain := item.workerDomain
		p.mu.Unlock()
		stats.Current.CfPoolHits.Add(1)
		p.scheduleRefill(dc, fallbackDst, workerDomains)
		return item.ws, domain
	}
	p.idle[dc] = bucket
	p.mu.Unlock()

	stats.Current.CfPoolMisses.Add(1)
	return nil, ""
}

func (p *CfWorkerPool) scheduleRefill(dc int, fallbackDst string, workerDomains []string) {
	p.mu.Lock()
	if p.refilling[dc] {
		p.mu.Unlock()
		return
	}
	p.refilling[dc] = true
	ctx := p.ctx
	p.mu.Unlock()
	go p.refill(ctx, dc, fallbackDst, workerDomains)
}

func (p *CfWorkerPool) refill(ctx context.Context, dc int, fallbackDst string, workerDomains []string) {
	defer func() {
		p.mu.Lock()
		p.refilling[dc] = false
		p.mu.Unlock()
	}()

	p.mu.Lock()
	target := p.cfg.PoolSize
	if target > cfPerDCLimit {
		target = cfPerDCLimit
	}
	needed := target - len(p.idle[dc])
	p.mu.Unlock()
	if needed <= 0 {
		return
	}

	for i := 0; i < needed; i++ {
		if isCtxDone(ctx) {
			return
		}
		ws, workerDomain := p.connectOne(ctx, workerDomains, fallbackDst, dc)
		if ws == nil {
			break
		}
		p.mu.Lock()
		p.idle[dc] = append(p.idle[dc], cfIdle{ws: ws, created: time.Now(), workerDomain: workerDomain})
		p.mu.Unlock()
	}
}

func (p *CfWorkerPool) connectOne(ctx context.Context, workerDomains []string, fallbackDst string, dc int) (*wsconn.RawWebSocket, string) {
	for _, workerDomain := range p.AvailableDomains(workerDomains) {
		path := "/apiws?dst=" + fallbackDst + "&dc=" + itoa(dc)
		ws, err := wsconn.Dial(workerDomain, workerDomain, path, 8*time.Second, "")
		if err == nil {
			return ws, workerDomain
		}
		p.ReportFailure(workerDomain, err)
		if isCtxDone(ctx) {
			return nil, ""
		}
	}
	return nil, ""
}

// AvailableDomains returns worker domains not currently exhausted, shuffled.
func (p *CfWorkerPool) AvailableDomains(workerDomains []string) []string {
	now := time.Now()
	p.mu.Lock()
	defer p.mu.Unlock()
	seen := make(map[string]struct{})
	var out []string
	for _, d := range workerDomains {
		if _, dup := seen[d]; dup {
			continue
		}
		seen[d] = struct{}{}
		if ex, ok := p.exhaustedUntil[d]; ok && !now.Before(ex) {
			delete(p.exhaustedUntil, d)
		}
		if ex, ok := p.exhaustedUntil[d]; ok && now.Before(ex) {
			continue
		}
		out = append(out, d)
	}
	rand.Shuffle(len(out), func(i, j int) { out[i], out[j] = out[j], out[i] })
	return out
}

// ReportFailure is currently a no-op (Python guards daily-limit handling).
func (p *CfWorkerPool) ReportFailure(workerDomain string, err error) {}

// Warmup pre-fills fallback worker connections for DCs not in dc_redirects.
func (p *CfWorkerPool) Warmup() {
	if len(p.cfg.CfproxyWorkerDomains) == 0 {
		return
	}
	for dc, ip := range config.DCDefaultIPs {
		if _, ok := p.cfg.DCRedirects[dc]; ok {
			continue
		}
		p.scheduleRefill(dc, ip, p.cfg.CfproxyWorkerDomains)
	}
	p.log.Info("CF worker pool warmup started")
}

// Reset clears the pool state.
func (p *CfWorkerPool) Reset() {
	p.cancel()
	p.mu.Lock()
	for _, bucket := range p.idle {
		for _, item := range bucket {
			go item.ws.Close()
		}
	}
	p.idle = make(map[int][]cfIdle)
	p.refilling = make(map[int]bool)
	p.exhaustedUntil = make(map[string]time.Time)
	p.mu.Unlock()
	p.ctx, p.cancel = context.WithCancel(context.Background())
}

func cloneIdle(in []idleWs) []idleWs {
	out := make([]idleWs, len(in))
	copy(out, in)
	return out
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func isCtxDone(ctx context.Context) bool {
	select {
	case <-ctx.Done():
		return true
	default:
		return false
	}
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	neg := i < 0
	if neg {
		i = -i
	}
	var b [20]byte
	pos := len(b)
	for i > 0 {
		pos--
		b[pos] = byte('0' + i%10)
		i /= 10
	}
	if neg {
		pos--
		b[pos] = '-'
	}
	return string(b[pos:])
}
