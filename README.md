# faron — мой канал пакетов Guix

Локальный Guix-канал с определениями пакетов и собственными программами.
Канал подключён в `~/.config/guix/channels.scm` (и в `/root/.config/guix/channels.scm`)
и обновляется через `sudo guix pull --disable-authentication`.

## Доступные пакеты

| Пакет | Что это |
|-------|---------|
| `polymc` | Лаунчер Minecraft (PolyMC 7.1) |
| `opencode` | AI-агент для терминала (prebuilt бинарник) |
| `yazi` | Терминальный файловый менеджер (prebuilt бинарник) |
| `tg-ws-proxy-go` | Локальный MTProto WebSocket прокси для Telegram |

Пакеты собраны из исходников (`faron/packages/*.scm`) с использованием
системных Guix-библиотек. Prebuilt-бинарники (`opencode`, `yazi`) патчатся
`patchelf` под интерпретатор glibc из Guix store.

## Как добавить новый пакет

1. Создай файл `faron/packages/<имя>.scm` с модулем `(faron packages <имя>)`:

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

   Существует несколько build-system на выбор: `copy`, `go`, `gnu` (для
   cmake/autotools), `python`, и т.д. Для Qt-приложений добавь фазу обёртки
   `wrap-all-qt-programs` из `(guix build qt-utils)` и подключи `qtwayland`,
   если приложение должно запускаться под Wayland.

2. Закоммить изменения:
   ```
   cd /home/faron/guix-channels/faron && git add -A && git commit -m "add myprog"
   ```

3. Обнови канал и собери:
   ```
   sudo guix pull --disable-authentication
   guix build myprog
   ```

4. Чтобы использовать пакет в системном `config.scm` или `home-config.scm`,
   добавь в `use-modules`:
   ```
   (faron packages myprog)
   ```
   и ссылайся на пакет по имени `myprog` (или `#$(file-append myprog "/bin/myprog")`
   внутри gexp для сервисов). В home-конфиге (`~/guix-home-config.scm`) это уже
   сделано для всех пакетов из канала.

## Структура

```
faron/
  .guix-channel
  faron/packages/<имя>.scm
```