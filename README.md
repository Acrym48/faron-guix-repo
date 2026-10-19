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
| `codebase-memory-mcp` | Code intelligence MCP server backed by a local knowledge graph | [DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) |
| `tg-ws-proxy-go` | Local MTProto WebSocket proxy for Telegram Desktop | [Acrym48/tg-ws-proxy-go](https://github.com/Acrym48/tg-ws-proxy-go) |
| `glow` | Render Markdown on the CLI, with pretty syntax highlighting | [charmbracelet/glow](https://github.com/charmbracelet/glow) |
| `driftwm` | Trackpad-first infinite canvas Wayland compositor (Smithay) | [malbiruk/driftwm](https://github.com/malbiruk/driftwm) |
| `onlyoffice-desktopeditors` | Office suite for documents, spreadsheets, and presentations | [ONLYOFFICE/DesktopEditors](https://github.com/ONLYOFFICE/DesktopEditors) |
| `font-microsoft-times-new-roman` | Times New Roman from the Microsoft core fonts for the web | [corefonts](https://sourceforge.net/projects/corefonts/) |

Packages built from source reuse the system Guix libraries. The `glow`
package is built from the [charm.land/glow/v3](https://github.com/charmbracelet/glow)
source and brings its own Go dependency stack (`charm.land/v2` modules plus
fresh `x/ansi`, `x/term`, `x/windows`, `x/cellbuf` versions that are not yet
in GNU Guix).  Prebuilt
binaries (`opencode`, `yazi`, `claude-code`, `antigravity`, `qwen-code`) are
patched with `patchelf` to the glibc interpreter from the Guix store.  These
prebuilt binary packages ship both `x86_64-linux` and `aarch64-linux`
artifacts and pull the matching one for the build system.

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
glow --help
```

## Using a package in a system / home config

Import the module in your `config.scm` or `home-config.scm` `use-modules`
and reference the package by name:

```scheme
(use-modules (faron packages polymc)      ; system
             (faron packages glow))       ; terminal

(home-environment
  (packages (list polymc glow)))
```

## Services

`tg-ws-proxy-go` ships Shepherd services (`faron services tg-ws-proxy`)
for both system and home configurations:

```scheme
;; system.scm — runs under a dedicated unprivileged user
(use-modules (faron services tg-ws-proxy))

(operating-system
  ;; ...
  (services (cons (service tg-ws-proxy-service-type
                           (tg-ws-proxy-configuration
                            (port 1443)
                            (secret-file "/etc/tg-ws-proxy/secret")))
                  %base-services)))
```

```scheme
;; home.scm — runs as the home user
(use-modules (faron services tg-ws-proxy))

(home-environment
  ;; ...
  (services (cons (service tg-ws-proxy-home-service-type
                           (tg-ws-proxy-configuration
                            (fallback 'cf)))
                  %base-home-services)))
```

Prefer `secret-file` over `secret`: the file is read at service start into
`TG_WS_PROXY_SECRET` and never lands in the store, while a plain `secret`
string ends up on the daemon command line (visible via `ps`).

## Updating packages

`bump.sh` checks upstream APIs for new versions of the `url-fetch`
packages, refreshes the `version` and both `nix-base32` hashes
(`x86_64` + `aarch64`), and commits each update as
`bump <pkg> <old> -> <new>`:

```bash
./bump.sh --check          # only show what is outdated
./bump.sh                  # update everything, committing per package
./bump.sh qwen-code yazi   # update selected packages only
```

Covered: `opencode`, `claude-code`, `antigravity`, `qwen-code`,
`kimi-code`, `yazi`, `codebase-memory-mcp`, `driftwm`.  The `git-fetch`
packages (`glow` + its Go stack, `tg-ws-proxy-go`, `anilib-cli`,
`polymc`) still need a manual bump with `guix hash -r`.  Needs `curl`,
`jq`, `python3`, `git`; set `GITHUB_TOKEN` to avoid GitHub API
rate limits.

## License

Unless otherwise noted, the channel code is free software licensed under the
GPL-3.0-or-later license. The `tg-ws-proxy-go` package is built from
[Acrym48/tg-ws-proxy-go](https://github.com/Acrym48/tg-ws-proxy-go), which is
also licensed under the GPL-3.0-or-later license (see its `LICENSE` /
`NOTICE`).