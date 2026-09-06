(define-module (faron packages ai)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix download)
  #:use-module (guix build-system gnu)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages elf)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages base)
  #:export (opencode claude-code antigravity qwen-code))

;; Prebuilt glibc binary from GitHub Releases; ELF interpreter is patched to
;; the glibc loader from the Guix store ('-baseline' build). libgcc_s.so.1 is
;; shipped in lib/ and provided via LD_LIBRARY_PATH in the wrapper.
(define-public opencode
  (package
    (name "opencode")
    (version "1.18.29")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/anomalyco/opencode/releases/download/v"
             version "/opencode-linux-x64-baseline.tar.gz"))
       (sha256
        (base32 "0b84gxaspjlidmd6lkgmxjkcamlz73mki9y3wkipfd72cgqg58q3"))))
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

;; Prebuilt native binary from Anthropic's release server. The installer that
;; ships it patches nothing; we set the ELF interpreter to the Guix glibc
;; loader. Claude Code maintains its own state/updates under $HOME/.claude.
(define-public claude-code
  (package
    (name "claude-code")
    (version "2.1.263")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://downloads.claude.ai/claude-code-releases/"
             version "/linux-x64/claude"))
       (file-name (string-append "claude-" version))
       (sha256
        (base32 "1fnmh4diar2d6r1fbl5i3c6dzjdl8g7czwwhcw0g84l13qsj1l16"))))
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
                        #$(file-append glibc "/lib/ld-linux-x86-64.so.2")
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
     (origin
       (method url-fetch)
       (uri (string-append
             "https://storage.googleapis.com/antigravity-public/antigravity-cli/"
             version "-5211191891591168/linux-x64/cli_linux_x64.tar.gz"))
       (sha256
        (base32 "1gi0kbykgs4jcrp79zfv9bkbdz2nnrgz507mc3v2sg57p3vd8x7q"))))
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
                        #$(file-append glibc "/lib/ld-linux-x86-64.so.2")
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
    (version "0.23.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/QwenLM/qwen-code/releases/download/v"
             version "/qwen-code-linux-x64.tar.gz"))
       (sha256
        (base32 "1g859dkq5qakrdrixcmrhfqfx8kj7br4c2yxqqs0iahxgqigf86s"))))
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
                        #$(file-append glibc "/lib/ld-linux-x86-64.so.2")
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
