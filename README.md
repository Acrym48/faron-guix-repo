# faron

A Guix channel providing packages missing from the official GNU Guix, along
with personal projects.

## Packages

| Package | Description | Source |
|---------|-------------|-------|
| `polymc` | Open-source Minecraft launcher with instance management (Qt6 build) | [PolyMC/PolyMC](https://github.com/PolyMC/PolyMC) |
| `opencode` | Open-source AI coding agent for the terminal | [opencode.ai](https://opencode.ai) |
| `claude-code` | Anthropic's AI coding assistant for the terminal | [code.claude.com](https://code.claude.com) |
| `antigravity` | AI coding agent for the terminal from Google (installed as `agy`) | [antigravity.google](https://antigravity.google) |
| `qwen-code` | Open-source AI coding agent for the terminal | [github.com/QwenLM/qwen-code](https://github.com/QwenLM/qwen-code) |
| `yazi` | Blazing-fast terminal file manager | [sxyazi/yazi](https://github.com/sxyazi/yazi) |
| `tg-ws-proxy-go` | Local MTProto WebSocket proxy for Telegram Desktop | [Acrym48/tg-ws-proxy-go](https://github.com/Acrym48/tg-ws-proxy-go) |

Packages built from source reuse the system Guix libraries. Prebuilt
binaries (`opencode`, `yazi`, `claude-code`, `antigravity`, `qwen-code`) are
patched with `patchelf` to the glibc interpreter from the Guix store.

## Installation

Add the channel to `~/.config/guix/channels.scm`:

```scheme
(cons (channel
        (name 'faron)
        (url "https://github.com/Acrym48/faron-guix-repo"))
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
GPL-3.0-or-later license. The `tg-ws-proxy-go` package is built from
[Acrym48/tg-ws-proxy-go](https://github.com/Acrym48/tg-ws-proxy-go), which is
also licensed under the GPL-3.0-or-later license (see its `LICENSE` /
`NOTICE`).