;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2026 faron
;;;
;;; This file is part of the faron channel.
;;;
;;; This program is free software: you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License as published by
;;; the Free Software Foundation, either version 3 of the License, or
;;; (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

(define-module (faron services tg-ws-proxy)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (gnu home services shepherd)
  #:use-module (gnu system accounts)
  #:use-module (gnu system shadow)
  #:use-module (gnu packages admin)
  #:use-module (srfi srfi-1)
  #:use-module (faron packages go)
  #:export (tg-ws-proxy-configuration
            tg-ws-proxy-configuration?
            tg-ws-proxy-service-type
            tg-ws-proxy-home-service-type))

;;; Commentary:
;;;
;;; Shepherd services for tg-ws-proxy, a local MTProto WebSocket proxy
;;; bridging Telegram Desktop traffic.  One configuration record feeds two
;;; service types:
;;;
;;;   - tg-ws-proxy-service-type for system.scm: runs the proxy as a
;;;     Shepherd system service under a dedicated unprivileged user
;;;     (created via account-service-type).
;;;   - tg-ws-proxy-home-service-type for home.scm: runs it as the home
;;;     user via home-shepherd (the user/group fields are ignored there).
;;;
;;; The proxy secret needs care: a plain `secret' string ends up in the
;;; store and on the daemon command line (visible via `ps'), so prefer
;;; `secret-file' — a path read at service start into TG_WS_PROXY_SECRET
;;; and never baked into the store.
;;;
;;; Code:

(define-record-type* <tg-ws-proxy-configuration>
  tg-ws-proxy-configuration make-tg-ws-proxy-configuration
  tg-ws-proxy-configuration?
  (package                tg-ws-proxy-configuration-package                (default tg-ws-proxy-go))
  (host                   tg-ws-proxy-configuration-host                   (default "127.0.0.1"))
  (port                   tg-ws-proxy-configuration-port                   (default 1443))
  (secret                 tg-ws-proxy-configuration-secret                 (default #f))
  (secret-file            tg-ws-proxy-configuration-secret-file            (default #f))
  (verbose?               tg-ws-proxy-configuration-verbose?               (default #f))
  (log-file               tg-ws-proxy-configuration-log-file               (default #f))
  (log-max-mb             tg-ws-proxy-configuration-log-max-mb             (default 5))
  (log-backups            tg-ws-proxy-configuration-log-backups            (default 1))
  (buffer-kb              tg-ws-proxy-configuration-buffer-kb              (default 256))
  (pool-size              tg-ws-proxy-configuration-pool-size              (default 4))
  (fallback               tg-ws-proxy-configuration-fallback               (default #f))
  (no-cfproxy?            tg-ws-proxy-configuration-no-cfproxy?            (default #f))
  (cfproxy-domains        tg-ws-proxy-configuration-cfproxy-domains        (default '()))
  (cfproxy-worker-domains tg-ws-proxy-configuration-cfproxy-worker-domains (default '()))
  (dc-ips                 tg-ws-proxy-configuration-dc-ips                 (default '()))
  (fake-tls-domain        tg-ws-proxy-configuration-fake-tls-domain        (default #f))
  (force-test-dc?         tg-ws-proxy-configuration-force-test-dc?         (default #f))
  (proxy-protocol?        tg-ws-proxy-configuration-proxy-protocol?        (default #f))
  (auto-start?            tg-ws-proxy-configuration-auto-start?            (default #t))
  (user                   tg-ws-proxy-configuration-user                   (default "tg-ws-proxy"))
  (group                  tg-ws-proxy-configuration-group                  (default "tg-ws-proxy"))
  (extra-arguments        tg-ws-proxy-configuration-extra-arguments        (default '())))

(define (fallback->string fallback)
  "Map a `fallback' symbol to the --fallback flag value."
  (cond ((eq? fallback 'cf) "cf")
        ((eq? fallback 'cf-worker) "cf_worker")
        ((eq? fallback 'tcp) "tcp")
        ((eq? fallback 'off) "off")
        (else (error "unknown tg-ws-proxy fallback (cf, cf-worker, tcp, off):"
                     fallback))))

(define (tg-ws-proxy-arguments config)
  "Return the tg-ws-proxy command-line arguments (a list of strings)."
  (match-record config <tg-ws-proxy-configuration>
    (host port secret secret-file verbose? log-file log-max-mb log-backups
     buffer-kb pool-size fallback no-cfproxy? cfproxy-domains
     cfproxy-worker-domains dc-ips fake-tls-domain force-test-dc?
     proxy-protocol? extra-arguments)
    (append
     (list "--host" host
           "--port" (number->string port)
           "--buf-kb" (number->string buffer-kb)
           "--pool-size" (number->string pool-size)
           "--log-max-mb" (number->string log-max-mb)
           "--log-backups" (number->string log-backups))
     ;; secret-file wins: it is read at start time and never lands
     ;; in the store, unlike --secret.
     (if (and secret (not secret-file))
         (list "--secret" secret)
         '())
     (if verbose? '("-v") '())
     (if log-file (list "--log-file" log-file) '())
     (if fallback (list "--fallback" (fallback->string fallback)) '())
     (if no-cfproxy? '("--no-cfproxy") '())
     (append-map (lambda (domain) (list "--cfproxy-domain" domain))
                 cfproxy-domains)
     (append-map (lambda (domain) (list "--cfproxy-worker-domain" domain))
                 cfproxy-worker-domains)
     (append-map (lambda (mapping) (list "--dc-ip" mapping)) dc-ips)
     (if fake-tls-domain (list "--fake-tls-domain" fake-tls-domain) '())
     (if force-test-dc? '("--force-test-dc") '())
     (if proxy-protocol? '("--proxy-protocol") '())
     extra-arguments)))

(define (tg-ws-proxy-secret-wrapper binary secret-file arguments)
  "Return a script that reads the proxy secret from SECRET-FILE into
TG_WS_PROXY_SECRET and execs BINARY with ARGUMENTS."
  (program-file "tg-ws-proxy-run"
    #~(begin
        (use-modules (ice-9 rdelim) (srfi srfi-13))
        (let ((secret (call-with-input-file #$secret-file read-string)))
          (setenv "TG_WS_PROXY_SECRET" (string-trim-both secret))
          (apply execl #$binary #$binary (list #$@arguments))))))

(define (tg-ws-proxy-shepherd-service config user group)
  "Return a <shepherd-service> running tg-ws-proxy per CONFIG.
USER and GROUP are strings for the system service, #f for a home service."
  (match-record config <tg-ws-proxy-configuration>
    (package secret-file auto-start?)
    (let* ((binary (file-append package "/bin/tg-ws-proxy"))
           (arguments (tg-ws-proxy-arguments config))
           (command (if secret-file
                        (list (tg-ws-proxy-secret-wrapper
                               binary secret-file arguments))
                        (cons binary arguments))))
      (shepherd-service
       (provision '(tg-ws-proxy))
       (documentation "Local MTProto WebSocket proxy for Telegram Desktop.")
       (requirement '())
       (auto-start? auto-start?)
       (respawn? #t)
       (start #~(make-forkexec-constructor
                 (list #$@command)
                 #$@(if user
                        `(#:user ,user #:group ,group)
                        '())))
       (stop #~(make-kill-destructor))))))

(define (tg-ws-proxy-accounts config)
  "Return the system user and group to run tg-ws-proxy as."
  (match-record config <tg-ws-proxy-configuration> (user group)
    (list (user-group (name group) (system? #t))
          (user-account
           (name user)
           (group group)
           (system? #t)
           (comment "tg-ws-proxy service user")
           (home-directory "/var/empty")
           (shell (file-append shadow "/sbin/nologin"))))))

(define tg-ws-proxy-service-type
  (service-type
   (name 'tg-ws-proxy)
   (extensions
    (list (service-extension shepherd-root-service-type
                             (lambda (config)
                               (list (tg-ws-proxy-shepherd-service
                                      config
                                      (tg-ws-proxy-configuration-user config)
                                      (tg-ws-proxy-configuration-group config)))))
          (service-extension account-service-type
                             tg-ws-proxy-accounts)))
   (default-value (tg-ws-proxy-configuration))
   (description "Run @command{tg-ws-proxy}, a local MTProto WebSocket proxy
bridging Telegram Desktop traffic, as a Shepherd system service under a
dedicated unprivileged user.")))

(define tg-ws-proxy-home-service-type
  (service-type
   (name 'tg-ws-proxy-home)
   (extensions
    (list (service-extension home-shepherd-service-type
                             (lambda (config)
                               (list (tg-ws-proxy-shepherd-service
                                      config #f #f))))))
   (default-value (tg-ws-proxy-configuration))
   (description "Run @command{tg-ws-proxy}, a local MTProto WebSocket proxy
bridging Telegram Desktop traffic, as a Shepherd home service under the
home user.")))

;;; tg-ws-proxy.scm ends here
