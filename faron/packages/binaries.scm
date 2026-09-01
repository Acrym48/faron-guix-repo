(define-module (faron packages binaries)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix download)
  #:use-module (guix build-system gnu)
  #:use-module (guix git-download)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages elf)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages base)
  #:export (opencode yazi))

;; Prebuilt glibc binary from GitHub Releases; ELF interpreter is patched to
;; the glibc loader from the Guix store ('-baseline' build). libgcc_s.so.1 is
;; shipped in lib/ and provided via LD_LIBRARY_PATH in the wrapper.
(define-public opencode
  (package
    (name "opencode")
    (version "1.18.25")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/anomalyco/opencode/releases/download/v"
             version "/opencode-linux-x64-baseline.tar.gz"))
       (sha256
        (base32 "0s19j9fn27cvl06kcsvkkv03x3n6rgxmrh6pmqg8nn8vc630blfc"))))
    (build-system gnu-build-system)
    (native-inputs (list patchelf))
    (inputs (list bash glibc (list gcc-14 "lib")))
    (arguments
     (list
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (delete 'build)
          (delete 'check)
          (delete 'validate-runpath)
          (delete 'strip)
          (replace 'install
            (lambda _
              (let* ((libexec (string-append #$output "/libexec"))
                     (lib (string-append #$output "/lib"))
                     (bin (string-append #$output "/bin"))
                     (real (string-append libexec "/opencode"))
                     (libgcc (search-input-file %build-inputs
                                                "lib/libgcc_s.so.1")))
                (mkdir-p libexec)
                (mkdir-p lib)
                (install-file "opencode" libexec)
                (chmod real #o755)
                (invoke "patchelf"
                        "--set-interpreter"
                        #$(file-append glibc "/lib/ld-linux-x86-64.so.2")
                        real)
                (install-file libgcc lib)
                (wrap-program real
                              #:sh #$(file-append bash "/bin/sh")
                              `("LD_LIBRARY_PATH" ":" prefix (,lib)))
                (mkdir-p bin)
                (symlink real (string-append bin "/opencode"))))))))
    (synopsis "Open source AI coding agent for the terminal")
    (description "opencode is an open source AI coding agent that helps you
write code in your terminal, IDE, or desktop.")
    (home-page "https://opencode.ai")
    (license license:expat)))

;; Prebuilt Rust binary from GitHub Releases; glibc interpreter and rpath are
;; set to find libc and libgcc_s.so.1 from the Guix store.
(define-public yazi
  (package
    (name "yazi")
    (version "26.9.1")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/sxyazi/yazi/releases/download/v"
             version "/yazi-x86_64-unknown-linux-gnu.zip"))
       (sha256
        (base32 "1lka1ba8is18ff9gdv4q9qm8fmh823qi1w41qr440a846cfyjbx0"))))
    (build-system gnu-build-system)
    (native-inputs (list patchelf unzip))
    (inputs (list glibc (list gcc-14 "lib")))
    (arguments
     (list
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (delete 'build)
          (delete 'check)
          (delete 'validate-runpath)
          (delete 'strip)
          (replace 'install
            (lambda _
              (let* ((bin (string-append #$output "/bin"))
                     (lib (string-append #$output "/lib"))
                     (libgcc (search-input-file %build-inputs
                                                "lib/libgcc_s.so.1")))
                (mkdir-p bin)
                (mkdir-p lib)
                (install-file "yazi" bin)
                (install-file "ya" bin)
                (chmod (string-append bin "/yazi") #o755)
                (chmod (string-append bin "/ya") #o755)
                (install-file libgcc lib)
                (for-each
                 (lambda (prog)
                   (invoke "patchelf"
                           "--set-interpreter"
                           #$(file-append glibc "/lib/ld-linux-x86-64.so.2")
                           "--set-rpath"
                           (string-append
                            #$(file-append glibc "/lib")
                            ":"
                            lib)
                           (string-append bin "/" prog)))
                 (list "yazi" "ya"))))))))
    (synopsis "Blazing fast terminal file manager")
    (description "yazi is a terminal file manager written in Rust, based on
async I/O.")
    (home-page "https://yazi-rs.github.io")
    (license license:expat)))
