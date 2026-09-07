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
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/Acrym48/tg-ws-proxy-go")
             (commit "1afa1a95511af02fdca746d93721e43841edcc33")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0n9cvlsvbr55yhyjl9l00bcr0nci819w2i1i0spmvl8fy2vz7kgy"))))
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
    (home-page "https://github.com/Acrym48/tg-ws-proxy-go")
    (synopsis "Local MTProto WebSocket proxy for Telegram Desktop")
    (description
     "Local MTProto proxy bridging Telegram Desktop traffic over WebSocket.")
    (license license:gpl3)))
