# AGENTS.md — faron-guix-repo

Guix-канал `faron`: пакеты, которых нет в официальном GNU Guix, + личные
проекты. Код канала по умолчанию под GPL-3.0-or-later (см. `LICENSE`).

## Структура

- `faron/packages/*.scm` — пакеты, по одному тематическому файлу:
  `ai.scm` (AI-агенты, prebuilt), `binaries.scm` (prebuilt),
  `glow.scm` (Go из исходников + свой dep-стек), `go.scm` (Go из исходников),
  `java-runtimes.scm` (trivial-бандл), `polymc.scm` (CMake/Qt),
  `driftwm.scm` (Rust офлайн через вендор).
- `README.md` — таблица пакетов + установка. Обновлять при добавлении пакета.
- `test/` — пустая, пока не используется.
- `.guix-channel` — имя канала (`faron`), не трогать.

Модуль = `(faron packages <файл>)`, каждый пакет — `define-public` + `#:export`.
Исходники личных проектов в канал НЕ бандлить — тянуть из внешних git-репо
(см. `tg-ws-proxy-go: fetch from external git repo instead of bundling
in-tree`). Никакого dev-тулинга (flake/shell/guix.scm) в канале нет и не надо.

## Локальная сборка и установка

Канал у пользователей подключён через `~/.config/guix/channels.scm` + `guix pull`.
Для проверки без pull — из корня репозитория:

```bash
GUIX_PACKAGE_PATH=. guix build <pkg>
GUIX_PACKAGE_PATH=. guix lint <pkg>
GUIX_PACKAGE_PATH=. guix refresh <pkg>   # проверить, есть ли апстрим-обновления
```

Использование пакета в system/home-конфиге — через `use-modules`, см. пример
в `README.md`.

## Как добавить пакет

1. Выбери файл: пакет своей тематики — новый `<тема>.scm` с модулем
   `(faron packages <тема>)`; родственный существующим — допиши в тот же
   файл и добавь имя в `#:export`.
2. Определи тип сборки и скопируй ближайший прецедент (раздел ниже).
3. Релизы/артефакты ищи на GitHub Releases апстрима (удобно через API:
   `https://api.github.com/repos/<owner>/<repo>/releases/tags/<tag>` —
   там же `digest: sha256:<hex>` для каждого ассета).
4. Добавь строку в таблицу `README.md`.
5. Проверь сборку и линтер (раздел «Проверка»).
6. Не коммить без прямой просьбы.

## Паттерны сборки

### Prebuilt-бинарь + patchelf (`ai.scm`, `binaries.scm`)

Для закрытых/тяжёлых бинарей с GitHub Releases. Обязательно оба
архитектурных артефакта через предикат:

```scheme
(define (aarch64-build?)
  (string-prefix? "aarch64"
                  (or (%current-target-system) (%current-system))))
```

- `gnu-build-system`, фазы `configure/build/check/validate-runpath/strip`
  удалить, `install` заменить.
- `patchelf --set-interpreter` на glibc из стора
  (`/lib/ld-linux-x86-64.so.2` vs `/lib/ld-linux-aarch64.so.1`).
- Рантайм-библиотеки (`libgcc_s`, `libstdc++`): положить `.so` в `$out/lib`
  и выставить `LD_LIBRARY_PATH` через `wrap-program`
  (`#:sh #$(file-append bash "/bin/sh")`, `bash` — во `inputs`).
- НЕ ставить `--set-rpath` на эти бинари — ломал claude/antigravity (segfault,
  см. историю `fix claude/antigravity segfault: drop patchelf --set-rpath`).
- Полностью статическим бинарям (`codebase-memory-mcp`) patchelf не нужен.
- Бандлы со своим рантаймом: патчить интерпретатор вложенного бинаря, точку
  входа оборачивать скриптом (Node у `qwen-code`, SEA-бандл у `kimi-code`).
- Скачивание одиночного файла (не тарболла): обязателен `file-name`
  (`claude-code`, `kimi-code`), иначе кэш загрузок Guix коллизирует.
