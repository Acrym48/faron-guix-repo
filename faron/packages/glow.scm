(define-module (faron packages glow)
  #:use-module (guix packages)
  #:use-module (guix build-system go)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages golang)
  #:use-module (gnu packages golang-build)
  #:use-module (gnu packages golang-check)
  #:use-module (gnu packages golang-web)
  #:use-module (gnu packages golang-xyz))

(define-public go-github-com-charmbracelet-x-editor
  (package
    (name "go-github-com-charmbracelet-x-editor")
    (version "0.1.0")
    (source
     (origin
       (method git-fetch/lfs)
       (uri (git-reference
              (url "https://github.com/charmbracelet/x")
              (commit "editor/v0.1.0")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0dl09xqvffrv7hxhvq68kdrvkn4qgdxkic5c4sjc6c8xzs9j7bj9"))
       (modules '((guix build utils)
                  (ice-9 ftw)
                  (srfi srfi-26)))
       (snippet
        #~(begin
            (define (delete-all-but directory . preserve)
              (with-directory-excursion directory
                (let* ((pred (negate (cut member <>
                                          (cons* "." ".." preserve))))
                       (items (scandir "." pred)))
                  (for-each (cut delete-file-recursively <>) items))))
            (delete-all-but "." "editor")))))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "github.com/charmbracelet/x/editor"
      #:unpack-path "github.com/charmbracelet/x"))
    (home-page "https://github.com/charmbracelet/x")
    (synopsis "Open files in text editors")
    (description
     "This package provides helpers for opening files in a text editor from a
@code{GO} program, with support for highlighting the current line in common
editors.")
    (license license:expat)))

(define-public go-github-com-muesli-gitcha
  (package
    (name "go-github-com-muesli-gitcha")
    (version "0.3.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/muesli/gitcha")
              (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0726w3cg4c22jgh82dii6ygmwm5wsii660wra5xhgjmbqrr8i4pn"))))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "github.com/muesli/gitcha"
      #:tests? #f))
    (native-inputs
     (list go-github-com-stretchr-testify))
    (propagated-inputs
     (list go-github-com-sabhiram-go-gitignore))
    (home-page "https://github.com/muesli/gitcha")
    (synopsis "Gitignore-aware file finder")
    (description
     "This package provides utilities to find files inside a git repository,
taking @code{.gitignore} rules into account.")
    (license license:expat)))

(define-public go-github-com-muesli-go-app-paths
  (package
    (name "go-github-com-muesli-go-app-paths")
    (version "0.2.2")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/muesli/go-app-paths")
              (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "19g7fzyqg8d0nkb50h1rjk3q87v0yd1g9mh55ywgw85m5cji3w69"))))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "github.com/muesli/go-app-paths"
      #:tests? #f))
    (propagated-inputs
     (list go-github-com-mitchellh-go-homedir))
    (home-page "https://github.com/muesli/go-app-paths")
    (synopsis "Retrieve platform-specific application paths")
    (description
     "This package provides a cross-platform way to resolve application-specific
directories such as config, cache and data dirs.")
    (license license:expat)))

(define-public go-github-com-charmbracelet-x-ansi-next
  (package
    (name "go-github-com-charmbracelet-x-ansi")
    (version "0.11.8")
    (source
     (origin
       (method git-fetch/lfs)
       (uri (git-reference
              (url "https://github.com/charmbracelet/x")
              (commit "ansi/v0.11.8")))
       (file-name (git-file-name name version))
       (sha256 (base32 "070gjf4f0pgbnwik6bd7cp8lac76xjq7g851n21bd9iq269wchvq"))
       (modules '((guix build utils)
                  (ice-9 ftw)
                  (srfi srfi-26)))
       (snippet
        #~(begin
            (define (delete-all-but directory . preserve)
              (with-directory-excursion directory
                (let* ((pred (negate (cut member <>
                                          (cons* "." ".." preserve))))
                       (items (scandir "." pred)))
                  (for-each (cut delete-file-recursively <>) items))))
            (delete-all-but "." "ansi")))))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "github.com/charmbracelet/x/ansi"
      #:unpack-path "github.com/charmbracelet/x"))
    (propagated-inputs
     (list go-github-com-bits-and-blooms-bitset
           go-github-com-clipperhouse-displaywidth
           go-github-com-clipperhouse-uax29-v2
           go-github-com-lucasb-eyer-go-colorful
           go-github-com-mattn-go-runewidth))
    (home-page "https://github.com/charmbracelet/x")
    (synopsis "ANSI escape sequence parser and definitions")
    (description
     "This package defines common ANSI escape sequences based on the ECMA-48
specs.")
    (license license:expat)))

(define-public go-github-com-charmbracelet-x-term-next
  (package
    (name "go-github-com-charmbracelet-x-term")
    (version "0.2.2")
    (source
     (origin
       (method git-fetch/lfs)
       (uri (git-reference
              (url "https://github.com/charmbracelet/x")
              (commit "term/v0.2.2")))
       (file-name (git-file-name name version))
       (sha256 (base32 "0gah6pnr4l7ap99haiqmn33csh4zqsls176nih2pn6hxm6089fij"))
       (modules '((guix build utils)
                  (ice-9 ftw)
                  (srfi srfi-26)))
       (snippet
        #~(begin
            (define (delete-all-but directory . preserve)
              (with-directory-excursion directory
                (let* ((pred (negate (cut member <>
                                          (cons* "." ".." preserve))))
                       (items (scandir "." pred)))
                  (for-each (cut delete-file-recursively <>) items))))
            (delete-all-but "." "term")))))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "github.com/charmbracelet/x/term"
      #:unpack-path "github.com/charmbracelet/x"))
    (propagated-inputs
     (list go-golang-org-x-sys))
    (home-page "https://github.com/charmbracelet/x")
    (synopsis "Terminal utilities and helpers")
    (description
     "This package provides terminal utilities and helpers for Go.")
    (license license:expat)))

