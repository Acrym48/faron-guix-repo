// Package config holds the runtime configuration, CLI flag plumbing and the
// Cloudflare domain pool management.
package config

import (
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode"

	"tg-ws-proxy-go/internal/balancer"
)

const (
	CfDomainsURL = "https://raw.githubusercontent.com/Flowseal/tg-ws-proxy/main/.github/cfproxy-domains.txt"

	cfMinValidDomains    = 3
	defaultCfDomainsCOUK = ".co.uk"
)

// encoded default CF proxy domains (decoded at init via decodeCfDomain).
var encodedCfDomains = []string{
	"virkgj.com", "vmmzovy.com", "mkuosckvso.com", "zaewayzmplad.com",
	"twdmbzcm.com", "awzwsldi.com", "clngqrflngqin.com", "tjacxbqtj.com",
	"bxaxtxmrw.com", "dmohrsgmohcrwb.com", "vwbmtmoi.com", "khgrre.com",
	"ulihssf.com", "tmhqsdqmfpmk.com", "xwuwoqbm.com", "orgcnunpj.com",
	"zhkuldz.com", "zypoljnslxa.com", "efabnxaowuzs.com", "zaftuzsftqdq.com",
}

// Config mirrors the Python ProxyConfig plus CLI overrides.
type Config struct {
	Port        int
	Host        string
	Secret      string
	DCRedirects map[int]string
	BufferSize  int
	PoolSize    int

	FallbackCfproxy      bool
	CfproxyUserDomains   []string
	CfproxyWorkerDomains []string
	FakeTlsDomain        string
	ProxyProtocol        bool
	ForceTestDC          bool

	// FallbackSet marks that the user pinned the fallback chain explicitly
	// (--fallback); FallbackMethods then holds the ordered methods.
	FallbackSet     bool
	FallbackMethods []string
}

// New returns a config with the same defaults as the Python project.
func New() *Config {
	return &Config{
		Port:            1443,
		Host:            "127.0.0.1",
		DCRedirects:     map[int]string{2: "149.154.167.220", 4: "149.154.167.220"},
		BufferSize:      256 * 1024,
		PoolSize:        4,
		FallbackCfproxy: true,
	}
}

// DC defaults used for fallback destinations.
var DCDefaultIPs = map[int]string{
	1:   "149.154.175.50",
	2:   "149.154.167.51",
	3:   "149.154.175.100",
	4:   "149.154.167.91",
	5:   "149.154.171.5",
	203: "91.105.192.100",
}

var DCTestIPs = map[int]string{
	1: "149.154.175.10",
	2: "149.154.167.40",
	3: "149.154.175.117",
}

// ParseDcIpList parses ["2:149.154.167.220", ...] entries into a dc->ip map.
// The last entry wins for duplicate DCs.
func ParseDcIpList(entries []string) (map[int]string, error) {
	out := make(map[int]string, len(entries))
	for _, entry := range entries {
		idx := strings.IndexByte(entry, ':')
		if idx < 0 {
			return nil, fmt.Errorf("invalid --dc-ip format %q, expected DC:IP", entry)
		}
		dcS, ipS := entry[:idx], entry[idx+1:]
		dcN, err := parseInt(dcS)
		if err != nil {
			return nil, fmt.Errorf("invalid --dc-ip %q", entry)
		}
		if net.ParseIP(ipS) == nil {
			return nil, fmt.Errorf("invalid --dc-ip %q", entry)
		}
		out[dcN] = ipS
	}
	return out, nil
}

// ParseFallbackChain parses a --fallback value into an ordered method list.
// Empty returns (nil, false, nil) = auto (default chain). "off"/"none"
// returns (nil, true, nil) = no fallbacks at all.
func ParseFallbackChain(s string) ([]string, bool, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, false, nil
	}
	fields := strings.FieldsFunc(s, func(r rune) bool {
		return r == ',' || r == ';' || r == ' ' || r == '+'
	})
	if len(fields) == 1 {
		if low := strings.ToLower(fields[0]); low == "off" || low == "none" {
			return nil, true, nil
		}
	}
	var methods []string
	for _, f := range fields {
		switch strings.ToLower(f) {
		case "cf", "cloudflare", "cf_proxy":
			methods = append(methods, "cf")
		case "cf_worker", "worker":
			methods = append(methods, "cf_worker")
		case "tcp", "direct":
			methods = append(methods, "tcp")
		default:
			return nil, true, fmt.Errorf(
				"unknown fallback method %q (allowed: cf, cf_worker, tcp, off)", f)
		}
	}
	return methods, true, nil
}

func parseInt(s string) (int, error) {
	n := 0
	if s == "" || s == "-" {
		return 0, errors.New("empty")
	}
	i := 0
	neg := false
	if s[0] == '-' {
		neg = true
		i++
	}
	for ; i < len(s); i++ {
		c := s[i]
		if c < '0' || c > '9' {
			return 0, errors.New("not a number")
		}
		n = n*10 + int(c-'0')
	}
	if neg {
		n = -n
	}
	return n, nil
}

