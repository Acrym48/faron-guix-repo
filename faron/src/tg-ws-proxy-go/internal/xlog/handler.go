// Package xlog is a tiny printf-style wrapper around log/slog so the proxy
// code can mirror the Python logging calls verbatim.
//
// This file adds a pretty console handler that prints records like the
// original Python logger:
//
//	14:03:22  INFO   [127.0.0.1:40888] DC2 ended (client closed): 612.0B in 5.4s
package xlog

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"os"
	"strings"
	"sync"
)

const (
	cReset  = "\x1b[0m"
	cGray   = "\x1b[90m"
	cGreen  = "\x1b[32m"
	cYellow = "\x1b[33m"
	cRed    = "\x1b[31m"
)

// PrettyHandler prints records as "HH:MM:SS  LEVEL  message  key=value ...".
// When out is a terminal, levels are colourised and the timestamp is dimmed;
// for files (pipes/rotation) everything stays plain.
type PrettyHandler struct {
	mu    *sync.Mutex
	out   io.Writer
	level slog.Level
	color bool

	group string
	attrs []slog.Attr
}

// NewPrettyHandler builds a PrettyHandler writing to out at the given level.
func NewPrettyHandler(out io.Writer, level slog.Level) *PrettyHandler {
	return &PrettyHandler{
		mu:    &sync.Mutex{},
		out:   out,
		level: level,
		color: isTerminal(out),
	}
}

func isTerminal(w io.Writer) bool {
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

// Enabled reports whether the record at the given level is worth logging.
func (h *PrettyHandler) Enabled(_ context.Context, l slog.Level) bool {
	return l >= h.level
}

// Handle renders a single record.
func (h *PrettyHandler) Handle(_ context.Context, r slog.Record) error {
	var b strings.Builder

	name, lc := levelName(r.Level)
	if h.color {
		fmt.Fprintf(&b, "%s%s%s  %s%-5s%s  %s",
			cGray, r.Time.Format("15:04:05"), cReset, lc, name, cReset, r.Message)
	} else {
		fmt.Fprintf(&b, "%s  %-5s  %s", r.Time.Format("15:04:05"), name, r.Message)
	}

	attrs := append([]slog.Attr(nil), h.attrs...)
	r.Attrs(func(a slog.Attr) bool {
		attrs = append(attrs, a)
		return true
	})

	parts := make([]string, 0, len(attrs))
	for _, a := range attrs {
		a.Value = a.Value.Resolve()
		if a.Key == "" {
			continue
		}
		if p := attrString(h.group, a); p != "" {
			parts = append(parts, p)
		}
	}
	if len(parts) > 0 {
		b.WriteString("  ")
		b.WriteString(strings.Join(parts, " "))
	}
	b.WriteString("\n")

	h.mu.Lock()
	defer h.mu.Unlock()
	_, err := io.WriteString(h.out, b.String())
	return err
}

// WithAttrs returns a copy carrying pre-set attributes.
func (h *PrettyHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	c := *h
	c.attrs = append(append([]slog.Attr(nil), h.attrs...), attrs...)
	return &c
}

// WithGroup returns a copy that prefixes attribute keys with the group name.
func (h *PrettyHandler) WithGroup(name string) slog.Handler {
	if name == "" {
		return h
	}
	c := *h
	if c.group == "" {
		c.group = name
	} else {
		c.group = c.group + "." + name
	}
	return &c
}

func attrString(group string, a slog.Attr) string {
	key := a.Key
	if group != "" {
		key = group + "." + key
	}
	switch a.Value.Kind() {
	case slog.KindGroup:
		inner := make([]string, 0, len(a.Value.Group()))
		for _, ia := range a.Value.Group() {
			if ia.Key == "" {
				continue
			}
			if p := attrString(key, ia); p != "" {
				inner = append(inner, p)
			}
		}
		return strings.Join(inner, " ")
	case slog.KindString:
		s := a.Value.String()
		if strings.ContainsAny(s, " \t\n\"") {
			return fmt.Sprintf("%s=%q", key, s)
		}
		return key + "=" + s
	default:
		return fmt.Sprintf("%s=%v", key, a.Value.Any())
	}
}

func levelName(l slog.Level) (string, string) {
	var name, color string
	switch {
	case l >= slog.LevelError:
		name, color = "ERROR", cRed
	case l >= slog.LevelWarn:
		name, color = "WARN", cYellow
	case l >= slog.LevelInfo:
		name, color = "INFO", cGreen
	default:
		name, color = "DEBUG", cGray
	}
	return name, color
}
