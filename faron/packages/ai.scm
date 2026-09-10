(define-module (faron packages ai)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix download)
  #:use-module (guix build-system gnu)
  #:use-module (guix utils)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages elf)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages base)
  #:export (opencode claude-code antigravity qwen-code kimi-code))

(define (aarch64-build?)
  (string-prefix? "aarch64"
                  (or (%current-target-system) (%current-system))))

;; Prebuilt glibc binary from GitHub Releases; ELF interpreter is patched to
;; the glibc loader from the Guix store ('-baseline' on x86_64).  libgcc_s.so.1
;; is shipped in lib/ and provided via LD_LIBRARY_PATH in the wrapper.
(define-public opencode
  (package
    (name "opencode")
    (version "1.18.30")
    (source
     (if (aarch64-build?)
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://github.com/anomalyco/opencode/releases/download/v"
                 version "/opencode-linux-arm64.tar.gz"))
           (sha256
            (base32 "1vb64mhn4vgz9xavk19bkp9fd0026fifjldx2k1zmh0259faa4a1")))
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://github.com/anomalyco/opencode/releases/download/v"
                 version "/opencode-linux-x64-baseline.tar.gz"))
           (sha256
            (base32 "0qz0cj56vprlzfzqsbgbb7whwzn8sdh759x8vl3acv6qs13j3jb0")))))
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
                        #$(if (aarch64-build?)
                              (file-append glibc
                                           "/lib/ld-linux-aarch64.so.1")
                              (file-append glibc
                                           "/lib/ld-linux-x86-64.so.2"))
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