(define-public go-github-com-charmbracelet-x-windows-next
  (package
    (name "go-github-com-charmbracelet-x-windows")
    (version "0.2.2")
    (source
     (origin
       (method git-fetch/lfs)
       (uri (git-reference
              (url "https://github.com/charmbracelet/x")
              (commit "windows/v0.2.2")))
       (file-name (git-file-name name version))
       (sha256 (base32 "0cvpyks5pnfsb7ifm2bdd1jaw50q39bdf7vj4lnhjyw1l62xn5v0"))
       (modules '((guix build utils)
                  (ice-9 ftw)
                  (srfi srfi-26)))
       (snippet
        #~(begin
            (define (delete-all-but directory . preserve)
              (with-directory-excursion directory
                (let* ((pred (negate (cut member <>
                                          (cons* "." ".." preserve))))
                       (items (scandir "." pred)))
                  (for-each (cut delete-file-recursively <>) items))))
            (delete-all-but "." "windows")))))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "github.com/charmbracelet/x/windows"
      #:unpack-path "github.com/charmbracelet/x"))
    (propagated-inputs
     (list go-golang-org-x-sys))
    (home-page "https://github.com/charmbracelet/x")
    (synopsis "Windows API used at Charmbracelet")
    (description
     "This package provides Windows API bindings used by the Charmbracelet
@code{x} packages.")
    (license license:expat)))

