// Package stats exposes process-wide counters shared across connection
// goroutines.
package stats

import (
	"fmt"
	"strconv"
	"sync/atomic"
)

type Stats struct {
	ConnectionsTotal       atomic.Int64
	ConnectionsActive      atomic.Int64
	ConnectionsWS          atomic.Int64
	ConnectionsTCPFallback atomic.Int64
	ConnectionsCfproxy     atomic.Int64
	ConnectionsFronting    atomic.Int64
	ConnectionsBad         atomic.Int64
	ConnectionsMasked      atomic.Int64
	WSErrors               atomic.Int64
	BytesUp                atomic.Int64
	BytesDown              atomic.Int64
	PoolHits               atomic.Int64
	PoolMisses             atomic.Int64
	CfPoolHits             atomic.Int64
	CfPoolMisses           atomic.Int64
}

var Current = &Stats{}

func humanBytes(n int64) string {
	units := []string{"B", "KB", "MB", "GB"}
	f := float64(n)
	if f < 0 {
		f = -f
	}
	for _, u := range units {
		if f < 1024 || u == "GB" {
			return fmt.Sprintf("%.1f%s", f, u)
		}
		f /= 1024
	}
	return fmt.Sprintf("%.1fTB", f)
}

// Summary renders one log line with all counters, like Python's
// `stats.summary()`.
func (s *Stats) Summary() string {
	poolTotal := s.PoolHits.Load() + s.PoolMisses.Load()
	poolS := fmt.Sprintf("%d/%d", s.PoolHits.Load(), poolTotal)
	if poolTotal == 0 {
		poolS = "n/a"
	}
	cfPoolTotal := s.CfPoolHits.Load() + s.CfPoolMisses.Load()
	cfPoolS := fmt.Sprintf("%d/%d", s.CfPoolHits.Load(), cfPoolTotal)
	if cfPoolTotal == 0 {
		cfPoolS = "n/a"
	}
	return "total=" + strconv.FormatInt(s.ConnectionsTotal.Load(), 10) +
		" active=" + strconv.FormatInt(s.ConnectionsActive.Load(), 10) +
		" ws=" + strconv.FormatInt(s.ConnectionsWS.Load(), 10) +
		" tcp_fb=" + strconv.FormatInt(s.ConnectionsTCPFallback.Load(), 10) +
		" cf=" + strconv.FormatInt(s.ConnectionsCfproxy.Load(), 10) +
		" front=" + strconv.FormatInt(s.ConnectionsFronting.Load(), 10) +
		" bad=" + strconv.FormatInt(s.ConnectionsBad.Load(), 10) +
		" masked=" + strconv.FormatInt(s.ConnectionsMasked.Load(), 10) +
		" err=" + strconv.FormatInt(s.WSErrors.Load(), 10) +
		" pool=" + poolS +
		" cf_pool=" + cfPoolS +
		" up=" + humanBytes(s.BytesUp.Load()) +
		" down=" + humanBytes(s.BytesDown.Load())
}