// CoerceDomainList flattens mixed input into a de-duplicated domain list,
// splitting on spaces, commas and semicolons. Mirrors `coerce_domain_list`.
func CoerceDomainList(items []string) []string {
	var raw []string
	for _, it := range items {
		raw = append(raw, strings.FieldsFunc(it, func(r rune) bool {
			return r == ' ' || r == ',' || r == ';'
		})...)
	}
	seen := make(map[string]struct{})
	var out []string
	for _, it := range raw {
		key := strings.ToLower(it)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, it)
	}
	return out
}

// IsValidDomain mirrors the `_is_valid_domain` checks.
func IsValidDomain(d string) bool {
	if len(d) == 0 || len(d) > 253 {
		return false
	}
	if strings.HasPrefix(d, ".") || strings.HasSuffix(d, ".") {
		return false
	}
	labels := strings.Split(d, ".")
	if len(labels) < 2 {
		return false
	}
	for _, label := range labels {
		if len(label) == 0 || len(label) > 63 {
			return false
		}
		if label[0] == '-' || label[len(label)-1] == '-' {
			return false
		}
		for _, ch := range label {
			if !(ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z' ||
				ch >= '0' && ch <= '9' || ch == '-') {
				return false
			}
		}
	}
	tld := labels[len(labels)-1]
	if len(tld) < 2 {
		return false
	}
	for _, ch := range tld {
		if unicode.IsLetter(ch) {
			return true
		}
	}
	return false
}

// NormalizeDomainPool lowercases, dedupes and drops invalid domains.
func NormalizeDomainPool(domains []string) []string {
	seen := make(map[string]struct{})
	var out []string
	for _, d := range domains {
		item := strings.ToLower(strings.TrimSpace(d))
		if !IsValidDomain(item) {
			continue
		}
		if _, ok := seen[item]; ok {
			continue
		}
		seen[item] = struct{}{}
		out = append(out, item)
	}
	return out
}

// DecodeCfDomain decodes an encoded `*.com` domain into a `*.co.uk` domain.
// Mirrors `_dd` in config.py.
func DecodeCfDomain(s string) string {
	if len(s) < 4 || !strings.HasSuffix(s, ".com") {
		return s
	}
	p := s[:len(s)-4]
	n := 0
	for _, c := range p {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
			n++
		}
	}
	var b strings.Builder
	b.Grow(len(p) + len(defaultCfDomainsCOUK))
	for _, c := range p {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') {
			base := byte('a')
			if c < 'a' {
				base = 'A'
			}
			shift := byte(n % 26)
			newC := byte(c) - shift
			if newC < base {
				newC += 26
			}
			b.WriteByte(newC)
		} else {
			b.WriteRune(c)
		}
	}
	b.WriteString(defaultCfDomainsCOUK)
	return b.String()
}

// DefaultCfDomains returns the decoded default pool.
func DefaultCfDomains() []string {
	out := make([]string, 0, len(encodedCfDomains))
	for _, d := range encodedCfDomains {
		out = append(out, DecodeCfDomain(d))
	}
	return out
}

func fetchCfProxyDomainList(client *http.Client) ([]string, error) {
	u := fmt.Sprintf("%s?%s", CfDomainsURL, randString(7))
	req, err := http.NewRequest(http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "tg-ws-proxy")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		io.Copy(io.Discard, resp.Body)
		return nil, fmt.Errorf("GET %s: %s", CfDomainsURL, resp.Status)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	var out []string
	for _, line := range strings.Split(string(body), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		out = append(out, DecodeCfDomain(line))
	}
	return out, nil
}

func randString(n int) string {
	const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	b := make([]byte, n)
	for i := range b {
		b[i] = letters[rand.Intn(len(letters))]
	}
	return string(b)
}

// CfDomainManager periodically refreshes the shared CF proxy domain pool.
type CfDomainManager struct {
	Mu      sync.Mutex
	Domains []string
	stopCh  chan struct{}
}

func NewCfDomainManager() *CfDomainManager {
	m := &CfDomainManager{
		Domains: NormalizeDomainPool(DefaultCfDomains()),
		stopCh:  make(chan struct{}),
	}
	return m
}

// Start begins the periodic refresh loop (every hour) unless the caller
// supplied user domains, in which case the pool is fixed.
func (m *CfDomainManager) Start(userDomains []string) {
	if len(userDomains) > 0 {
		m.Mu.Lock()
		m.Domains = NormalizeDomainPool(userDomains)
		m.Mu.Unlock()
		balancer.Default.UpdateDomainsList(m.Domains)
		return
	}
	balancer.Default.UpdateDomainsList(m.Domains)
	client := &http.Client{Timeout: 15 * time.Second}
	go m.refreshOnce(client)
	go func() {
		ticker := time.NewTicker(time.Hour)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				m.refreshOnce(client)
			case <-m.stopCh:
				return
			}
		}
	}()
}

func (m *CfDomainManager) Stop() {
	select {
	case <-m.stopCh:
	default:
		close(m.stopCh)
	}
}

func (m *CfDomainManager) refreshOnce(client *http.Client) {
	fetched, err := fetchCfProxyDomainList(client)
	if err != nil {
		// keep the current pool
		return
	}
	pool := NormalizeDomainPool(fetched)
	if len(pool) < cfMinValidDomains {
		return
	}
	m.Mu.Lock()
	m.Domains = pool
	m.Mu.Unlock()
	balancer.Default.UpdateDomainsList(pool)
}
