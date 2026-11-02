(define-module (faron packages android)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system trivial)
  #:use-module (gnu packages)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (nonguix licenses)
  #:use-module (nonguix multiarch-container)
  #:export (android-studio))

(define %android-studio-version "2026.2.2.8")
(define %android-studio-codename "rabbit2")

(define android-studio-meta-package
  (package
   (name "android-studio-meta-package")
   (version %android-studio-version)
   (source (origin
	    (method url-fetch)
	    (uri (string-append
		  "https://edgedl.me.gvt1.com/android/studio/ide-zips/"
		  version "/android-studio-"
		  %android-studio-codename
		  "-linux.tar.gz"))
	    (sha256 (base32 "0143agdhyylpw85n916rprkdxidg5j1d2npxga56269hf30dqzxl"))))
   (build-system copy-build-system)
   (arguments
    (list #:validate-runpath? #f
	  #:strip-binaries? #f
	  #:install-plan #~'(("." "/opt/android-studio"))
	  #:phases
	  #~(modify-phases %standard-phases
			   (add-after 'install 'create-symlink
				      (lambda* (#:key outputs #:allow-other-keys)
					       (let* ((out (assoc-ref outputs "out"))
						      (bin (string-append out "/bin"))
						      (studio (string-append out "/opt/android-studio/bin/studio.sh")))
						 (mkdir-p bin)
						 (symlink studio (string-append bin "/android-studio"))))))))
   (synopsis "IDE for Android development")
   (description "Android Studio is the official IDE for Android...")
   (home-page "https://developer.android.com/studio")
   (license (nonfree "https://developer.android.com/studio/terms"
                     "Contains proprietary components; see the Android Studio Terms and Conditions."))))

(define android-studio-container
  (nonguix-container
   (name "android-studio")
   (wrap-package android-studio-meta-package)
   (run "/bin/android-studio")
   (union64
    (fhs-union
     (map specification->package
          '("gcc-toolchain" "glibc-locales"
            "coreutils" "grep" "sed" "gawk" "findutils" "which"
            "zlib" "nss" "nspr" "alsa-lib" "eudev"
            "freetype" "fontconfig" "font-dejavu"
            "libx11" "libxext" "libxrender" "libxtst" "libxi"
            "libxrandr" "libxcursor" "libxcomposite" "libxdamage"
            "libxfixes" "libxkbcommon" "libxcb"
            "mesa" "libdrm" "gtk+" "dbus" "libsecret"))
     #:name "fhs-union-64"))
   (preserved-env '("^WAYLAND_DISPLAY$" "^XDG_RUNTIME_DIR$"
                    "^DBUS_SESSION_BUS_ADDRESS$" "^XDG_CURRENT_DESKTOP$"
                    "^DISPLAY$" "^XAUTHORITY$"))
   (description "Android-studio inside an FHS container.")))

(define android-studio-container-package
  (nonguix-container->package android-studio-container))

(define-public android-studio
  (package
   (inherit android-studio-container-package)
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
                (dest (string-append bin "/android-studio"))
                (real (string-append #$android-studio-container-package
                                     "/bin/android-studio")))
           (mkdir-p bin)
           (call-with-output-file dest
             (lambda (port)
               (format port "#!~a/bin/bash
export GUIX_SANDBOX_HOME=\"${GUIX_SANDBOX_HOME:-$HOME}\"
exec ~a \"$@\"
"
                       #$bash-minimal real)))
           (chmod dest #o755)
           (let ((apps (string-append #$output "/share/applications"))
		 (pixmaps (string-append #$output "/share/pixmaps")))
           (mkdir-p apps)
	   (mkdir-p pixmaps)
	   (copy-file (string-append #$android-studio-meta-package
				     "/opt/android-studio/bin/studio.png")
		      (string-append pixmaps "/android-studio.png"))
	   (make-desktop-entry-file
	    (string-append apps "/android-studio.desktop")
	    #:name "Android Studio"
	    #:comment "IDE for Android development"
	    #:exec dest
	    #:icon "android-studio"
	    #:categories '("Development" "IDE")))))))))
