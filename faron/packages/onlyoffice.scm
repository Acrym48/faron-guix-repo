(define-module (faron packages onlyoffice)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix download)
  #:use-module (guix build-system gnu)
  #:use-module (guix utils)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages cups)
  #:use-module (gnu packages elf)
  #:use-module (gnu packages fontutils)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages gl)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages gstreamer)
  #:use-module (gnu packages gtk)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages nss)
  #:use-module (gnu packages pulseaudio)
  #:use-module (gnu packages xdisorg)
  #:use-module (gnu packages xml)
  #:use-module (gnu packages xorg)
  #:use-module (nongnu packages fonts)
  #:export (onlyoffice-desktopeditors))

(define (aarch64-build?)
  (string-prefix? "aarch64"
                  (or (%current-target-system) (%current-system))))

;; Prebuilt Qt5/CEF office suite.  The tarball ships Linux images for both
;; architectures under opt/onlyoffice/desktopeditors plus a /usr tree (launcher,
;; .desktop, icons, licenses).  Everything except the base system libraries is
;; bundled (Qt5, libcef, ICU 52/74, Qt plugins), and DesktopEditors carries an
;; RPATH of $ORIGIN:$ORIGIN/system:$ORIGIN/converter, so it finds the bundled
;; libs on its own.  We only patch the ELF interpreter to the Guix glibc and
;; point the launcher's LD_LIBRARY_PATH at the Guix store libraries it dlopen's
;; (GTK3, X11/xcb, dbus, cups, NSS, GStreamer, ...).  CEF's chrome-sandbox is
;; not setuid in the tarball, so Chromium falls back to the unprivileged user
;; namespace sandbox.
;;
;; Fonts: CApplicationFonts ignores fontconfig and walks a hardcoded set of
;; directories (/usr/share/fonts, /usr/share/X11/fonts, /run/host/fonts,
;; /usr/local/share/fonts) plus $CUSTOM_FONTS_PATH.  None of those exist on
;; Guix, so the app only ever sees the fonts shipped in the tarball.  We bake
;; font packages into the tarball's own fonts/ tree as real files; see the
;; install phase for why symlinks (i.e. anything reachable through a Guix
;; profile) are invisible to it.
(define-public onlyoffice-desktopeditors
  (package
    (name "onlyoffice-desktopeditors")
    (version "10.0.0")
    (source
     (if (aarch64-build?)
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://github.com/ONLYOFFICE/DesktopEditors/releases/download/v"
                 version "/onlyoffice-desktopeditors-aarch64.tar.xz"))
           (sha256
            (base32 "1xqzda40pnjqw86nl77hyv1br9asyz3m5az6xnidifaz582nl9yi")))
         (origin
           (method url-fetch)
           (uri (string-append
                 "https://github.com/ONLYOFFICE/DesktopEditors/releases/download/v"
                 version "/onlyoffice-desktopeditors-x64.tar.xz"))
           (sha256
            (base32 "16nsjmcmf7jhjrkfmxp8q29lvvvj1w04v45m2cwgpilrcjz5hhdl")))))
    (build-system gnu-build-system)
    (native-inputs (list patchelf xz))
    (inputs
     (list bash
           glibc
           (list gcc-14 "lib")
           alsa-lib
           at-spi2-core
           cups
           dbus
           expat
           font-microsoft-times-new-roman
           fontconfig
           freetype
           gdk-pixbuf
           glib
           gst-plugins-base
           gstreamer
           gtk+
           libdrm
           libglvnd
           libnotify
           libsm
           libice
           libx11
           libxcb
           libxcomposite
           libxdamage
           libxext
           libxfixes
           libxi
           libxkbcommon
           libxrandr
           mesa
           nss
           pulseaudio))
    (arguments
     (list
      #:phases
      #~(modify-phases %standard-phases
          ;; The stock 'unpack' ends with (chdir (first-subdirectory ".")), and
          ;; first-subdirectory returns the *first* entry, not the only one.
          ;; This tarball has two top-level directories (opt and usr), so the
          ;; build would chdir into opt/ and the usr/ half would fall outside
          ;; the current directory.  Unpack in place instead.
          (replace 'unpack
            (lambda* (#:key source #:allow-other-keys)
              (invoke "tar" "xf" source)))
          (delete 'configure)
          (delete 'build)
          (delete 'check)
          (delete 'validate-runpath)
          (delete 'strip)
          (replace 'install
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (app (string-append out "/opt/onlyoffice/desktopeditors"))
                     (bin (string-append out "/bin"))
                     (share (string-append out "/share"))
                     (doc (string-append share "/doc/onlyoffice-desktopeditors"))
                     (loader #$(if (aarch64-build?)
                                   (file-append glibc "/lib/ld-linux-aarch64.so.1")
                                   (file-append glibc "/lib/ld-linux-x86-64.so.2")))
                     ;; ld.so runs the launcher with this set; the launcher then
                     ;; prepends $APP_PATH, so the bundled Qt5/CEF win over any
                     ;; store library of the same soname.  NSS keeps its libs
                     ;; under lib/nss.
                     (libdirs
                      (let loop ((dirs '()) (todo inputs))
                        (if (null? todo)
                            (reverse dirs)
                            (let* ((prefix (cdr (car todo)))
                                   (lib (string-append prefix "/lib"))
                                   (nss (string-append prefix "/lib/nss")))
                              (loop (append (if (file-exists? lib) (list lib) '())
                                            (if (file-exists? nss) (list nss) '())
                                            dirs)
                                    (cdr todo)))))))
                (mkdir-p (dirname app))
                ;; The app tree is 1.2 GB; renaming it into $out avoids copying
                ;; it.  Fall back to a copy if the build directory happens to
                ;; live on another filesystem.  (false-if-exception is a macro
                ;; with a narrow pattern, so spell the catch out.)
                (catch 'system-error
                  (lambda ()
                    (rename-file "opt/onlyoffice/desktopeditors" app))
                  (lambda args
                    (copy-recursively "opt/onlyoffice/desktopeditors" app)))
                ;; Prebuilt ELFs point at /lib64/ld-linux-*.so.2, absent from
                ;; the store.  Do NOT touch their rpath: libcef/SwiftShader
                ;; segfault when repatched (same story as claude/antigravity).
                (for-each (lambda (exe)
                            (invoke "patchelf" "--set-interpreter" loader
                                    (string-append app "/" exe)))
                          '("DesktopEditors" "editors_helper"
                            "chrome-sandbox" "converter/x2t"))
                ;; System fonts.  CApplicationFonts::GetSetupFontFiles walks
                ;; /usr/share/fonts, /usr/share/X11/fonts, /run/host/fonts,
                ;; /usr/local/share/fonts and $CUSTOM_FONTS_PATH -- all
                ;; absent on Guix -- and never asks fontconfig.  The desktop
                ;; app additionally registers "./fonts" relative to the
                ;; executable, so anything dropped into the tarball's own
                ;; fonts/ tree is picked up, and that works for both GUI and
                ;; shell launches with no env var.
                ;;
                ;; The files MUST be real copies.  Guix profiles are built
                ;; from symlinks and NSDirectory::GetFiles2 only acts on
                ;; DT_REG/DT_DIR (plus a DT_UNKNOWN stat fallback), so a
                ;; DT_LNK entry is dropped without a word -- which is why
                ;; pointing CUSTOM_FONTS_PATH at a profile yields nothing.
                ;; Copying is the only option: store and $HOME sit on
                ;; separate filesystems here, so hardlinks fail too.
                (let ((fontdir (string-append app "/fonts/microsoft")))
                  (mkdir-p fontdir)
                  (copy-recursively
                   (string-append
                    (assoc-ref inputs "font-microsoft-times-new-roman")
                    "/share/fonts")
                   fontdir
                   #:follow-symlinks? #t
                   #:log #f))
                (mkdir-p bin)
                (install-file "usr/bin/onlyoffice-desktopeditors" bin)
                (let ((launcher (string-append bin "/onlyoffice-desktopeditors")))
                  ;; The stock launcher hardcodes /opt/onlyoffice/desktopeditors
                  ;; (both for the app dir and the --new-document-templates
                  ;; source); repoint it at the store and give it a store sh.
                  (substitute* launcher
                    (("#!/bin/sh")
                     (string-append "#!" #$(file-append bash "/bin/sh")))
                    (("/opt/onlyoffice/desktopeditors") app))
                  (chmod launcher #o755)
                  (wrap-program launcher
                    #:sh #$(file-append bash "/bin/sh")
                    `("LD_LIBRARY_PATH" ":" prefix ,libdirs)))
                (install-file "usr/share/applications/onlyoffice-desktopeditors.desktop"
                              (string-append share "/applications"))
                (substitute* (string-append
                              share
                              "/applications/onlyoffice-desktopeditors.desktop")
                  (("Exec=/usr/bin/onlyoffice-desktopeditors")
                   (string-append "Exec=" bin "/onlyoffice-desktopeditors")))
                (copy-recursively "usr/share/icons" (string-append share "/icons"))
                (mkdir-p doc)
                (for-each (lambda (f)
                            (install-file (string-append "usr/share/licenses/"
                                                         "onlyoffice-desktopeditors/" f)
                                          doc))
                          '("LICENSE" "3DPARTYLICENSE"))
                (for-each (lambda (f)
                            (install-file (string-append "usr/share/doc/"
                                                         "onlyoffice-desktopeditors/" f)
                                          doc))
                          '("NEWS" "ChangeLog"))))))))
    (home-page "https://www.onlyoffice.com")
    (synopsis "Office suite for documents, spreadsheets, and presentations")
    (description
     "A full-featured office suite that opens, edits and saves text documents,
spreadsheets, presentations, PDFs and forms in all common formats, including
the OOXML (DOCX, XLSX, PPTX) and OpenDocument families.  The desktop editors
run fully offline, bundle a document converter, and are built on Qt5 and CEF.")
    (license license:agpl3)))