;; Prebuilt native binary from Anthropic's release server. The installer that
;; ships it patches nothing; we set the ELF interpreter to the Guix glibc
;; loader. Claude Code maintains its own state/updates under $HOME/.claude.
(define-public claude-code
  (package
    (name "claude-code")
    (version "2.1.263")
    (source
     (if (aarch64-build?)
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://downloads.claude.ai/claude-code-releases/"
                 version "/linux-arm64/claude"))
           (file-name (string-append "claude-" version))
           (sha256
            (base32 "00sc5f8c5r7yav6inxmp3z9ry5vlyqbyir6sqyf00vkcmv4df9bx")))
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://downloads.claude.ai/claude-code-releases/"
                 version "/linux-x64/claude"))
           (file-name (string-append "claude-" version))
           (sha256
            (base32 "1fnmh4diar2d6r1fbl5i3c6dzjdl8g7czwwhcw0g84l13qsj1l16")))))
    (build-system gnu-build-system)
    (native-inputs (list patchelf))
    (inputs (list glibc))
    (arguments
     (list
      #:phases
      #~(modify-phases %standard-phases
          (replace 'unpack (lambda _ #t))
          (delete 'configure)
          (delete 'build)
          (delete 'check)
          (delete 'validate-runpath)
          (delete 'strip)
          (delete 'make-dynamic-linker-cache)
          (replace 'install
            (lambda _
              (let* ((bin (string-append #$output "/bin"))
                     (claude-file (string-append bin "/claude"))
                     (src (assoc-ref %build-inputs "source")))
                (mkdir-p bin)
                (copy-file src claude-file)
                (chmod claude-file #o755)
                (invoke "patchelf"
                        "--set-interpreter"
                        #$(if (aarch64-build?)
                              (file-append glibc
                                           "/lib/ld-linux-aarch64.so.1")
                              (file-append glibc
                                           "/lib/ld-linux-x86-64.so.2"))
                        claude-file)))))))
    (synopsis "AI coding assistant for the terminal")
    (description
     "Claude Code is Anthropic's AI coding assistant for the terminal.  It can
read and edit your code, run commands, and delegate subtasks to subagents.")
    (home-page "https://code.claude.com")
    (license (license:non-copyleft "https://code.claude.com"))))

;; Prebuilt Go binary from Google's auto-updater manifest; installed as 'agy'.
;; The self-updating binary checks for new versions during regular runs.
(define-public antigravity
  (package
    (name "antigravity")
    (version "1.1.27")
    (source
     (if (aarch64-build?)
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://github.com/google-antigravity/antigravity-cli/"
                 "releases/download/" version "/agy_cli_linux_arm64.tar.gz"))
           (sha256
            (base32 "153axdyc2ihjj63c9gik9ni275ic6rpaxr6b0b6hcx06lvjrzz4p")))
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://storage.googleapis.com/antigravity-public/antigravity-cli/"
                 version "-5211191891591168/linux-x64/cli_linux_x64.tar.gz"))
           (sha256
            (base32 "1gi0kbykgs4jcrp79zfv9bkbdz2nnrgz507mc3v2sg57p3vd8x7q")))))
    (build-system gnu-build-system)
    (native-inputs (list patchelf))
    (inputs (list glibc))
    (arguments
     (list
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (delete 'build)
          (delete 'check)
          (delete 'validate-runpath)
          (delete 'strip)
          (delete 'make-dynamic-linker-cache)
          (replace 'install
            (lambda _
              (let* ((bin (string-append #$output "/bin"))
                     (agy-file (string-append bin "/agy")))
                (mkdir-p bin)
                (copy-file "antigravity" agy-file)
                (chmod agy-file #o755)
(invoke "patchelf"
                        "--set-interpreter"
                        #$(if (aarch64-build?)
                              (file-append glibc
                                           "/lib/ld-linux-aarch64.so.1")
                              (file-append glibc
                                           "/lib/ld-linux-x86-64.so.2"))
                        agy-file)))))))
    (synopsis "AI coding agent for the terminal from Google")
    (description
     "Antigravity is an AI coding agent from Google that helps you build,
debug, and ship code from the terminal.")
    (home-page "https://antigravity.google")
    (license (license:non-copyleft "https://antigravity.google"))))

;; Prebuilt bundle from GitHub Releases. The tarball ships its own Node.js
;; runtime; the 'qwen' launcher script execs it with lib/cli-entry.js. We keep
;; the tree in place and patch the bundled Node interpreter/rpath to the Guix
;; store.
(define-public qwen-code
  (package
    (name "qwen-code")
    (version "0.23.2")
    (source
     (if (aarch64-build?)
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://github.com/QwenLM/qwen-code/releases/download/v"
                 version "/qwen-code-linux-arm64.tar.gz"))
           (sha256
            (base32 "0ayimxrywy22x68j3y1394jymrc7bpa9wrl91shz0hpvykgzbppn")))
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://github.com/QwenLM/qwen-code/releases/download/v"
                 version "/qwen-code-linux-x64.tar.gz"))
           (sha256
            (base32 "0hf2w3br1gr5nsq3amyclj515np33w605hc5p97dm9afc21cdrrj")))))
    (build-system gnu-build-system)
    (native-inputs (list patchelf))
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
           (delete 'make-dynamic-linker-cache)
           (replace 'unpack
             (lambda _
               (invoke "tar" "xvf"
                       (assoc-ref %build-inputs "source"))))
           (replace 'install
             (lambda _
               (let* ((lib (string-append #$output "/lib/qwen-code"))
                     (bin (string-append #$output "/bin"))
                     (node (string-append lib "/node/bin/node")))
                (mkdir-p lib)
                (copy-recursively "qwen-code" lib)
                (invoke "patchelf"
                        "--set-interpreter"
                        #$(if (aarch64-build?)
                              (file-append glibc
                                           "/lib/ld-linux-aarch64.so.1")
                              (file-append glibc
                                           "/lib/ld-linux-x86-64.so.2"))
                        node)
                (mkdir-p bin)
                (call-with-output-file (string-append bin "/qwen")
                  (lambda (port)
                    (format port
                            "#!/bin/sh~%set -e~%ROOT=\"~a\"~%LD_LIBRARY_PATH=\"~a\"${LD_LIBRARY_PATH:+\":$LD_LIBRARY_PATH\"}~%export LD_LIBRARY_PATH~%QWEN_CODE_LAUNCHER_PATH=\"$ROOT/bin/qwen\" exec \"$ROOT/node/bin/node\" \"$ROOT/lib/cli-entry.js\" \"$@\"~%"
                            lib
                            (dirname (search-input-file %build-inputs
                                                       "lib/libstdc++.so.6")))))
                (chmod (string-append bin "/qwen") #o755)))))))
    (synopsis "Open-source AI coding agent that lives in your terminal")
    (description
     "Qwen Code is an open-source AI coding agent that works in the terminal,
with agentic features like auto-memory, skills, subagents and MCP support.")
    (home-page "https://qwenlm.github.io/qwen-code-docs")
    (license license:asl2.0)))

;; Prebuilt native binary from Moonshot AI's release server (SEA bundle, needs
;; libstdc++.so.6 at runtime). The installer fetches the version from /latest
;; and the file from /binaries/<version>/manifest.json; we pin the version and
;; patch the ELF interpreter to the Guix glibc loader.
(define-public kimi-code
  (package
    (name "kimi-code")
    (version "0.41.0")
    (source
     (if (aarch64-build?)
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://code.kimi.com/kimi-code/binaries/"
                 version "/kimi-code-linux-arm64"))
           (file-name (string-append "kimi-code-" version))
           (sha256
            (base32 "1650lig4l5a5lpdzw8g8wsq5s7sq9xajq10ibyly6kb9ywg9na1m")))
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://code.kimi.com/kimi-code/binaries/"
                 version "/kimi-code-linux-x64"))
           (file-name (string-append "kimi-code-" version))
           (sha256
            (base32 "0iwip37vq5dv2k41cfq4nq6z3mlhnmz4lgza8g5r4dzx44xshcah")))))
    (build-system gnu-build-system)
    (native-inputs (list patchelf))
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
          (delete 'make-dynamic-linker-cache)
          (replace 'install
            (lambda _
              (let* ((bin (string-append #$output "/bin"))
                     (kimi-file (string-append bin "/kimi-code"))
                     (src (assoc-ref %build-inputs "source")))
                (mkdir-p bin)
                (copy-file src kimi-file)
                (chmod kimi-file #o755)
                (invoke "patchelf"
                        "--set-interpreter"
                        #$(if (aarch64-build?)
                              (file-append glibc
                                           "/lib/ld-linux-aarch64.so.1")
                              (file-append glibc
                                           "/lib/ld-linux-x86-64.so.2"))
                        kimi-file)
                (wrap-program kimi-file
                              #:sh #$(file-append bash "/bin/sh")
                              `("LD_LIBRARY_PATH" ":" prefix
                                (,(dirname
                                   (search-input-file
                                    %build-inputs
                                    "lib/libstdc++.so.6")))))))))))
    (synopsis "AI coding agent for the terminal from Moonshot AI")
    (description
     "Kimi Code is a coding agent from Moonshot AI that helps you write code
 from the terminal, built as a native single-executable bundle.")
    (home-page "https://kimi.com")
    (license (license:non-copyleft "https://kimi.com"))))
