# tg-ws-proxy-go

A Go port of the core of [tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy):
a local MTProto proxy that bridges Telegram Desktop traffic to Telegram over
WebSocket connections.

The proxy listens on a local TCP port and presents a standard MTProto proxy
connection string. Client connections are bridged to Telegram's WebSocket
upstreams (`kws*.web.telegram.org`) and, when the primary path fails or a DC is
not routed, to a configurable chain of fallbacks (Cloudflare-proxied domains,
Cloudflare Workers, or direct TCP).

## Features

- MTProto proxy protocol support (abridged, intermediate, padded intermediate)
- Fake TLS masking with a configurable SNI domain (obfuscated `ee` secret)
- Automatic fallback chain: Cloudflare-proxied domains and/or Cloudflare
  Workers, with direct TCP as the last resort
- Pooled WebSocket connections per DC (media / non-media) with warmup, refill
  and rotation
- HTTP redirect (302) handling and per-DC / per-IP failure cooldowns
- PROXY protocol v1 support
- Optional forcing of all traffic to Telegram TEST datacenters
- Pretty structured logging with optional file logging and size-based rotation
- Zero external services required — a single static binary

## Requirements

- Go 1.26 or newer to build from source
- `just` (optional) to use the recipes in the `justfile`

## Build

```sh
just build            # or: go build ./cmd/tg-ws-proxy
```

The resulting binary is written to `./tg-ws-proxy`.

## Quick start

```sh
./tg-ws-proxy --port 1443 --secret <32-hex-chars>
```

If `--secret` is omitted, a random secret is generated and printed on startup.
Use the printed connection string (e.g. `tg://proxy?server=127.0.0.1&port=1443&secret=dd...`) to
connect from Telegram.

> The banner shown at startup includes ready-to-use `tg://proxy` links.

## Usage

```
Usage: tg-ws-proxy [flags] [dc-ips...]

Flags:
  -host string              listen host (default "127.0.0.1", env TG_WS_PROXY_HOST)
  -port int                 listen port (default 1443, env TG_WS_PROXY_PORT)
  -secret string            MTProto proxy secret (32 hex chars); auto-generated if empty
                            (env TG_WS_PROXY_SECRET)
  -v                        debug logging
  -log-file string          log to file with rotation (default: stderr only)
  -log-max-mb float         max log file size in MB before rotation (default 5)
  -log-backups int          number of rotated log files to keep (min 1)
  -buf-kb int               socket send/recv buffer size in KB (default 256)
  -pool-size int            WS connection pool size per DC (default 4, min 0)
  -no-cfproxy               disable Cloudflare proxy fallback (auto chain only)
  -fallback string          explicit fallback chain, e.g. "cf_worker,tcp"; "off" disables
                            fallbacks (overrides --no-cfproxy)
  -fake-tls-domain string   enable Fake TLS (ee-secret) masking with the given SNI domain
  -force-test-dc            force ALL traffic to Telegram TEST datacenters
  -proxy-protocol           accept PROXY protocol v1 header
  -dc-ip value              target IP for a DC, e.g. 2:149.154.167.220 (repeatable)
  -cfproxy-domain value     user defined Cloudflare-proxied domain for WS fallback (repeatable)
  -cfproxy-worker-domain value  Cloudflare Worker domain for WS fallback (repeatable)
```

Positional `dc-ips` arguments (e.g. `2:149.154.167.220`) are an alias for
repeated `--dc-ip` flags. Environment variable `TG_WS_PROXY_DC_IPS` is honored
when no `--dc-ip`/positional values are given, and `TG_WS_PROXY_CF_WORKER`
supplies extra Cloudflare Worker domains.

### Examples

Run with Fake TLS masking and no Cloudflare fallback:

```sh
./tg-ws-proxy --fake-tls-domain example.com --fallback tcp
```

Serve on all interfaces with a custom DC map:

```sh
./tg-ws-proxy --host 0.0.0.0 --port 1443 \
  --dc-ip 2:149.154.167.51 \
  --dc-ip 4:149.154.167.91
```

Log to a rotating file:

```sh
./tg-ws-proxy --log-file proxy.log --log-max-mb 10 --log-backups 3
```

### Telegram connection

Two secret types are supported:

- Simple (default): `tg://proxy?server=<host>&port=<port>&secret=dd<secret>`
- Fake TLS: `tg://proxy?server=<host>&port=<port>&secret=ee<secret><domain-hex>`

The domain hex suffix is the hex-encoded Fake TLS SNI domain.

## Configuration

Runtime behaviour is controlled exclusively through CLI flags and environment
variables (see above). There is no config file. The Cloudflare-proxied domain
pool is refreshed hourly from the upstream
[`cfproxy-domains.txt`](https://raw.githubusercontent.com/Flowseal/tg-ws-proxy/main/.github/cfproxy-domains.txt)
unless user domains are supplied via `--cfproxy-domain`.

## Project layout

```
cmd/tg-ws-proxy/   entrypoint: flags, logging, signal handling
internal/balancer  weighted domain balancer
internal/config    config model, flag parsing, CF domain pool management
internal/faketls   Fake TLS (obfuscated secret) client/server hello handling
internal/mtproto   MTProto handshake parsing and crypto context
internal/pool      pooled WebSocket connections (per-DC and CF worker)
internal/proxy     bridge server: handshake, fallback routing, listener
internal/splitter  MTProto transport re-encryption splitter
internal/stats     live counters and summary
internal/utils     WS constants, DC/domain helpers
internal/wsconn    raw WebSocket dial and read/write helpers
internal/xlog      structured pretty logger
```

## Development

```sh
just test          # run all tests
just vet           # go vet ./...
just fmt           # gofmt -l -w .
```

Nix-based development environments are provided via `flake.nix`, `shell.nix`
and `guix.scm`.

## License

GPL-3.0, see [LICENSE](LICENSE). This project is a Go port of the core of
[tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy) by Flowseal (MIT); the
original notice is retained in [NOTICE](NOTICE).