(define-public go-github-com-charmbracelet-x-cellbuf-next
  (package
    (name "go-github-com-charmbracelet-x-cellbuf")
    (version "0.0.15")
    (source
     (origin
       (method git-fetch/lfs)
       (uri (git-reference
             (url "https://github.com/charmbracelet/x")
             (commit "cellbuf/v0.0.15")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "17f37m2zzhxcm422h143khvhfmh2k1jc6mqhrz6xqmhibqvgwh3a"))
       (modules '((guix build utils)
                  (ice-9 ftw)
                  (srfi srfi-26)))
       (snippet
        #~(begin
            (define (delete-all-but directory . preserve)
              (with-directory-excursion directory
                (let* ((pred (negate (cut member <>
                                         (cons* "." ".." preserve))))
                       (items (scandir "." pred)))
                  (for-each (cut delete-file-recursively <>) items))))
            (delete-all-but "." "cellbuf")))))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "github.com/charmbracelet/x/cellbuf"
      #:unpack-path "github.com/charmbracelet/x"))
    (propagated-inputs
     (list go-github-com-charmbracelet-colorprofile
           go-github-com-charmbracelet-x-ansi-next
           go-github-com-charmbracelet-x-term-next
           go-github-com-mattn-go-runewidth
           go-github-com-rivo-uniseg
           go-github-com-xo-terminfo))
    (home-page "https://github.com/charmbracelet/x")
    (synopsis "Cell-based terminal model for the Charmbracelet x library")
    (description
     "This package provides a cell-based terminal model used by the Charmbracelet
@code{x} packages.")
    (license license:expat)))

