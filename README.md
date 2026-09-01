# faron

Мой личный Guix-канал: определения пакетов, которых нет в официальном Guix,
плюс собственные программы.

## Подключение

Канал уже подключён в `~/.config/guix/channels.scm` (и в
`/root/.config/guix/channels.scm`) и обновляется командой:

```bash
sudo guix pull --disable-authentication
```

## Пакеты

| Пакет | Что это |
|-------|---------|
| `polymc` | Лаунчер Minecraft (PolyMC), собирается из исходников с Qt6 |
| `opencode` | AI-агент для терминала (prebuilt бинарник из GitHub Releases) |
| `yazi` | Терминальный файловый менеджер (prebuilt бинарник из GitHub Releases) |
| `tg-ws-proxy-go` | Локальный MTProto WebSocket прокси для Telegram (собирается из исходников) |

Проекты, собираемые из исходников, используют системные Guix-библиотеки.
Prebuilt-бинарники (`opencode`, `yazi`) патчатся `patchelf` под
интерпретатор glibc из Guix store.

## Структура канала

```
faron/
  .guix-channel          # метаданные канала
  faron/packages/        # определения пакетов
    <имя>.scm            # один файл — один модуль (faron packages <имя>)
  faron/src/             # исходники собственных программ
```

## Как добавить новый пакет

1. Создай файл `faron/packages/<имя>.scm` с модулем `(faron packages <имя>)`:

   ```scheme
   (define-module (faron packages myprog)
     #:use-module (guix packages)
     #:use-module (guix build-system copy)
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

   Build-system выбирается по типу проекта: `copy`, `go`, `gnu` (cmake,
   autotools), `python` и т.д. Для Qt-приложений добавь фазу обёртки
   `wrap-all-qt-programs` из `(guix build qt-utils)` и подключай `qtwayland`,
   если приложение должно работать под Wayland.

2. Закоммить изменение:

   ```bash
   cd /home/faron/guix-channels/faron
   git add -A && git commit -m "add myprog"
   ```

3. Обнови канал и собери пакет:

   ```bash
   sudo guix pull --disable-authentication
   guix build myprog
   ```

4. Использование:

   - установить в профиль: `guix install myprog`
   - в системном `config.scm` или `home-config.scm` добавь в `use-modules`
     `(faron packages myprog)` и ссылайся на пакет по имени `myprog` (или
     используй `#$(file-append myprog "/bin/myprog")` в gexp для сервисов).