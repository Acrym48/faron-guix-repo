// Package xlog is a tiny printf-style wrapper around log/slog so the proxy
// code can mirror the Python logging calls verbatim.
package xlog

import (
	"fmt"
	"log/slog"
)

type Logger struct {
	l *slog.Logger
}

func New(l *slog.Logger) *Logger {
	if l == nil {
		l = slog.Default()
	}
	return &Logger{l: l}
}

// Slogger exposes the underlying slog.Logger for consumers that want it.
func (x *Logger) Slogger() *slog.Logger { return x.l }

func (x *Logger) Debugf(format string, args ...any) { x.l.Debug(fmt.Sprintf(format, args...)) }
func (x *Logger) Infof(format string, args ...any)  { x.l.Info(fmt.Sprintf(format, args...)) }
func (x *Logger) Warnf(format string, args ...any)  { x.l.Warn(fmt.Sprintf(format, args...)) }
func (x *Logger) Errorf(format string, args ...any) { x.l.Error(fmt.Sprintf(format, args...)) }

func (x *Logger) Debug(msg string, args ...any) { x.l.Debug(msg, args...) }
func (x *Logger) Info(msg string, args ...any)  { x.l.Info(msg, args...) }
func (x *Logger) Warn(msg string, args ...any)  { x.l.Warn(msg, args...) }
func (x *Logger) Error(msg string, args ...any) { x.l.Error(msg, args...) }
