(define-module (faron packages go)
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
(define-public anilib-cli
  (package
    (name "anilib-cli")
    (version "0.0.1")
    (source
      (origin
        (method git-fetch)
        (uri (git-reference
     	       (url "https://github.com/Acrym48/anilib-cli")
	       (commit "76c0aa0ff683c66652d1bb33e1784e969dc46964
")))
        (file-name (git-file-name name version))
        (sha256
          (base32 "1qh4nic3q46w1bpnhmxr0dlmk1q9warjx8n8m5fzfszfibxz40yq
"))))
   (build-system go-build-system)
   (arguments
    (list
        #:import-path "github.com/Acrym48/anilib-cli"
        #:install-source? #f
        #:phases
        #~(modify-phases %standard-phases
 	   (replace 'build
	     (lambda* (#:key import-path #:allow-other-keys)
	                (invoke "go" "install"
			        "-ldflags=-s -w"
			        "trimpath"
			        (string-append import-path "."))))
	   (add-after 'install 'wrap-program
	     (lambda* (#:key inputs outputs #:allow-other-keys)
	       (let* ((out (assoc-ref outputs "out"))
		      (mpv (assoc-ref inputs "mpv")))
	         (wrap-program (string-append out "/bin/anilib-cli")
		   `("PATH" ":" prefix (,(string-append mpv "/bin"))))))))))
  (inputs (list go-golang-org-x-term))
  (home-page "https://github.com/Acrym48/anilib-cli")
  (synopsis "anilib-cli is a cross-platform command-line tool for watching anime from AniLiberty, offering search, episode navigation, quality selection, and automatic viewing history.")
  (description
    "anilib-cli is a Go-based CLI application that lets users search, stream, and download anime from AniLiberty directly via an integrated video player. It supports interactive search with arrow-key selection or direct numeric picks, adjustable video quality (480p/720p/1080p), episode ranges, \"continue watching\" and \"next episode\" shortcuts, and episode downloading. Viewing history is saved automatically to a local JSON file. The tool runs on Linux, macOS, and Windows, and can be installed via a prebuilt binary or built from source using go install.")
  (license license:gpl3)))
