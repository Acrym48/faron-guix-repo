package proxy

import "encoding/hex"

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

func errName(err error) string {
	if err == nil {
		return ""
	}
	n := err.Error()
	if len(n) == 0 {
		return "error"
	}
	// Python's type(t).__name__ approximations for the session log:
	switch {
	case n == "client disconnected" || n == "connection reset by peer":
		return "ConnectionError"
	case n == "Broken pipe":
		return "BrokenPipeError"
	default:
		return "error:" + n
	}
}

func hexSecret(s string) []byte {
	if s == "" {
		return nil
	}
	b, err := hex.DecodeString(s)
	if err != nil {
		return []byte(s)
	}
	return b
}

func pluralPkts(n int64) string {
	if n == 1 {
		return "pkt"
	}
	return "pkts"
}
