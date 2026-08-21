package proxy

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"time"
	"unicode/utf8"

	"tg-ws-proxy-go/internal/balancer"
	"tg-ws-proxy-go/internal/stats"
	"tg-ws-proxy-go/internal/utils"
)

const (
	cReset = "\x1b[0m"
	cGray  = "\x1b[90m"
	cGreen = "\x1b[32m"
	cCyan  = "\x1b[36m"
)

// Run starts the listener, warms up the pools and blocks until ctx is
// cancelled, then shuts everything down cleanly.
func (p *Proxy) Run(ctx context.Context) error {
	p.WsPool.Reset()
	p.CfPool.Reset()
	p.resetState()

	if len(p.Cfg.CfproxyUserDomains) > 0 {
		balancer.Default.UpdateDomainsList(p.Cfg.CfproxyUserDomains)
	}
	p.CfDomain.Start(p.Cfg.CfproxyUserDomains)

	addr := net.JoinHostPort(p.Cfg.Host, itoa(p.Cfg.Port))
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return fmt.Errorf("listen %s: %w", addr, err)
	}

	p.printBanner()

	acceptDone := make(chan struct{})
	go func() {
		defer close(acceptDone)
		p.acceptLoop(ctx, ln, addr)
	}()

	p.WsPool.Warmup()
	p.CfPool.Warmup()

	statsDone := make(chan struct{})
	go func() {
		defer close(statsDone)
		t := time.NewTicker(60 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				p.Log.Infof("stats: %s", stats.Current.Summary())
			}
		}
	}()

	<-ctx.Done()
	_ = ln.Close()
	<-acceptDone
	p.CfDomain.Stop()
	<-statsDone
	p.Log.Infof("Shutting down. Final stats: %s", stats.Current.Summary())
	return nil
}

// acceptLoop accepts connections; on a hard listener failure it attempts to
// rebind after a short delay, mirroring the Python listener watchdog.
func (p *Proxy) acceptLoop(ctx context.Context, ln net.Listener, addr string) {
	for {
		conn, err := ln.Accept()
		if err == nil {
			go p.handleClient(conn)
			continue
		}
		if ctx.Err() != nil {
			return
		}
		var ne net.Error
		if errors.As(err, &ne) && ne.Timeout() {
			continue
		}
		p.Log.Warnf("listening socket error (%s), restarting in 1s", err)
		_ = ln.Close()
		select {
		case <-ctx.Done():
			return
		case <-time.After(time.Second):
		}
		newLn, err2 := net.Listen("tcp", addr)
		if err2 != nil {
			p.Log.Errorf("failed to restart listener: %s", err2)
			return
		}
		ln = newLn
		p.Log.Warnf("Server restored, listening on %s", addr)
	}
}

func (p *Proxy) printBanner() {
	linkHost := utils.GetLinkHost(p.Cfg.Host)

	fields := [][2]string{}
	addField := func(name, value string) { fields = append(fields, [2]string{name, value}) }

	addField("listen", fmt.Sprintf("%s:%d", p.Cfg.Host, p.Cfg.Port))
	addField("secret", "dd"+p.Cfg.Secret)
	if ftls := p.Cfg.FakeTlsDomain; ftls != "" {
		addField("fake TLS", ftls)
	}
	var fb []string
	if p.Cfg.FallbackSet {
		for _, m := range p.Cfg.FallbackMethods {
			switch m {
			case "cf":
				fb = append(fb, "cloudflare")
			case "cf_worker":
				fb = append(fb, "worker")
			case "tcp":
				fb = append(fb, "tcp")
			}
		}
		if len(fb) == 0 {
			addField("fallback", "off")
		} else {
			addField("fallback", strings.Join(fb, " + "))
		}
	} else {
		if p.Cfg.FallbackCfproxy {
			fb = append(fb, "cloudflare")
		}
		if len(p.Cfg.CfproxyWorkerDomains) > 0 {
			fb = append(fb, "worker")
		}
		if len(fb) > 0 {
			addField("fallback", strings.Join(fb, " + "))
		}
	}
	if p.Cfg.ForceTestDC {
		addField("force test DC", "yes")
	}
	if p.Cfg.ProxyProtocol {
		addField("proxy protocol", "yes")
	}

	var dcRows []string
	dcRows = append(dcRows, "  target DCs")
	for _, dc := range sortedDCKeys(p.Cfg.DCRedirects) {
		dcRows = append(dcRows, fmt.Sprintf("    DC %-4d%s", dc, p.Cfg.DCRedirects[dc]))
	}

	var links []string
	links = append(links, fmt.Sprintf("tg://proxy?server=%s&port=%d&secret=dd%s",
		linkHost, p.Cfg.Port, p.Cfg.Secret))
	if ftls := p.Cfg.FakeTlsDomain; ftls != "" {
		links = append(links,
			fmt.Sprintf("tg://proxy?server=%s&port=%d&secret=ee%s%s",
				linkHost, p.Cfg.Port, p.Cfg.Secret, hex.EncodeToString([]byte(ftls))))
	}

	var linkRows []string
	linkRows = append(linkRows, "  connect")
	for _, l := range links {
		linkRows = append(linkRows, "    "+l)
	}

	var groups [][]string
	groups = append(groups, []string{"  Telegram MTProto WS Bridge Proxy"})
	var body []string
	for _, f := range fields {
		body = append(body, fmt.Sprintf("  %-16s%s", f[0]+":", f[1]))
	}
	groups = append(groups, body)
	groups = append(groups, dcRows)
	groups = append(groups, linkRows)

	if w := p.Out; w != nil {
		fmt.Fprint(w, "\n"+bannerBox(groups, isTerminalWriter(w))+"\n")
	}
}

