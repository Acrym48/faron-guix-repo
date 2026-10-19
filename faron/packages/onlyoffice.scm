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
  #:use-module (gnu packages fonts)
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
  #:use-module (faron packages fonts)
  #:export (onlyoffice-desktopeditors))

(define (aarch64-build?)
  (string-prefix? "aarch64"
                  (or (%current-target-system) (%current-system))))

;; The web UI is styled for Windows: every theme sets
;; --font-family-base to "Segoe UI", which does not exist on Linux, so the
;; whole interface falls back to Arial/Helvetica/sans-serif.  Point it at a
;; font that is actually installed instead.  DejaVu Sans is the generic
;; sans-serif of every Guix system (font-dejavu), and it is what the UI
;; ends up rendering with today anyway -- this just makes it explicit.
(define %onlyoffice-ui-font "DejaVu Sans")

;; Base font size of the web UI, in CSS pixels.
(define %onlyoffice-ui-font-size 12)

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
    (native-inputs (list patchelf sed xz))
    (inputs
     (list bash
           glibc
           (list gcc-14 "lib")
           adwaita-icon-theme
           alsa-lib
           at-spi2-core
           cups
           dbus
           expat
           font-dejavu
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
                ;; DejaVu Sans for the document canvas as well: the canvas uses
                ;; the app's own font list (CApplicationFonts), which walks the
                ;; bundled fonts/ tree, not fontconfig.
                (let ((dejavu (string-append
                               (assoc-ref inputs "font-dejavu")
                               "/share/fonts/truetype"))
                      (fontdir (string-append app "/fonts/dejavu")))
                  (mkdir-p fontdir)
                  (for-each
                   (lambda (f)
                     (install-file (string-append dejavu "/" f) fontdir))
                   '("DejaVuSans.ttf"
                     "DejaVuSans-Bold.ttf"
                     "DejaVuSans-Oblique.ttf"
                     "DejaVuSans-BoldOblique.ttf"
                     "DejaVuSansMono.ttf"
                     "DejaVuSansMono-Bold.ttf"
                     "DejaVuSansMono-Oblique.ttf"
                     "DejaVuSansMono-BoldOblique.ttf")))
                ;; Fontconfig for the embedded Chromium.  The app's fontconfig
                ;; has no main fonts.conf (Guix ships fontconfig-minimal), so
                ;; Chromium falls back to its own built-in configuration, which
                ;; knows nothing about the store.  What it does include is the
                ;; user's ~/.config/fontconfig/fonts.conf, i.e. the home
                ;; profile -- and nothing else.  Without DejaVu there, the
                ;; generic sans-serif resolves to Times New Roman and the whole
                ;; interface renders serif.  Point FONTCONFIG_FILE (set in the
                ;; wrapper below) at a config that adds the DejaVu directory
                ;; while keeping the user's own settings.
                (let ((fc (string-append out "/etc/fonts.conf")))
                  (mkdir-p (dirname fc))
                  (call-with-output-file fc
                    (lambda (port)
                      (display "<?xml version=\"1.0\"?>\n\
<!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">\n\
<fontconfig>\n\
  <include ignore_missing=\"yes\" prefix=\"xdg\">fontconfig/fonts.conf</include>\n\
  <dir>" port)
                      (display (string-append
                                (assoc-ref inputs "font-dejavu")
                                "/share/fonts") port)
                      (display "</dir>\n\
  <cachedir prefix=\"xdg\">fontconfig</cachedir>\n\
</fontconfig>\n" port))))
                ;; Interface font.  The web UI is styled for Windows: every
                ;; theme sets --font-family-base to "Segoe UI", which does
                ;; not exist on Linux.  Worse, the rules that use it are
                ;; written as
                ;;   font-family:var(--font-family-base-custom,
                ;;                   var(--font-family-base)),Arial,...
                ;; and where the variable is not in scope the whole
                ;; declaration is invalid at computed-value time, so the
                ;; browser falls back to its default (a serif).  Replace
                ;; the declarations themselves rather than just the
                ;; variable, so they cannot become invalid.
                ;;
                ;; The stylesheets are minified into single huge lines, so
                ;; substitute* is unusable here (it replaces whole lines) --
                ;; use sed.  Each value ends at the next ';' or '}' and none
                ;; of them contain either.
                (for-each
                 (lambda (rel)
                   (let ((f (string-append app "/" rel)))
                     (when (file-exists? f)
                       (invoke "sed" "-i"
                                "-e"
                                (string-append
                                 "s|--font-family-base:[^;}]*|"
                                 "--font-family-base:\""
                                 #$%onlyoffice-ui-font "\"|g")
                                "-e"
                                (string-append
                                 "s|font-family:var(--font-family-base-custom[^;}]*|"
                                 "font-family:\""
                                 #$%onlyoffice-ui-font "\"|g")
                                "-e"
                                (string-append
                                 "s|font-family:Arial,Helvetica,"
                                 "\"Helvetica Neue\",sans-serif|"
                                 "font-family:\""
                                 #$%onlyoffice-ui-font "\"|g")
                                ;; The body rule carries the base size of
                                ;; the whole interface.  Mark it first: the
                                ;; font-family substitution above rewrites
                                ;; the very same rule.
                                "-e"
                                (string-append
                                 "s|body{font-family:\\([^;}]*\\);"
                                 "font-size:11px|"
                                 "body{font-family:\\1;font-size:"
                                 (number->string #$%onlyoffice-ui-font-size)
                                 "px|g")
                                ;; Theme base sizes, one pixel up.  The
                                ;; markers keep the two substitutions from
                                ;; eating each other.
                                "-e" "s|--font-size-base:11px|--font-size-base:@BS@|g"
                                "-e" (string-append
                                      "s|--font-size-base:12px|--font-size-base:"
                                      (number->string
                                       (1+ #$%onlyoffice-ui-font-size))
                                      "px|g")
                                "-e" (string-append "s|@BS@|"
                                      (number->string
                                       #$%onlyoffice-ui-font-size)
                                      "px|g")
                                f))))
                 ;; The list of files is spelled out here rather than in a
                 ;; module-level constant: inside a gexp, #$ splices a list
                 ;; into the enclosing form instead of passing it as one
                 ;; argument, so a list cannot be handed over that way.
                 '("index.html"
                   "addon.html"
                   "editors/web-apps/apps/documenteditor/main/resources/css/app.css"
                   "editors/web-apps/apps/documenteditor/forms/resources/css/app-all.css"
                   "editors/web-apps/apps/spreadsheeteditor/main/resources/css/app.css"
                   "editors/web-apps/apps/presentationeditor/main/resources/css/app.css"
                   "editors/web-apps/apps/pdfeditor/main/resources/css/app.css"
                   "editors/web-apps/apps/visioeditor/main/resources/css/app.css"))
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
                    `("LD_LIBRARY_PATH" ":" prefix ,libdirs)
                    ;; See the install phase: without this the embedded
                    ;; Chromium ends up with a font set that contains neither
                    ;; DejaVu nor any generic sans-serif, and renders the
                    ;; whole interface in Times New Roman.  The '=' action
                    ;; replaces the value; it has to be the symbol, not the
                    ;; string.
                    (list "FONTCONFIG_FILE" ":" '=
                          (list (string-append out "/etc/fonts.conf")))
                    ;; GTK3 looks for the icon theme under $HOME/.icons and
                    ;; XDG_DATA_DIRS/icons only, so a theme that merely sits
                    ;; in the store closure stays invisible.  Put its share/
                    ;; on the path.  (Guix ships no Adwaita *widget* theme
                    ;; at all, so the window frame still uses GTK's Default;
                    ;; this is about the icons in the toolbars and dialogs.)
                    `("XDG_DATA_DIRS" ":"
                      suffix
                      ,(list (string-append
                              (assoc-ref inputs "adwaita-icon-theme")
                              "/share")))))
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
