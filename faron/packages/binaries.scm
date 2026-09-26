(define-module (faron packages binaries)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix download)
  #:use-module (guix build-system gnu)
  #:use-module (guix utils)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages elf)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages base)
  #:export (yazi codebase-memory-mcp))

(define (aarch64-build?)
  (string-prefix? "aarch64"
                  (or (%current-target-system) (%current-system))))

;; Prebuilt Rust binary from GitHub Releases; glibc interpreter and rpath are
;; set to find libc and libgcc_s.so.1 from the Guix store.
(define-public yazi
  (package
    (name "yazi")
    (version "26.9.1")
    (source
     (if (aarch64-build?)
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://github.com/sxyazi/yazi/releases/download/v"
                 version "/yazi-aarch64-unknown-linux-gnu.zip"))
           (sha256
            (base32 "0fhb6xdkhhai2lx2pc9vlbbran9zv1cy590nfmdvd2dmsq47z002")))
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://github.com/sxyazi/yazi/releases/download/v"
                 version "/yazi-x86_64-unknown-linux-gnu.zip"))
           (sha256
            (base32 "1lka1ba8is18ff9gdv4q9qm8fmh823qi1w41qr440a846cfyjbx0")))))
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
                           #$(if (aarch64-build?)
                                 (file-append glibc
                                              "/lib/ld-linux-aarch64.so.1")
                                 (file-append glibc
                                              "/lib/ld-linux-x86-64.so.2"))
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

;; Fully static prebuilt binary from GitHub Releases; the portable Linux
;; archives carry no dynamic linkage, so no patchelf work is needed here.
(define-public codebase-memory-mcp
  (package
    (name "codebase-memory-mcp")
    (version "0.11.0")
    (source
     (if (aarch64-build?)
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://github.com/DeusData/codebase-memory-mcp/releases/download/v"
                 version "/codebase-memory-mcp-linux-arm64-portable.tar.gz"))
           (sha256
            (base32 "0yycj3rsxxv7zfrc9h8y0h5z2cqhrxifqf090yiypqsy9lifnbnn")))
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://github.com/DeusData/codebase-memory-mcp/releases/download/v"
                 version "/codebase-memory-mcp-linux-amd64-portable.tar.gz"))
           (sha256
            (base32 "10v6603dcgxarp7mqlmdzwlxg9ix0gyfi9r7z9fc1i9bxf9q57hz")))))
    (build-system gnu-build-system)
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
              (let ((bin (string-append #$output "/bin"))
                    (doc (string-append #$output "/share/doc/"
                                        #$name "-" #$version)))
                (mkdir-p bin)
                (mkdir-p doc)
                (install-file "codebase-memory-mcp" bin)
                (chmod (string-append bin "/codebase-memory-mcp") #o755)
                (install-file "LICENSE" doc)
                (install-file "THIRD_PARTY_NOTICES.md" doc)))))))
    (synopsis "Code intelligence MCP server backed by a knowledge graph")
    (description "codebase-memory-mcp is an MCP server that indexes a codebase
into a persistent local knowledge graph using vendored tree-sitter grammars for
over 150 languages, and answers structural queries from AI coding agents in
under a millisecond.  It ships as a single self-contained, fully static
executable with no language runtime or API key.")
    (home-page "https://github.com/DeusData/codebase-memory-mcp")
    (license license:expat)))
