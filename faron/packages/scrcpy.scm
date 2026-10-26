;;; scrcpy для канала faron.
;;; Положи файл как faron/packages/scrcpy.scm (имя модуля подправь под
;;; структуру канала, если она другая).

(define-module (faron packages scrcpy)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system meson)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages android)
  #:use-module (gnu packages base)
  #:use-module (gnu packages libusb)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages sdl)
  #:use-module (gnu packages video)
  #:use-module (gnu packages xorg)
  #:use-module (gnu packages xdisorg)
  #:use-module (gnu packages bash))

;; Android-часть (scrcpy-server) в Guix не собирается: нужен gradle и Android
;; SDK, поэтому берём официальный готовый jar из релиза.
(define scrcpy-server
  (origin
    (method url-fetch)
    (uri "https://github.com/Genymobile/scrcpy/releases/download/v5.0.1/scrcpy-server-v5.0.1")
    (file-name "scrcpy-server-5.0.1")
    (sha256
     (base32 "0dn57gjn5dizpzbrgf31g969ka9bi0h12d6zx4gj3m8ik3vvckkn"))))

(define-public scrcpy
  (package
    (name "scrcpy")
    (version "5.0.1")
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
              ;; scrcpy ищет adb в PATH или в переменной ADB.
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
