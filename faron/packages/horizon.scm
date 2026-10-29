(define-module (faron packages horizon)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system trivial)
  #:use-module (gnu packages)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (nonguix multiarch-container)
  #:export (horizon-launcher))

(define %horizon-version "0.2.26")

(define horizon-launcher-files
  (package
   (name "horizon-launcher-files")
   (version %horizon-version)
   (source (origin
            (method url-fetch)
            (uri (string-append
                  "https://github.com/ludovic111/horizon/releases/download/launcher@"
                  version "/horizon-launcher-linux-x86_64.tar.gz"))
            (sha256 (base32 "0pa7zyq31h9jf6pa5zpjx9w67dqyjadjqjdcr049zggpsnm69gpf"))))
   (build-system copy-build-system)
   (arguments
    (list #:validate-runpath? #f
          #:strip-binaries? #f
          #:install-plan #~'(("horizon-launcher" "bin/"))
          #:phases
          #~(modify-phases %standard-phases
			   (add-after 'install 'chmod
				      (lambda _
					(chmod (string-append #$output "/bin/horizon-launcher")
					       #o755))))))
   (home-page "https://github.com/ludovic111/horizon")
   (synopsis "Horizon launcher")
   (description "Launcher for Horizon, a Rust rewrite of Minecraft.")
   (license license:expat)))

(define horizon-container
  (nonguix-container
   (name "horizon-launcher")
   (wrap-package horizon-launcher-files)
   (run "/bin/horizon-launcher")
   (union64
    (fhs-union
     (map specification->package
          '("vulkan-loader" "mesa" "wayland" "libxcb" "libxkbcommon"
            "xkeyboard-config" "openjdk" "gcc-toolchain" "nautilus" "alsa-lib" "eudev"))
     #:name "fhs-union-64"))
   (preserved-env '("^WAYLAND_DISPLAY$" "^XDG_RUNTIME_DIR$"
                    "^DBUS_SESSION_BUS_ADDRESS$" "^XDG_CURRENT_DESKTOP$"))
   (description "Horizon launcher inside an FHS container.")))

(define horizon-container-package
  (nonguix-container->package horizon-container))

;; Внешняя обёртка: выставляет GUIX_SANDBOX_HOME до запуска контейнера.
(define-public horizon-launcher
  (package
   (inherit horizon-container-package)
   (build-system trivial-build-system)
   (inputs '())
   (native-inputs '())
   (propagated-inputs '())
   (arguments
    (list
     #:modules '((guix build utils))
     #:builder
     #~(begin
         (use-modules (guix build utils))
         (let* ((bin  (string-append #$output "/bin"))
                (dest (string-append bin "/horizon-launcher"))
                (real (string-append #$horizon-container-package
                                     "/bin/horizon-launcher")))
           (mkdir-p bin)
           (call-with-output-file dest
             (lambda (port)
               (format port "#!~a/bin/bash
export GUIX_SANDBOX_HOME=\"${GUIX_SANDBOX_HOME:-$HOME}\"
exec ~a \"$@\"
"
                       #$bash-minimal real)))
           (chmod dest #o755)))))))