type bannerRow struct {
	role int
	text string
}

const (
	rowBody = iota
	rowTitle
	rowHeader
	rowSep
)

// bannerBox renders section groups inside a Unicode box frame. When color is
// true the frame is dimmed, the title is bold-green and section headers cyan.
func bannerBox(groups [][]string, color bool) string {
	var rows []bannerRow
	for gi, g := range groups {
		if gi > 0 {
			rows = append(rows, bannerRow{role: rowSep})
		}
		for ri, line := range g {
			role := rowBody
			if gi == 0 && ri == 0 {
				role = rowTitle
			} else if gi > 1 && ri == 0 {
				role = rowHeader
			}
			rows = append(rows, bannerRow{role: role, text: line})
		}
	}

	inner := 0
	for _, r := range rows {
		if r.role == rowSep {
			continue
		}
		if n := utf8.RuneCountInString(r.text); n > inner {
			inner = n
		}
	}

	b := &strings.Builder{}
	writeFrame := func(cornerL, cornerR string) {
		if color {
			b.WriteString(cGray)
			b.WriteString(cornerL + strings.Repeat("\u2500", inner+2) + cornerR)
			b.WriteString(cReset)
			b.WriteString("\n")
		} else {
			b.WriteString(cornerL + strings.Repeat("\u2500", inner+2) + cornerR + "\n")
		}
	}
	writeFrame("\u250c", "\u2510")
	for _, r := range rows {
		pad := strings.Repeat(" ", inner-utf8.RuneCountInString(r.text))
		if r.role == rowSep {
			writeFrame("\u251c", "\u2524")
			continue
		}
		switch {
		case color && r.role == rowTitle:
			b.WriteString("\u2502 " + cGreen + r.text + pad + cReset + " \u2502\n")
		case color && r.role == rowHeader:
			b.WriteString("\u2502 " + cCyan + r.text + pad + cReset + " \u2502\n")
		case color:
			b.WriteString("\u2502 " + cGray + r.text + pad + cReset + " \u2502\n")
		default:
			b.WriteString("\u2502 " + r.text + pad + " \u2502\n")
		}
	}
	writeFrame("\u2514", "\u2518")
	return b.String()
}

func isTerminalWriter(w io.Writer) bool {
	f, ok := w.(*os.File)
	if !ok {
		return false
	}
	info, err := f.Stat()
	if err != nil {
		return false
	}
	return info.Mode()&os.ModeCharDevice != 0
}

func sortedDCKeys(m map[int]string) []int {
	keys := make([]int, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	for i := 1; i < len(keys); i++ {
		for j := i; j > 0 && keys[j] < keys[j-1]; j-- {
			keys[j], keys[j-1] = keys[j-1], keys[j]
		}
	}
	return keys
}
