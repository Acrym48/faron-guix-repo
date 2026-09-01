# faron

A Guix channel providing packages missing from the official GNU Guix, along
with personal projects.

## Packages

| Package | Description | Source |
|---------|-------------|-------|
| `polymc` | Open-source Minecraft launcher with instance management (Qt6 build) | [PolyMC/PolyMC](https://github.com/PolyMC/PolyMC) |
| `opencode` | Open-source AI coding agent for the terminal | [opencode.ai](https://opencode.ai) |
| `yazi` | Blazing-fast terminal file manager | [sxyazi/yazi](https://github.com/sxyazi/yazi) |
| `tg-ws-proxy-go` | Local MTProto WebSocket proxy for Telegram Desktop | in-tree ([`faron/src/tg-ws-proxy-go`](faron/src/tg-ws-proxy-go)) |

Packages built from source reuse the system Guix libraries. Prebuilt
binaries (`opencode`, `yazi`) are patched with `patchelf` to the glibc
interpreter from the Guix store.

## Installation

Add the channel to `~/.config/guix/channels.scm`:

```scheme
(cons (channel
        (name 'faron)
        (url "https://github.com/<you>/<repo>"))
      %default-channels)
```

Update the channel and build or install a package:

```bash
guix pull
guix install polymc
# or only build it without installing:
guix build polymc
```

## Using a package in a system / home config

Import the module in your `config.scm` or `home-config.scm` `use-modules`
and reference the package by name:

```scheme
(use-modules (faron packages polymc))

(home-environment
  (packages (list polymc)))
```

## License

Unless otherwise noted, the channel code is free software licensed under the
GPL-3.0-or-later license. See the `faron/src/tg-ws-proxy-go` directory for
the licensing of the bundled `tg-ws-proxy-go` project.