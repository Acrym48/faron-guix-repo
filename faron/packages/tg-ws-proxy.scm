(define-module (faron packages tg-ws-proxy)
  #:use-module (guix packages)
  #:use-module (guix build-system go)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages golang)
  #:use-module (gnu packages golang-web)
  #:export (tg-ws-proxy-go))

(define-public tg-ws-proxy-go
  (package
    (name "tg-ws-proxy-go")
    (version "0.1.0")
    (source (local-file "/home/faron/projects/tg-ws-proxy-go"
                        "tg-ws-proxy-go-src"
                        #:recursive? #t
                        #:select? (git-predicate
                                   "/home/faron/projects/tg-ws-proxy-go")))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "tg-ws-proxy-go"
      #:install-source? #f
      #:phases
      #~(modify-phases %standard-phases
          (replace 'build
            (lambda* (#:key import-path #:allow-other-keys)
              (invoke "go" "install"
                      "-ldflags=-s -w"
                      "-trimpath"
                      (string-append import-path "/cmd/tg-ws-proxy")))))))
    (inputs (list go-github-com-gorilla-websocket))
    (home-page "https://github.com/tg-ws-proxy-go")
    (synopsis "Local MTProto WebSocket proxy for Telegram Desktop")
    (description
     "Local MTProto proxy bridging Telegram Desktop traffic over WebSocket.")
    (license license:gpl3)))