(define-public go-github-com-charmbracelet-ultraviolet
  (package
    (name "go-github-com-charmbracelet-ultraviolet")
    (version "0.0.0-20260811")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/charmbracelet/ultraviolet")
              (commit "006e29f97886822b5d62d373b29f3143a7220ac3")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "04hnq7qk7nlac0vzv7w6xp1i5895gf043kg3yd3320px1iks1jmr"))))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "github.com/charmbracelet/ultraviolet"
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'remove-extras
            (lambda* (#:key import-path #:allow-other-keys)
              (with-directory-excursion (string-append "src/" import-path)
                (for-each delete-file-recursively
                          '("examples" "internal/conformance"))))))))
    (propagated-inputs
     (list go-github-com-charmbracelet-colorprofile
           go-github-com-charmbracelet-x-ansi-next
           go-github-com-charmbracelet-x-term-next
           go-github-com-charmbracelet-x-termios
           go-github-com-charmbracelet-x-windows-next
           go-github-com-clipperhouse-displaywidth
           go-github-com-clipperhouse-uax29-v2
           go-github-com-lucasb-eyer-go-colorful
           go-github-com-mattn-go-runewidth
           go-github-com-muesli-cancelreader
           go-github-com-rivo-uniseg
           go-github-com-xo-terminfo
           go-golang-org-x-sync
           go-golang-org-x-sys))
    (home-page "https://github.com/charmbracelet/ultraviolet")
    (synopsis "Virtual terminal emulator in Go")
    (description
     "This package provides a terminal emulator using the Charm @code{x/ansi}
and @code{x/term} packages.")
    (license license:expat)))

(define-public go-charm-land-lipgloss-v2
  (package
    (name "go-charm-land-lipgloss-v2")
    (version "2.0.6")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/charmbracelet/lipgloss")
              (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "19l95pds8ic39wnjhl54knc1k7jlky6dfxblxyksr9fmjmqfa693"))))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "charm.land/lipgloss/v2"
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'remove-examples
            (lambda* (#:key import-path #:allow-other-keys)
              (with-directory-excursion (string-append "src/" import-path)
                (for-each delete-file-recursively '("examples"))))))))
    (native-inputs
     (list go-github-com-charmbracelet-x-exp-golden))
    (propagated-inputs
     (list go-github-com-aymanbagabas-go-udiff
           go-github-com-charmbracelet-colorprofile
           go-github-com-charmbracelet-ultraviolet
           go-github-com-charmbracelet-x-ansi-next
           go-github-com-charmbracelet-x-term-next
           go-github-com-charmbracelet-x-termios
           go-github-com-charmbracelet-x-windows-next
           go-github-com-clipperhouse-displaywidth
           go-github-com-clipperhouse-uax29-v2
           go-github-com-lucasb-eyer-go-colorful
           go-github-com-mattn-go-runewidth
           go-github-com-muesli-cancelreader
           go-github-com-rivo-uniseg
           go-github-com-xo-terminfo
           go-golang-org-x-sync
           go-golang-org-x-sys))
    (home-page "https://github.com/charmbracelet/lipgloss")
    (synopsis "Style definitions for nice terminal layouts")
    (description
     "This package provides a library for styling terminal output with colors,
layout and formatting helpers.")
    (license license:expat)))

(define-public go-charm-land-bubbletea-v2
  (package
    (name "go-charm-land-bubbletea-v2")
    (version "2.0.8")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/charmbracelet/bubbletea")
              (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "1m0mb529gn47vy3j7nm6bx832hvq7sna9q1icl0cgw4r1afs3x0q"))))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "charm.land/bubbletea/v2"
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'remove-examples
            (lambda* (#:key import-path #:allow-other-keys)
              (with-directory-excursion (string-append "src/" import-path)
                (for-each delete-file-recursively
                          '("examples" "tutorials"))))))))
    (native-inputs
     (list go-github-com-charmbracelet-x-exp-golden))
    (propagated-inputs
     (list go-github-com-aymanbagabas-go-udiff
           go-github-com-charmbracelet-colorprofile
           go-github-com-charmbracelet-ultraviolet
           go-github-com-charmbracelet-x-ansi-next
           go-github-com-charmbracelet-x-term-next
           go-github-com-charmbracelet-x-termios
           go-github-com-charmbracelet-x-windows-next
           go-github-com-clipperhouse-displaywidth
           go-github-com-clipperhouse-uax29-v2
           go-github-com-lucasb-eyer-go-colorful
           go-github-com-mattn-go-runewidth
           go-github-com-muesli-cancelreader
           go-github-com-rivo-uniseg
           go-github-com-xo-terminfo
           go-golang-org-x-sync
           go-golang-org-x-sys))
    (home-page "https://github.com/charmbracelet/bubbletea")
    (synopsis "Powerful little TUI framework for Go")
    (description
     "This package provides a framework for building terminal user
interfaces (TUIs) in Go.")
    (license license:expat)))

(define-public go-charm-land-bubbles-v2
  (package
    (name "go-charm-land-bubbles-v2")
    (version "2.1.1")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
              (url "https://github.com/charmbracelet/bubbles")
              (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "1i91gqgqpxvlwca7r633ckvni5y530vild3y75ri75vg4myr2hfb"))))
    (build-system go-build-system)
    (arguments
     (list
      #:import-path "charm.land/bubbles/v2"
      #:tests? #f))
    (native-inputs
     (list go-github-com-charmbracelet-x-exp-golden))
    (propagated-inputs
     (list go-charm-land-bubbletea-v2
           go-charm-land-lipgloss-v2
           go-github-com-atotto-clipboard
           go-github-com-charmbracelet-harmonica
           go-github-com-charmbracelet-x-ansi-next
           go-github-com-dustin-go-humanize
           go-github-com-makenowjust-heredoc
           go-github-com-mattn-go-runewidth
           go-github-com-rivo-uniseg
           go-github-com-sahilm-fuzzy))
    (home-page "https://github.com/charmbracelet/bubbles")
    (synopsis "TUI components for Bubble Tea")
    (description
     "This package provides a collection of TUIs, components and utilities for
use with Bubble Tea: list, paginator, spinner, textinput and more.")
    (license license:expat)))

(define-public go-charm-land-glamour-v2
  (package
    (name "go-charm-land-glamour-v2")
    (version "2.0.1")
    (source
     (origin
       (method git-fetch/lfs)
       (uri (git-reference
              (url "https://github.com/charmbracelet/glamour")
              (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "1gqx2zdsdmblc5czirv5ykyfjimsp4155jawk417aqrgrxn7mfq0"))))
    (build-system go-build-system)
(arguments
     (list
      #:import-path "charm.land/glamour/v2"
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'fix-embed-files 'materialize-embed-chroma
            (lambda _
              (with-directory-excursion "src"
                (for-each
                 (lambda (dir)
                   (for-each
                    (lambda (file)
                      (when (eq? 'symlink (stat:type (lstat file)))
                        (let ((target (readlink file)))
                          (delete-file file)
                          (copy-recursively target file))))
                    (find-files dir)))
                 (list (string-append "github.com/alecthomas/chroma/v2/lexers/embedded")
                       (string-append "github.com/alecthomas/chroma/v2/styles")))))))))
    (native-inputs
     (list go-github-com-charmbracelet-x-exp-golden))
    (propagated-inputs
     (list go-charm-land-lipgloss-v2
           go-github-com-alecthomas-chroma-v2
           go-github-com-aymerick-douceur
           go-github-com-charmbracelet-x-ansi-next
           go-github-com-charmbracelet-x-exp-golden
           go-github-com-charmbracelet-x-exp-slice
           go-github-com-dlclark-regexp2
           go-github-com-gorilla-css
           go-github-com-microcosm-cc-bluemonday
           go-github-com-yuin-goldmark
           go-github-com-yuin-goldmark-emoji
           go-golang-org-x-text))
    (home-page "https://github.com/charmbracelet/glamour")
    (synopsis "Write handsome command-line apps with markdown")
    (description
     "This package provides a markdown rendering engine for any GO-CLI
application, allowing you to render markdown documents as styled terminal
output.")
    (license license:expat)))

(define-public glow
  (package
     (name "glow")
     (version "3.0.0")
     (source
       (origin
	 (method git-fetch)
	 (uri (git-reference
	        (url "https://github.com/charmbracelet/glow")
		(commit "7b2431d4a82428fb477eb4361e11583e1644e9ba")))
	 (file-name (git-file-name name version))
	 (sha256
	   (base32 "05cyh8ccsav348sjs5h6jlzzhk8cid6vqq39qr64vz5jivjvpz5n"))))
     (build-system go-build-system)
     (arguments
       (list
	 #:import-path "charm.land/glow/v3"
	 #:install-source? #f
#:phases
 	 #~(modify-phases %standard-phases
 	     (add-after 'fix-embed-files 'materialize-embed-chroma
	       (lambda _
		 (with-directory-excursion "src"
		   (for-each
		    (lambda (dir)
		      (for-each
		       (lambda (file)
			 (when (eq? 'symlink (stat:type (lstat file)))
			   (let ((target (readlink file)))
			     (delete-file file)
			     (copy-recursively target file))))
		       (find-files dir)))
		    (list (string-append "github.com/alecthomas/chroma/v2/lexers/embedded")
			  (string-append "github.com/alecthomas/chroma/v2/styles"))))))
	     (replace 'build
		      (lambda* (#:key import-path outputs #:allow-other-keys)
		        (invoke "go" "build"
				"-ldflags=-s -w"
				"-trimpath"
				"-o"
				(string-append (assoc-ref outputs "out") "/bin/glow")
				import-path))))))
     (inputs (list go-charm-land-bubbles-v2
		   go-charm-land-bubbletea-v2
		   go-charm-land-glamour-v2
		   go-charm-land-lipgloss-v2
		   go-github-com-charmbracelet-x-cellbuf-next
		   go-github-com-charmbracelet-x-editor
		   go-github-com-atotto-clipboard
		   go-github-com-caarlos0-env
		   go-github-com-charmbracelet-log
		   go-github-com-dustin-go-humanize
		   go-github-com-fsnotify-fsnotify
		   go-github-com-mattn-go-runewidth
		   go-github-com-mitchellh-go-homedir
		   go-github-com-muesli-gitcha
		   go-github-com-muesli-go-app-paths
		   go-github-com-muesli-mango-cobra
		   go-github-com-muesli-reflow
		   go-github-com-muesli-mango-pflag
		   go-github-com-muesli-termenv
		   go-github-com-sahilm-fuzzy
		   go-github-com-spf13-cobra
		   go-github-com-spf13-viper
		   go-golang-org-x-sys
		   go-golang-org-x-term
		   go-golang-org-x-text
		   go-mvdan-cc-sh-v3))
     (home-page "https://github.com/charmbracelet/glow")
     (synopsis "Glow is a terminal based markdown reader designed from the ground up to bring out the beauty—and power—of the CLI.")
     (description
       "Use it to discover markdown files, read documentation directly on the command line. Glow will find local markdown files in subdirectories or a local Git repository.")
     (license license:expat)))