- В фазах: пути к инпутам — через `(assoc-ref %build-inputs "<имя>")`
  или `(search-input-file %build-inputs "lib/<файл>.so")`.

### Go из исходников (`go.scm`, `glow.scm`)

- `go-build-system` с `#:import-path` = **module path апстрима**, а не имя
  пакета: иначе `go install` не резолвит internal-пакеты
  (дважды чинилось на `anilib-cli`/`tg-ws-proxy-go`).
- `#:install-source? #f` для конечных бинарей.
- Кастомная точка входа — фазой `replace 'build` с `go install <import>/...`
  (см. `tg-ws-proxy-go`: `.../cmd/tg-ws-proxy`).
- Go-зависимости, которых нет в Guix, пакетировать рядом в том же файле
  (`go-charm-land-*`, `go-github-com-*` в `glow.scm`).
- Рантайм-зависимости бинаря (mpv у `anilib-cli`) — `wrap-program` с `PATH`.
- Если тестов нет: `#:tests? #f`.
- Хэш в `base32` — одной строкой без переносов (был фикс со strip newlines).

### CMake/Qt (`polymc.scm`)

- `cmake-build-system`, сабмодули апстрима — `(recursive? #t)` в `git-reference`.
- `wrap-all-qt-programs` в фазе после `install` (+ `qtwayland`, иначе нет
  wayland-плагина).
- Рантайм-пути для дочерних процессов — через `wrap-program`: `PATH`,
  кастомные переменные (`POLYMC_JAVA_PATHS`), `LD_LIBRARY_PATH` под dlopen
  (без xorg-библиотек в `LD_LIBRARY_PATH` дочерний Minecraft падал
  в `glfwInit`, см. историю).

### Rust офлайн через вендорный тарболл (`driftwm.scm`)

- Если апстрим публикует `*-vendor.tar.xz` (`cargo vendor --locked`):
  `gnu-build-system` вместо возни с `cargo-build-system` и сотнями крейтов.
  Вендор — отдельным `origin`-define'ом, НЕ записью `("label" ,origin)`
  в `native-inputs`: в new-style inputs двухэлементный список читается как
  «пакет + outputs» и падает с `Wrong type to apply` (было на driftwm).
  В фазе ссылаться напрямую через `#$driftwm-vendor` — gexp сам положит
  origin в стор. Распаковка фазой `unpack-vendor` поверх исходников
  СТРОГО ПОСЛЕ `patch-generated-file-shebangs` (прямо перед `build`):
  patch-фазы переписывают shebang'и скриптов, а cargo сверяет sha256
  каждого файла вендора с `.cargo-checksum.json` — было падение
  `the listed checksum of .../vendor/... has changed`.
  (в тарболле нет top-level директории — распаковывать в корень исходников),
  далее `cargo build --offline --locked --release`.
- `CARGO_HOME` указывать на writable-дир в `TMPDIR`
  (`CARGO_NET_OFFLINE=true`), иначе cargo падает на homeless-shelter.
- Параллелизм: `--jobs=<parallel-job-count>`.
- Тесты, требующие GPU/железа/сторонних бинарей, — `#:tests? #f`.
- dlopen-зависимости (EGL/GBM/seat/udev) — `LD_LIBRARY_PATH` через
  `wrap-program`, как у prebuilt-бинарей.
- Версия исходников и вендора обязана совпадать (вендор привязан к
  `Cargo.lock` тега); держать обе в одном define (`%driftwm-version`).

### trivial-бандл (`java-runtimes.scm`)

- `trivial-build-system` для склейки нескольких store-пакетов
  (симлинки в `_jvm/<major>/`, версионированные лаунчеры в `bin/`).

## Версии и хэши

- Бамп: поднять `version`, обновить оба хэша (x86_64 + aarch64, где есть).
- Хэш тарболла: `guix download <url>` (выдаёт готовый base32).
- Хэш git-источника (`git-fetch`): склонировать и `guix hash -r <dir>`
  (это nar-хэш чекаута, не sha256 архива).
- Для релизных ассетов GitHub API отдаёт `digest: sha256:<hex>` —
  hex → nix-base32: скрипт `sha256-to-nix32.sh` (вне репозитория).
