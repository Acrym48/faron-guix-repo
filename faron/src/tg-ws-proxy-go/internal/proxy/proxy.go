// Package proxy implements the MTProto-to-WebSocket bridge server: client
// handshake handling, re-encryption bridges, fallback routing and the TCP
// listener lifecycle.
package proxy

import (
	"io"
	"os"
	"sync"
	"time"

	"tg-ws-proxy-go/internal/config"
	"tg-ws-proxy-go/internal/pool"
	"tg-ws-proxy-go/internal/xlog"
)

// Proxy wires configuration, pools and per-connection failure state.
type Proxy struct {
	Cfg      *config.Config
	Log      *xlog.Logger
	WsPool   *pool.WsPool
	CfPool   *pool.CfWorkerPool
	CfDomain *config.CfDomainManager

	// Out receives the startup banner; defaults to stderr.
	Out io.Writer

	mu          sync.Mutex
	wsBlacklist map[string]struct{}
	dcFailUntil map[string]time.Time
	ipFailUntil map[string]time.Time

	secret []byte
}

// New builds a Proxy from the given config; pools own their goroutines.
func New(cfg *config.Config, log *xlog.Logger) *Proxy {
	return &Proxy{
		Cfg:      cfg,
		Log:      log,
		WsPool:   pool.NewWsPool(cfg, log.Slogger()),
		CfPool:   pool.NewCfWorkerPool(cfg, log.Slogger()),
		CfDomain: config.NewCfDomainManager(),
		secret:   hexSecret(cfg.Secret),
		Out:      os.Stderr,

		wsBlacklist: make(map[string]struct{}),
		dcFailUntil: make(map[string]time.Time),
		ipFailUntil: make(map[string]time.Time),
	}
}

func (p *Proxy) resetState() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.wsBlacklist = make(map[string]struct{})
	p.dcFailUntil = make(map[string]time.Time)
	p.ipFailUntil = make(map[string]time.Time)
}
