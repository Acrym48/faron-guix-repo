(define-module (faron packages java-runtimes)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix build-system trivial)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages java)
  #:export (java-runtimes))

;; Bundles several OpenJDK runtimes (17, 21, 25) in a single package so that
;; Minecraft launchers such as PolyMC can find a suitable JVM for any game
;; version.  Each runtime is kept in its own _jvm/<major>/ directory to avoid
;; name clashes (bin/java, etc.), and versioned launchers are provided on PATH.
(define-public java-runtimes
  (package
    (name "java-runtimes")
    (version "1.0")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
(let ((out #$output))
            (use-modules (guix build utils))
            (for-each
             (lambda (major input-label)
               (let* ((jvm (string-append out "/_jvm/" major))
                      (java (assoc-ref %build-inputs input-label)))
                 (mkdir-p (string-append out "/_jvm"))
                 (symlink java jvm)
                 (mkdir-p (string-append out "/bin"))
                 (symlink (string-append jvm "/bin/java")
                          (string-append out "/bin/java-" major))))
             '("17" "21" "25")
             '("openjdk17" "openjdk21" "openjdk25"))))))
    (inputs
     (list `("openjdk17" ,openjdk17)
           `("openjdk21" ,openjdk21)
           `("openjdk25" ,openjdk25)))
    (home-page "https://adoptium.net")
    (synopsis "Bundled OpenJDK runtimes (17, 21, 25) for Minecraft")
    (description
     "This package collects several OpenJDK runtimes (17, 21 and 25) in a
single store item.  Each runtime lives under _jvm/<major>/ and versioned
launchers are placed on PATH, so tools such as PolyMC can locate a suitable
Java runtime for any Minecraft version.  It provides the runtime convenience
of the upstream Temurin Builds while staying on the upstream Guix OpenJDK
builds.")
    (license license:gpl3)))