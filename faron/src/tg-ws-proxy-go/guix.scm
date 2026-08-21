;; -*- mode: scheme; coding: utf-8 -*-
;;; tg-ws-proxy-go: build recipe and development environment for GNU Guix.
;;;
;;;   guix shell -f guix.scm    # dev environment (go + gopls)
;;;   guix shell -m guix.scm    # manifest form (same as above)
;;;   guix build -f guix.scm    # build the packaged proxy binary

(use-modules
 (guix)
 (guix build-system go)
 ((guix licenses) #:prefix license:)
 (guix profiles)
 (gnu packages)
 (gnu packages golang)
 (gnu packages golang-web))

(define-public tg-ws-proxy-go
  (package
    (name "tg-ws-proxy-go")
    (version "0.1.0")
    (source (local-file "." "tg-ws-proxy-go" #:recursive? #t))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "tg-ws-proxy-go"
      #:packages (list "cmd/tg-ws-proxy")
      #:install-source? #f))
    (inputs (list go-github-com-gorilla-websocket))
    (home-page "https://github.com/tg-ws-proxy-go")
    (synopsis "Local MTProto WebSocket proxy for Telegram Desktop")
    (description
     "tg-ws-proxy-go is a Go port of the tg-ws-proxy core: a local MTProto
proxy that bridges Telegram Desktop traffic over WebSocket connections,
with Cloudflare and direct TCP fallbacks.")
    (license license:gpl3)))

(define-public tg-ws-proxy-go-dev
  (package
    (inherit tg-ws-proxy-go)
    (name "tg-ws-proxy-go-dev")
    (inputs (list go-github-com-gorilla-websocket gopls))))

;; Value used by `guix shell -f guix.scm` / `guix build -f guix.scm`.
tg-ws-proxy-go-dev
