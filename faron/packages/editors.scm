(define-module (faron packages editors)
  #:use-module (guix packages)
  #:use-module (gnu packages ncurses)
  #:use-module (gnu packages llvm)
  #:use-module (guix gexp)
  #:use-module (guix utils)
  #:use-module (guix git-download)
  #:use-module (guix build-system gnu)
  #:use-module ((guix licenses) #:prefix license:))

(define-public atto
  (package
   (name "atto")
   (version "1.22")   
   (source
    (origin
     (method git-fetch)
     (uri (git-reference
           (url "https://github.com/hughbarney/atto")
           (commit "0b2c5bb0a236eb8d0272cdc7c501758b4fcc413c")))
     (file-name (git-file-name name version))
     (sha256
      (base32 "11afh1sbb4ljxn3896v8pkn8fiafdayicas4fy2f57f94vy5bavp"))))
   (build-system gnu-build-system)
   (arguments
    (list
     #:tests? #f
     #:make-flags
     #~(list (string-append "CC=clang")
	     (string-append "CXX=clang++")
             (string-append "PREFIX=" #$output))
     #:phases
     #~(modify-phases %standard-phases
		      (delete 'configure)
		      (replace 'install
			       (lambda _
				 (install-file "atto" (string-append #$output "/bin")))))))
   (native-inputs (list ncurses clang-toolchain))
   (inputs '())
   (home-page "https://github.com/hughbarney/atto")
   (synopsis "Atto is a tiny Emacs-style text editor in under 2000 lines of C.")
   (description "Atto Emacs is a minimal functional Emacs in less than 2000 lines of C code. It is derived from Anthony's Editor and uses a buffer-gap to represent the file in memory.")
   (license license:public-domain)))
