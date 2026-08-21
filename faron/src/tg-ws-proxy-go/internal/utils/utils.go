// Package utils provides small shared helpers and Telegram WS constants.
package utils

import (
	"fmt"
	"net"
)

// WS path constants (mirror utils.py).
const (
	WSPath     = "/apiws"
	WSPathTest = WSPath + "_test"
)

// WSDomains returns the candidate upstream WebSocket domains for a DC.
// isMedia=true (or nil semantics) prefers the "-1" front domain first.
func WSDomains(dc int, isMedia bool) []string {
	if dc == 203 {
		dc = 2
	}
	if isMedia {
		return []string{
			fmt.Sprintf("kws%d-1.web.telegram.org", dc),
			fmt.Sprintf("kws%d.web.telegram.org", dc),
		}
	}
	return []string{
		fmt.Sprintf("kws%d.web.telegram.org", dc),
		fmt.Sprintf("kws%d-1.web.telegram.org", dc),
	}
}

// GetLinkHost resolves 0.0.0.0 to the primary LAN address for share links.
func GetLinkHost(host string) string {
	if host != "0.0.0.0" {
		return host
	}
	c, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		return "127.0.0.1"
	}
	defer c.Close()
	if addr, ok := c.LocalAddr().(*net.UDPAddr); ok {
		return addr.IP.String()
	}
	return "127.0.0.1"
}

// HumanBytes renders a byte count like Python's human_bytes.
func HumanBytes(n int64) string {
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

// DC key helper: "1", "1t", "2m", "2tm".
func DCKey(dc int, isTest, isMedia bool) string {
	s := fmt.Sprintf("%d", dc)
	if isTest {
		s += "t"
	}
	if isMedia {
		s += "m"
	}
	return s
}
