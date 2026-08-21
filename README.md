# faron — локальный канал Guix

Здесь лежат определения пакетов для твоих собственных программ.
Канал подключён в `/root/.config/guix/channels.scm` (и в `~/.config/guix/channels.scm`)
и обновляется через `sudo guix pull --disable-authentication`.

## Как добавить новый пакет

1. Создай файл `faron/packages/<имя>.scm` с модулем `(faron packages <имя>)`.

   ```scheme
   (define-module (faron packages myprog)
     #:use-module (guix packages)
     #:use-module (guix build-system copy)   ; или go / gnu / python ...
     #:use-module ((guix licenses) #:prefix license:)
     #:export (myprog))

   (define-public myprog
     (package
       (name "myprog")
       (version "0.1.0")
       (source (local-file "/home/faron/projects/myprog"
                           "myprog-src" #:recursive? #t
                           #:select? (git-predicate "/home/faron/projects/myprog")))
       (build-system copy-build-system)
       (arguments
        (list #:install-plan ''(("myprog" "bin/"))))
       (home-page "https://example.com")
       (synopsis "...")
       (description "...")
       (license license:gpl3)))
   ```

2. Закоммить изменения:
   ```
   cd /home/faron/guix-channels/faron && git add -A && git commit -m "add myprog"
   ```

3. Обнови канал и собери:
   ```
   sudo guix pull --disable-authentication
   guix build myprog
   ```

4. Чтобы использовать в системном `config.scm`, добавь в `use-modules`:
   ```
   (faron packages myprog)
   ```
   и ссылайся на пакет по имени `myprog` (или `#$(file-append myprog "/bin/myprog")`
   внутри gexp для сервисов).

## Структура

```
faron/
  .guix-channel
  faron/packages/<имя>.scm
```
