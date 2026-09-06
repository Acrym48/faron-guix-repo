(define-module (faron packages binaries)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix download)
  #:use-module (guix build-system gnu)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages elf)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages base)
  #:export (yazi))

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
