(define-module (faron packages android)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system meson)
  #:use-module (guix gexp)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system trivial)
  #:use-module (guix build-system gnu)
  #:use-module (gnu packages)
  #:use-module (gnu packages base)
  #:use-module (gnu packages elf)
  #:use-module (gnu packages android)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages sdl)
  #:use-module (gnu packages video)
  #:use-module (gnu packages xorg)
  #:use-module (gnu packages xdisorg)
  #:use-module (gnu packages libusb)
  #:use-module (gnu packages qt)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages bash)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (nonguix licenses)
  #:use-module (nonguix multiarch-container)
  #:export (android-studio odin4 odin4-gui scrcpy))

  (define (aarch64-build?)
    (string-prefix? "aarch64"
		    (or (%current-target-system) (%current-system))))

(define %android-studio-version "2026.2.2.8")
(define %android-studio-codename "rabbit2")

(define %odin4-version "7.3.0")
(define %odin4-id "a46321b")

(define %scrcpy-version "5.0.1")

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

(define-public odin4
  (package
   (name "odin4")
   (version %odin4-version)
   (source
    (if (aarch64-build?)
	(origin
	 (method url-fetch)
	 (uri (string-append
	       "https://github.com/Llucs/odin4/releases/download/v"
	       version
	       "/odin4_arm64_"
	       version
	       "-"
	       %odin4-id))
	 (file-name (string-append "odin4-" version))
	 (sha256 (base32 "1f791czz5526j0lk27k86zvfyhps4ik94as85q3fc28imz4qzlkf")))
	(origin
	 (method url-fetch)
	 (uri (string-append
	       "https://github.com/Llucs/odin4/releases/download/v"
	       version
	       "/odin4_x86_64_"
	       version
	       "-"
	       %odin4-id))
	 (file-name (string-append "odin4-" version))
	 (sha256 (base32 "005dhqhj58jzpw62a0d1jls43sh7vw67lqhrs3mix71krxyzqfjy")))))
   (build-system gnu-build-system)
   (native-inputs (list patchelf))
   (inputs (list libusb glibc (list gcc-14 "lib")))
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
					(odin4-file (string-append bin "/odin4"))
					(src (assoc-ref %build-inputs "source")))
				   (mkdir-p bin)
				   (copy-file src odin4-file)
				   (chmod odin4-file #o755)
				   (invoke "patchelf"
					   "--set-interpreter"
					   #$(if (aarch64-build?)
						 (file-append glibc
							      "/lib/ld-linux-aarch64.so.1")
						 (file-append glibc
							      "/lib/ld-linux-x86-64.so.2"))
					   "--set-rpath"
					   (string-append #$libusb "/lib:" #$gcc-14:lib "/lib")
					   odin4-file)))))))
   (synopsis "odin4 is a flash tool for Samsung devices.")
   (description "odin4 is a flash tool for Samsung devices.")
   (home-page "https://github.com/Llucs/odin4")
   (license license:asl2.0)))

(define odin4-gui-icon
  (origin
   (method url-fetch)
   (uri "https://raw.githubusercontent.com/Llucs/odin4/main/docs/assets/logo.png")
   (sha256 (base32 "11z1mg9z3zwl4dw1nfj4izza9xdc211kx83fqm17wzr0065ikqp3"))))

