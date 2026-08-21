// Command tg-ws-proxy is a Go port of the tg-ws-proxy core: a local MTProto
// proxy that bridges Telegram Desktop traffic over WebSocket connections.
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"

	"tg-ws-proxy-go/internal/config"
	"tg-ws-proxy-go/internal/proxy"
	"tg-ws-proxy-go/internal/xlog"
)

var defaultDCIPs = []string{"2:149.154.167.220", "4:149.154.167.220"}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run() error {
	fs := flag.NewFlagSet("tg-ws-proxy", flag.ExitOnError)
	fs.Usage = func() {
		fmt.Fprintln(os.Stderr, "Usage: tg-ws-proxy [flags] [dc-ips...]")
		fs.PrintDefaults()
	}

	port := fs.Int("port", envInt("TG_WS_PROXY_PORT", 1443), "listen port (default 1443)")
	host := fs.String("host", envStr("TG_WS_PROXY_HOST", "127.0.0.1"), "listen host (default 127.0.0.1)")
	secret := fs.String("secret", envStr("TG_WS_PROXY_SECRET", ""), "MTProto proxy secret (32 hex chars); auto-generated if empty")
	verbose := fs.Bool("v", false, "debug logging")
	logFile := fs.String("log-file", "", "log to file with rotation (default: stderr only)")
	logMaxMB := fs.Float64("log-max-mb", 5, "max log file size in MB before rotation (default 5)")
	logBackups := fs.Int("log-backups", 1, "number of rotated log files to keep (min 1)")
	bufKB := fs.Int("buf-kb", 256, "socket send/recv buffer size in KB (default 256)")
	poolSize := fs.Int("pool-size", 4, "WS connection pool size per DC (default 4, min 0)")
	noCf := fs.Bool("no-cfproxy", false, "disable Cloudflare proxy fallback (auto chain only)")
	fallback := fs.String("fallback", "", "explicit fallback chain, e.g. \"cloudflare\" (cf), \"cf_worker,tcp\" or \"off\"; overrides --no-cfproxy")
	fakeTls := fs.String("fake-tls-domain", "", "enable Fake TLS (ee-secret) masking with the given SNI domain")
	forceTestDC := fs.Bool("force-test-dc", false, "force ALL traffic to Telegram TEST datacenters")
	proxyProto := fs.Bool("proxy-protocol", false, "accept PROXY protocol v1 header")

	var dcIPs, cfDomains, cfWorkerDomains []string
	var dcVisited bool
	fs.Func("dc-ip", "target IP for a DC, e.g. 2:149.154.167.220 (repeatable)", func(v string) error {
		dcIPs = append(dcIPs, v)
		return nil
	})
	fs.Func("cfproxy-domain", "user defined Cloudflare-proxied domain for WS fallback (repeatable)", func(v string) error {
		cfDomains = append(cfDomains, v)
		return nil
	})
	fs.Func("cfproxy-worker-domain", "Cloudflare Worker domain for WS fallback (repeatable)", func(v string) error {
		cfWorkerDomains = append(cfWorkerDomains, v)
		return nil
	})

	if err := fs.Parse(os.Args[1:]); err != nil {
		return err
	}
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "dc-ip" {
			dcVisited = true
		}
	})

	if env := os.Getenv("TG_WS_PROXY_CF_WORKER"); env != "" {
		cfWorkerDomains = append(cfWorkerDomains, strings.Fields(env)...)
	}
	if !dcVisited {
		if env := os.Getenv("TG_WS_PROXY_DC_IPS"); env != "" {
			dcIPs = strings.Fields(env)
		} else {
			dcIPs = defaultDCIPs
		}
	}

	secretHex := strings.TrimSpace(*secret)
	if secretHex == "" {
		buf := make([]byte, 16)
		if _, err := rand.Read(buf); err != nil {
			return err
		}
		secretHex = hex.EncodeToString(buf)
		fmt.Fprintf(os.Stderr, "Generated secret: %s\n", secretHex)
	} else if len(secretHex) != 32 {
		return fmt.Errorf("secret must be exactly 32 hex characters")
	} else if _, err := hex.DecodeString(secretHex); err != nil {
		return fmt.Errorf("secret must be valid hex")
	}

	dcRedirects, err := config.ParseDcIpList(dcIPs)
	if err != nil {
		return err
	}

	cfg := config.New()
	cfg.Port = *port
	cfg.Host = *host
	cfg.Secret = secretHex
	cfg.DCRedirects = dcRedirects
	cfg.BufferSize = max(4, *bufKB) * 1024
	cfg.PoolSize = max(0, *poolSize)
	cfg.FallbackCfproxy = !*noCf
	if *fallback != "" {
		methods, set, ferr := config.ParseFallbackChain(*fallback)
		if ferr != nil {
			return ferr
		}
		cfg.FallbackSet = set
		cfg.FallbackMethods = methods
	}
	cfg.CfproxyUserDomains = config.CoerceDomainList(cfDomains)
	cfg.CfproxyWorkerDomains = config.CoerceDomainList(cfWorkerDomains)
	cfg.FakeTlsDomain = strings.TrimSpace(*fakeTls)
	cfg.ProxyProtocol = *proxyProto
	cfg.ForceTestDC = *forceTestDC

	level := slog.LevelInfo
	if *verbose {
		level = slog.LevelDebug
	}

	var logOut *rotatingWriter
	var logDest io.Writer = os.Stderr
	if *logFile != "" {
		logOut = newRotatingWriter(*logFile, int64(*logMaxMB*1024*1024), max(1, *logBackups))
		defer logOut.Close()
		logDest = logOut
	}
	handler := xlog.NewPrettyHandler(logDest, level)
	slog.SetDefault(slog.New(handler))
	log := xlog.New(slog.Default())

	p := proxy.New(cfg, log)
	if logOut != nil {
		p.Out = logOut
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	return p.Run(ctx)
}

func envStr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		var n int
		if _, err := fmt.Sscanf(v, "%d", &n); err == nil {
			return n
		}
	}
	return def
}

// rotatingWriter implements simple size-based log rotation with N backups.
type rotatingWriter struct {
	mu       sync.Mutex
	path     string
	maxBytes int64
	backups  int

	f    *os.File
	size int64
}

func newRotatingWriter(path string, maxBytes int64, backups int) *rotatingWriter {
	w := &rotatingWriter{path: path, maxBytes: maxBytes, backups: backups}
	w.open()
	return w
}

func (w *rotatingWriter) open() {
	if w.f != nil {
		w.f.Close()
	}
	f, err := os.OpenFile(w.path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		// fall back to stderr
		w.f = os.Stderr
		return
	}
	info, _ := f.Stat()
	if info != nil {
		w.size = info.Size()
	}
	w.f = f
}

func (w *rotatingWriter) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.size+int64(len(p)) > w.maxBytes && w.maxBytes > 0 {
		w.rotate()
	}
	n, err := w.f.Write(p)
	w.size += int64(n)
	return n, err
}

func (w *rotatingWriter) rotate() {
	w.f.Close()
	for i := w.backups; i >= 1; i-- {
		src := w.path
		if i > 1 {
			src = fmt.Sprintf("%s.%d", w.path, i-1)
		}
		dst := fmt.Sprintf("%s.%d", w.path, i)
		if _, err := os.Stat(dst); err == nil {
			os.Remove(dst)
		}
		if _, err := os.Stat(src); err == nil {
			os.Rename(src, dst)
		}
	}
	w.open()
}

func (w *rotatingWriter) Close() {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.f != nil && w.f != os.Stderr {
		w.f.Close()
	}
}