- git-источник всегда оборачивать в `origin` с `file-name` и `sha256`
  (был фикс `tg-ws-proxy: fix broken source`).
- Стиль сообщений из истории: `bump <pkg> <old> -> <new>`,
  `add <pkg> <ver>`, `<pkg>: <что и зачем>`.

## Проверка и отладка

```bash
# из корня репозитория:
GUIX_PACKAGE_PATH=. guix build <pkg>
GUIX_PACKAGE_PATH=. guix lint <pkg>
GUIX_PACKAGE_PATH=. guix build -K <pkg>          # оставить /tmp/guix-build-* при падении
GUIX_PACKAGE_PATH=. guix build --log-file <pkg>  # лог последней сборки
```

- Без `guix` под рукой — минимум проверить баланс скобок парсером
  (системный guile не умеет gexp-синтаксис `#~`, это нормально).
- `guix lint` в частности ругается на синопсис/описание не по гайдлайнам:
  synopsis ≤ 80 символов, description не начинается с имени пакета.
- Частый провал — несбалансированные скобки в `#:phases` (было на polymc);
  второй частый — забытый `#:use-module` под новый input
  (было: `unzip` без `(gnu packages compression)`).

## Где искать символы Guix-модулей

Какой пакет в каком `(gnu packages ...)` лежит — не очевидно. Проверенные
соответствия (сверены с исходниками Guix master):

| Модуль | Символы |
|---|---|
| `admin` | `libseat`, `seatd` |
| `bash` | `bash` |
| `base` | `glibc` |
| `compression` | `unzip`, `zlib` |
| `elf` | `patchelf` |
| `freedesktop` | `wayland`, `wayland-protocols`, `libinput`, `libinput-minimal` |
| `gcc` | `gcc-14` (рантайм-библиотеки — `(list gcc-14 "lib")`) |
| `gl` | `mesa`, `libglvnd` |
| `golang`, `golang-build`, `golang-check`, `golang-web`, `golang-xyz` | Go-зависимости |
| `java` | `openjdk17`, `openjdk21`, `openjdk25` |
| `linux` | `eudev` (libudev) |
| `pkg-config` | `pkg-config` (макрос, резолвится в pkgconf) |
| `qt` | `qtbase`, `qtwayland`, `qtsvg`, … |
| `rust` | `rust` (+ `(list rust "cargo")` для cargo) |
| `video` | `mpv` |
| `window-management` | `libdisplay-info` (там же апстримный `niri` — образец `cargo-build-system` для композитора) |
| `xdisorg` | `libdrm`, `libxkbcommon`, `pixman` |
| `xorg` | `libx11`, `libxcursor`, `libxrandr`, `libxi`, `libxcb` |

Источники для сверки:

- Зеркало Guix на Codeberg (cgit Savannah иногда висит):
  `https://codeberg.org/guix/guix/raw/branch/master/gnu/packages/<модуль>.scm`
  + локальный grep по `define-public`.
- `cargo-build-system` апстрима и `(cargo-inputs '<pkg>)` работают только
  для пакетов из самого Guix — для канала этот путь не использовать
  (потому `driftwm` собран через вендор, а не через крейты).

## Стиль кода

- `inputs`/`native-inputs` — new-style списки `(list pkg (list pkg "out") ...)`
  (пример выбора output: `(list openjdk21 "jdk")`, `(list gcc-14 "lib")`,
  `(list rust "cargo")`); старый крой с backquote/`assoc-ref` не использовать.
- Версионированные/архитектурные ветвления — через предикат в `source`,
  а не отдельными пакетами.
- gexp: `#$output`, `#$version`, `#$(file-append bash "/bin/sh")` внутри
  `#~(modify-phases %standard-phases ...)`; в лямбдах фаз —
  `(assoc-ref %build-inputs "<имя>")`, `search-input-file`, `wrap-program`,
  `substitute*`, `install-file`, `copy-recursively`, `find-files`.
- Лицензии — с префиксом `license:`: `license:expat`, `license:gpl3`,
  `license:asl2.0`; проприетарщине — `(license:non-copyleft "<url>")`.
