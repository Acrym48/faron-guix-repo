(define-module (faron packages fonts)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix utils)
  #:use-module (guix download)
  ;; NOTE: (guix build-system font) must come BEFORE (guix build-system gnu).
  ;; It has no #:export clause, so it re-exports everything it imports --
  ;; including the `replace' macro of (guix packages), which only accepts
  ;; `modify-inputs' forms.  With that import last, the `replace' inside the
  ;; gexp below resolves to it and the module fails to compile with
  ;; "'replace' may only be used within 'modify-inputs'".  Importing
  ;; (guix build-system gnu) last puts its own `replace' back in scope.
  #:use-module (guix build-system font)
  #:use-module (guix build-system gnu)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages compression)
  #:export (font-microsoft-times-new-roman))

;; Microsoft core fonts for the web.  nongnu carries these in
;; (nongnu packages fonts), but that module does not exist in the Guix
;; that `guix pull' uses to build this channel, so importing it from a
;; channel module makes the channel itself fail to build.  Define the
;; one family we need here instead.
;;
;; The upstream artifact is a 7-Zip self-extracting .exe.  SourceForge's
;; per-datacenter hostnames (deac-ams and friends) now only redirect to
;; downloads.sourceforge.net, so talk to the canonical host directly; Guix
;; hashes content rather than URLs, so the sha256 is the same one nongnu
;; uses for this file.
(define-public font-microsoft-times-new-roman
  (package
    (name "font-microsoft-times-new-roman")
    (version "2.82")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://downloads.sourceforge.net/project/corefonts/"
             "the%20fonts/final/times32.exe"))
       (sha256
        (base32 "1aq7z3l46vwgqljvq9zfgkii6aivy00z1529qbjkspggqrg5jmnv"))))
    (build-system font-build-system)
    (arguments
     (list
      #:phases
      #~(modify-phases %standard-phases
          ;; 7z e drops the faces into ./font with .TTF extensions;
          ;; fontconfig only picks up the lowercase ones.  The face names
          ;; upstream are already lowercase, so downcasing the whole file
          ;; name is equivalent to rewriting just the extension.
          (replace 'unpack
            (lambda* (#:key source #:allow-other-keys)
              (invoke "7z" "e" source "-ofont")
              (for-each (lambda (oldname)
                          (rename-file oldname (string-downcase oldname)))
                        (find-files "font" "\\.TTF$")))))))
    (native-inputs (list p7zip))
    (home-page "https://sourceforge.net/projects/corefonts/")
    (synopsis "Times New Roman font")
    (description
     "This package provides Times New Roman from the Microsoft core fonts
for the web.")
    (license (license:non-copyleft
              "https://corefonts.sourceforge.net/eula.htm"))))