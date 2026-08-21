// Package balancer distributes Cloudflare-backed proxy workloads per DC.
package balancer

import (
	"math/rand"
	"sync"
)

// Default is the process-wide balancer used by the proxy and config refresh.
var Default = New()

// Balancer keeps a list of CF-proxy base domains and maps each DC to a
// preferred domain, falling back to randomly shuffled alternatives.
type Balancer struct {
	mu         sync.Mutex
	domains    []string
	dcToDomain map[int]string
}

func New() *Balancer {
	return &Balancer{dcToDomain: make(map[int]string)}
}

var allDCs = []int{1, 2, 3, 4, 5, 203}

// UpdateDomainsList replaces the domain pool and re-randomizes the per-DC
// assignment unless the pool is unchanged.
func (b *Balancer) UpdateDomainsList(domains []string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	if equalStr(b.domains, domains) {
		return false
	}
	b.domains = append([]string(nil), domains...)
	if len(domains) == 0 {
		return true
	}
	m := make(map[int]string, len(allDCs))
	for _, dc := range allDCs {
		m[dc] = domains[rand.Intn(len(domains))]
	}
	b.dcToDomain = m
	return true
}

// UpdateDomainForDC pins a DC to a specific domain. Returns true when changed.
func (b *Balancer) UpdateDomainForDC(dc int, domain string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.dcToDomain[dc] == domain {
		return false
	}
	b.dcToDomain[dc] = domain
	return true
}

// PreferDomainForDC returns the DC's preferred domain, if any.
func (b *Balancer) PreferDomainForDC(dc int) (string, bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	d, ok := b.dcToDomain[dc]
	return d, ok
}

// DomainsForDC yields the preferred domain first, then the rest shuffled.
func (b *Balancer) DomainsForDC(dc int) []string {
	b.mu.Lock()
	current := b.dcToDomain[dc]
	pool := append([]string(nil), b.domains...)
	b.mu.Unlock()

	out := make([]string, 0, len(pool))
	if current != "" {
		out = append(out, current)
	}
	rand.Shuffle(len(pool), func(i, j int) { pool[i], pool[j] = pool[j], pool[i] })
	for _, d := range pool {
		if d != current {
			out = append(out, d)
		}
	}
	return out
}

func equalStr(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
