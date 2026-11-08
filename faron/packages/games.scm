(define-module (faron packages games)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix build-system copy)
  #:use-module (gnu packages)
  #:use-module (guix build-system trivial)
  #:use-module (gnu packages python)
  #:use-module (gnu packages bash)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (nonguix multiarch-container)
  #:export (umu-launcher-bin umu))

(define %umu-version "1.4.4")

(define umu-launcher-bin
  (package
   (name "umu-launcher-bin")
   (version %umu-version)
   (source
    (origin
     (method url-fetch)
     (uri (string-append
           "https://github.com/Open-Wine-Components/umu-launcher/releases/download/"
           version "/umu-launcher-" version "-zipapp.tar"))
     (sha256 (base32 "0lf8ikj4wynfisr653llwygq91yb9kdxb3xdqczsszqzhj8hcngb"))))
   (build-system copy-build-system)
   (arguments
    (list
     #:install-plan #~'()
     #:phases
     #~(modify-phases %standard-phases
         (replace 'install
           (lambda _
             (let* ((bin (string-append #$output "/bin"))
                    (src (car (find-files "." "^umu-run$"))))
               (mkdir-p bin)
               (install-file src bin)
               (chmod (string-append bin "/umu-run") #o755)))))))
   (inputs (list python))
   (synopsis "Unified launcher for running Proton outside Steam")
   (description "umu-run: Proton outside of Steam (prebuilt zipapp).")
   (home-page "https://github.com/Open-Wine-Components/umu-launcher")
   (license license:gpl3+)))

(define %umu-libs-64
  '("bash" "coreutils" "grep" "sed" "gawk" "findutils" "which"
    "util-linux" "procps" "python" "gcc-toolchain" "glibc-locales"
    "zlib" "openssl" "nss-certs" "curl" "dbus" "eudev" "libusb"
    "alsa-lib" "pipewire" "pulseaudio"
    "freetype" "fontconfig" "font-dejavu"
    "mesa" "libdrm" "vulkan-loader" "wayland" "libxkbcommon"
    "libx11" "libxcb" "libxext" "libxrender" "libxi" "libxrandr"
    "libxcursor" "libxcomposite" "libxdamage" "libxfixes"))

(define %umu-libs-32
  '("mesa" "vulkan-loader" "libdrm" "alsa-lib" "pulseaudio" "zlib"))

(define umu-container
  (nonguix-container
   (name "umu")
   (wrap-package umu-launcher-bin)
   (run "/bin/umu-run")
   (union64
    (fhs-union (map specification->package %umu-libs-64)
               #:name "fhs-union-64"))
   (union32
    (fhs-union (map specification->package %umu-libs-32)
               #:name "fhs-union-32"
               #:system "i686-linux"))
   (preserved-env '("^PROTON" "^WINE" "^UMU_" "^GAMEID$" "^STORE$"
                    "^DXVK_" "^VKD3D_" "^LIBVA_DRIVERS_PATH$"))
   (link-files '("share"))
   (description "umu-launcher inside an FHS container.")))

(define umu-container-package
  (nonguix-container->package umu-container))

(define-public umu
  (package
   (inherit umu-container-package)
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
         (let* ((bin (string-append #$output "/bin"))
                (dest (string-append bin "/umu"))
                (real (string-append #$umu-container-package "/bin/umu")))
           (mkdir-p bin)
           (call-with-output-file dest
             (lambda (port)
               (format port "#!~a/bin/bash
export GUIX_SANDBOX_HOME=\"${GUIX_SANDBOX_HOME:-$HOME}\"
# The host SSL_CERT_FILE/SSL_CERT_DIR point outside the container (store
# path not shared, /run/current-system absent); override them with the
# bundle provided by nss-certs inside the FHS container.
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export SSL_CERT_DIR=/etc/ssl/certs
export CURL_CA_BUNDLE=\"$SSL_CERT_FILE\"
export GIT_SSL_CAINFO=\"$SSL_CERT_FILE\"
exec ~a \"$@\"
"
                       #$bash-minimal real)))
           (chmod dest #o755)))))))