(define-public odin4-gui
  (package
   (name "odin4-gui")
   (version %odin4-version)
   (source
    (if (aarch64-build?)
	(origin
	 (method url-fetch)
	 (uri (string-append
	       "https://github.com/Llucs/odin4/releases/download/v"
	       version
	       "/odin4-gui_arm64_"
	       version
	       "-"
	       %odin4-id))
	 (file-name (string-append "odin4-gui-" version))
	 (sha256 (base32 "1m2s62s42lj9d7k3knahbf4lj5kl79n32fa971b7ljpdaxxjg2r3")))
	(origin
	 (method url-fetch)
	 (uri (string-append
	       "https://github.com/Llucs/odin4/releases/download/v"
	       version
	       "/odin4-gui_x86_64_"
	       version
	       "-"
	       %odin4-id))
	 (file-name (string-append "odin4-gui-" version))
	 (sha256 (base32 "15zmqaccn9imcxn0zr15nzyqyg5zp29jr7rpn4g85hcwwdqwhz73")))))
   (build-system gnu-build-system)
   (native-inputs (list patchelf))
   (inputs (list libusb qtbase glibc (list gcc-14 "lib")))
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
					(odin4-gui-file (string-append bin "/odin4-gui"))
					(src (assoc-ref %build-inputs "source")))
				   (mkdir-p bin)
				   (copy-file src odin4-gui-file)
				   (chmod odin4-gui-file #o755)
				   (invoke "patchelf"
					   "--set-interpreter"
					   #$(if (aarch64-build?)
						 (file-append glibc
							      "/lib/ld-linux-aarch64.so.1")
						 (file-append glibc
							      "/lib/ld-linux-x86-64.so.2"))
					   "--set-rpath"
					   (string-append #$libusb "/lib:" #$gcc-14:lib "/lib:" #$qtbase "/lib")
					   odin4-gui-file))))
		      (add-after 'install 'install-desktop-file
				 (lambda* (#:key outputs #:allow-other-keys)
					  (let* ((out (assoc-ref outputs "out"))
						 (dest (string-append #$output "/bin/odin-gui"))
						 (icons (string-append out "/share/icons/pixmaps")))
					    (mkdir-p icons)
					    (copy-file #$odin4-gui-icon (string-append icons "/odin4-gui.png"))
					    (make-desktop-entry-file
					     (string-append out "/share/applications/odin4-gui.desktop")
					     #:name "Odin4 gui"
					     #:exec dest
					     #:icon "odin4-gui"
					     #:categories '("Utility"))))))))
   (synopsis "odin4 is a flash tool for Samsung devices.")
   (description "odin4 is a flash tool for Samsung devices.")
   (home-page "https://github.com/Llucs/odin4")
   (license license:asl2.0)))

(define scrcpy-server
  (origin
   (method url-fetch)
   (uri (string-append "https://github.com/Genymobile/scrcpy/releases/download/v"
                       %scrcpy-version "/scrcpy-server-v" %scrcpy-version))
   (file-name (string-append "scrcpy-server-" %scrcpy-version))
   (sha256
    (base32 "0dn57gjn5dizpzbrgf31g969ka9bi0h12d6zx4gj3m8ik3vvckkn"))))

(define-public scrcpy
  (package
   (name "scrcpy")
   (version %scrcpy-version)
   (source
    (origin
     (method git-fetch)
     (uri (git-reference
           (url "https://github.com/Genymobile/scrcpy")
           (commit (string-append "v" version))))
     (file-name (git-file-name name version))
     (sha256
      (base32 "062fnhm5pj39cxygs276zqw780blfw6rf850r442iw587a63fsyf"))))
   (build-system meson-build-system)
   (arguments
    (list
     #:configure-flags
     #~(list (string-append "-Dprebuilt_server=" #$scrcpy-server))
     #:phases
     #~(modify-phases %standard-phases
		      (add-after 'install 'wrap-adb
				 (lambda* (#:key inputs outputs #:allow-other-keys)					  
					  (wrap-program (string-append (assoc-ref outputs "out")
								       "/bin/scrcpy")
							`("ADB" = (,(search-input-file inputs "/bin/adb")))))))))
   (native-inputs (list pkg-config))
   (inputs (list adb
                 bash-minimal
                 ffmpeg
                 libdrm
                 libusb
                 libva
                 sdl3))
   (home-page "https://github.com/Genymobile/scrcpy")
   (synopsis "Display and control Android devices over USB or TCP/IP")
   (description
    "Scrcpy mirrors the screen of an Android device and lets you control it
with the computer's keyboard and mouse.  It also supports audio forwarding,
screen recording, camera mirroring and a virtual V4L2 sink.  Nothing is
installed on the device: the server part is pushed through adb at start-up.
The Android server is the prebuilt jar from the upstream release.")
   (license license:asl2.0)))
