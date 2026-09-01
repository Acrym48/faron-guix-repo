(define-module (faron packages polymc)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix build-system cmake)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages audio)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages cpp)
  #:use-module (gnu packages gl)
  #:use-module (gnu packages gnome)
  #:use-module (gnu packages java)
  #:use-module (gnu packages kde-frameworks)
  #:use-module (gnu packages man)
  #:use-module (gnu packages qt)
  #:export (polymc))

(define-public polymc
  (package
    (name "polymc")
    (version "7.1")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/PolyMC/PolyMC")
             (commit "9b01b80bfd43768c478ad6a0bdf532bc51635973")
             ;; Сабмодули (libnbtplusplus, quazip, tomlplusplus,
             ;; ghc-filesystem) нужны для сборки.
             (recursive? #t)))
       (file-name (git-file-name name version))
       (sha256
        (base32 "05zr0ib3a78yrhh2wnc3adidw17za89fd56c0pyq8gkrf6kakak8"))))
    (build-system cmake-build-system)
    (arguments
     (list
      #:modules '((guix build cmake-build-system)
                  (guix build qt-utils)
                  (guix build utils))
      #:imported-modules `(,@%cmake-build-system-modules
                           (guix build qt-utils))
      #:configure-flags
      #~(list "-DLauncher_APP_BINARY_NAME=polymc"
              "-DLauncher_QT_VERSION_MAJOR=6")
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'qt-wrap
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (wrap-all-qt-programs #:inputs inputs
                                    #:outputs outputs
                                    #:qtbase #$qtbase))))))
    (native-inputs
     (list extra-cmake-modules scdoc (list openjdk21 "jdk")))
    (inputs
     (list qtbase
           qt5compat
           qtsvg
           qtimageformats
           qtcharts
           qtwayland
           quazip
           tomlplusplus
           zlib
           glfw
           openal
           mesa
           hicolor-icon-theme
           openjdk21))
    (home-page "https://github.com/PolyMC/PolyMC")
    (synopsis "Free, open source launcher for Minecraft")
    (description
     "PolyMC is a custom launcher for Minecraft that allows you to easily
manage multiple installations of Minecraft at once.  It provides a rich
user interface for managing instances, mods, resource packs and more.")
    (license license:gpl3)))
