# faron

Мой личный Guix-канал с определениями пакетов и собственными программами.

## Подключение

Канал подключён в `~/.config/guix/channels.scm` (и в `/root/.config/guix/channels.scm`).
Обновление:

```bash
sudo guix pull --disable-authentication
```

## Структура

```
faron/
  .guix-channel          # метаданные канала
  faron/packages/        # определения пакетов (один файл — один модуль)
  faron/src/             # исходники собственных программ
```

## Добавление пакета

1. Создай `faron/packages/<имя>.scm` с модулем `(faron packages <имя>)`.
2. Закоммить:
   ```bash
   cd /home/faron/guix-channels/faron
   git add -A && git commit -m "add <имя>"
   ```
3. Обнови канал и собери:
   ```bash
   sudo guix pull --disable-authentication
   guix build <имя>
   ```

## Установка

```bash
guix install <имя>
```

Для использования в system/home-конфиге добавь `(faron packages <имя>)`
в `use-modules` и ссылайся на пакет по имени.