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
    (version "0.1.1")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/Acrym48/tg-ws-proxy-go")
             (commit "4dd081bbb79d7367beb1d75c30bb2606c016bffd")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "1bywa5rzm3gys89cnsm517bb2z6f3r3fqv3p4978q6fc8x90fq01"))))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "github.com/Acrym48/tg-ws-proxy-go"
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
    (home-page "https://github.com/Acrym48/tg-ws-proxy-go")
    (synopsis "Local MTProto WebSocket proxy for Telegram Desktop")
    (description
     "Local MTProto proxy bridging Telegram Desktop traffic over WebSocket.")
    (license license:gpl3)))
