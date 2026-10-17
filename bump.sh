#!/usr/bin/env bash
# bump.sh — сверяет версии пакетов канала с апстримом, обновляет version +
# nix-base32 хэши в faron/packages/*.scm и коммитит в стиле истории:
#   bump <pkg> <old> -> <new>
#
# Покрывает пакеты на url-fetch (версию и хэш можно получить без guix):
#   opencode, claude-code, antigravity, qwen-code, kimi-code,
#   yazi, codebase-memory-mcp, driftwm, onlyoffice-desktopeditors
# Пакеты на git-fetch (нужен `guix hash -r` по чекауту) не трогает:
#   glow (+go-стек), tg-ws-proxy-go, anilib-cli, polymc — их бампить вручную.
#
# Usage:
#   ./bump.sh [--check] [pkg...]
#     --check   только показать current -> latest, ничего не менять
#     pkg...    ограничить набором пакетов (по умолчанию все выше)
#
# Зависимости: curl, jq, python3, git. Для GitHub API без рейт-лимита:
#   export GITHUB_TOKEN=<token>
#
# Хэши считаются как `guix download`: sha256 файла -> nix base32
# (тот же алгоритм, что в ~/sha256-to-nix32.sh).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CHECK=0
WANT=()
for arg in "$@"; do
    case "$arg" in
        --check) CHECK=1 ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0 ;;
        *) WANT+=("$arg") ;;
    esac
done

for dep in curl jq python3 git; do
    command -v "$dep" >/dev/null || { echo "нет $dep в PATH" >&2; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- helpers ---------------------------------------------------------------

gh_api() { # GET api.github.com с опциональным токеном
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -fsS --max-time 30 -H "Authorization: Bearer $GITHUB_TOKEN" "$@"
    else
        curl -fsS --max-time 30 "$@"
    fi
}

# sha256 hex (stdin) -> nix base32 (stdout)
nix32() {
    python3 -c '
import sys
hexs = sys.stdin.read().strip().lower().replace(" ", "")
assert len(hexs) == 64 and all(c in "0123456789abcdef" for c in hexs), "bad sha256"
raw = bytes.fromhex(hexs)
chars = "0123456789abcdfghijklmnpqrsvwxyz"
out = ""
for n in range(51, -1, -1):
    b = n * 5; i = b // 8; j = b % 8
    c = raw[i] >> j
    if i < 31:
        c |= raw[i + 1] << (8 - j)
    out += chars[c & 0x1f]
print(out)'
}

# скачать URL и выдать nix32 хэш файла
hash_url() { # <url>
    local f="$TMP/dl-$(date +%s%N)"
    curl -fL --max-time 300 -o "$f" "$1"
    sha256sum "$f" | cut -d' ' -f1 | nix32
    rm -f "$f"
}

# пустая/битая версия из API — не продолжать, а пропустить пакет
require_ver() { # <pkg> <ver>
    if [ -z "${2:-}" ] || [ "$2" = "null" ]; then
        echo "$1: не смог узнать версию из апстрима" >&2
        return 1
    fi
}
newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]; }

# текущая (version "X") пакета <pkg> в файле <file>
current_version() { # <file> <pkg>
    sed -n "/(name \"$2\")/,/(version/p" "$1" \
        | sed -n 's/.*(version "\([^"]*\)").*/\1/p' | head -1
}

# заменить (version "OLD") -> (version "NEW") в файле
set_version() { # <file> <old> <new>
    python3 - "$1" "$2" "$3" <<'EOF'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
a, b = f'(version "{old}")', f'(version "{new}")'
assert s.count(a) == 1, f"version {old} found {s.count(a)} times in {path}"
open(path, "w").write(s.replace(a, b))
EOF
}

# заменить base32-хэши внутри блока (define-public <pkg> ...) по порядку:
# первый (aarch64-ветка) -> $3, второй (x86_64) -> $4
set_hashes() { # <file> <pkg> <arm32> <x64_32>
    python3 - "$1" "$2" "$3" "$4" <<'EOF'
import re, sys
path, pkg, arm, x64 = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(path).read()
m = re.search(r"\(define-public " + re.escape(pkg) + r"\b", s)
assert m, f"package {pkg} not found in {path}"
nxt = re.search(r"\(define-public ", s[m.end():])
blk_end = m.end() + nxt.start() if nxt else len(s)
blk = s[m.start():blk_end]
hashes = list(re.finditer(r'\(base32 "([0-9a-z]{52})"\)', blk))
assert len(hashes) == 2, f"{pkg}: expected 2 hashes, found {len(hashes)}"
blk = blk[::-1].replace(hashes[1].group(1)[::-1], x64[::-1], 1)[::-1]
blk = blk[::-1].replace(hashes[0].group(1)[::-1], arm[::-1], 1)[::-1]
open(path, "w").write(s[:m.start()] + blk + s[blk_end:])
EOF
}

commit_bump() { # <file> <pkg> <old> <new>
    git add "$1"
    git commit -q -m "bump $2 $3 -> $4"
    echo "committed: bump $2 $3 -> $4"
}

# типовой пакет с GitHub-релизами: tag -> version, два артефакта по шаблону.
# url_template: https://... с подстановками {V} (version) и {T} (tag).
github_bump() { # <pkg> <file> <repo> <tag_re> <strip_v:0|1> <url_template> <arm_asset> <x64_asset>
    local pkg="$1" file="$2" repo="$3" tag_re="$4" strip="$5" tmpl="$6"
    local arm_asset="$7" x64_asset="$8"
    local cur tag ver url_arm url_x64 h_arm h_x64
    cur="$(current_version "$file" "$pkg")"
    if [ "$tag_re" = "LATEST" ]; then
        tag="$(gh_api "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name)"
    else
        tag="$(gh_api "https://api.github.com/repos/$repo/releases?per_page=20" \
               | jq -r --arg re "$tag_re" '[.[].tag_name | select(test($re))] | .[0]')"
    fi
    [ -n "$tag" ] && [ "$tag" != "null" ] || { echo "$pkg: не смог узнать тег" >&2; return 1; }
    ver="$tag"
    [ "$strip" = 1 ] && ver="${tag#v}"
    require_ver "$pkg" "$ver" || return 1
    echo "$pkg: $cur -> $ver"
    if [ "$CHECK" = 1 ]; then return 0; fi
    newer "$cur" "$ver" || { echo "$pkg: актуально"; return 0; }
    url_arm="${tmpl//\{V\}/$ver}"; url_arm="${url_arm//\{T\}/$tag}"; url_arm="$url_arm$arm_asset"
    url_x64="${tmpl//\{V\}/$ver}"; url_x64="${url_x64//\{T\}/$tag}"; url_x64="$url_x64$x64_asset"
    echo "$pkg: качаю arm64..."
    h_arm="$(hash_url "$url_arm")"
    echo "$pkg: качаю x64..."
    h_x64="$(hash_url "$url_x64")"
    set_version "$file" "$cur" "$ver"
    set_hashes "$file" "$pkg" "$h_arm" "$h_x64"
    commit_bump "$file" "$pkg" "$cur" "$ver"
}

want() { # <pkg> — входит ли в запрошенный набор (или набор пуст = все)
    [ "${#WANT[@]}" -eq 0 ] && return 0
    local w
    for w in "${WANT[@]}"; do [ "$w" = "$1" ] && return 0; done
    return 1
}

# --- пакеты ----------------------------------------------------------------

AI=faron/packages/ai.scm
BIN=faron/packages/binaries.scm

# claude-code: manifest отдаёт версию и sha256 обоих платформ — качать нечего
bump_claude() {
    local base="https://downloads.claude.ai/claude-code-releases"
    local cur latest manifest ver h_arm h_x64 sum
    cur="$(current_version "$AI" claude-code)"
    latest="$(curl -fsS --max-time 30 "$base/latest")"
    manifest="$(curl -fsS --max-time 30 "$base/$latest/manifest.json")"
    ver="$(printf '%s' "$manifest" | jq -r .version)"
    require_ver claude-code "$ver" || return 1
    echo "claude-code: $cur -> $ver"
    if [ "$CHECK" = 1 ]; then return 0; fi
    newer "$cur" "$ver" || { echo "claude-code: актуально"; return 0; }
    for plat in linux-arm64 linux-x64; do
        sum="$(printf '%s' "$manifest" | jq -r --arg p "$plat" '.platforms[$p].checksum')"
        if [ "$plat" = linux-arm64 ]; then h_arm="$(printf '%s' "$sum" | nix32)"
        else h_x64="$(printf '%s' "$sum" | nix32)"; fi
    done
    set_version "$AI" "$cur" "$ver"
    set_hashes "$AI" claude-code "$h_arm" "$h_x64"
    commit_bump "$AI" claude-code "$cur" "$ver"
}

# opencode: версия из npm-реестра, хэши — скачать два tgz
bump_opencode() {
    local cur ver h_arm h_x64 v_arm
    cur="$(current_version "$AI" opencode)"
    ver="$(curl -fsS --max-time 30 "https://registry.npmjs.org/@opencode%2fcli-linux-x64-baseline/latest" | jq -r .version)"
    v_arm="$(curl -fsS --max-time 30 "https://registry.npmjs.org/@opencode%2fcli-linux-arm64/latest" | jq -r .version)"
    require_ver opencode "$ver" || return 1
    require_ver opencode "$v_arm" || return 1
    [ "$ver" = "$v_arm" ] || echo "opencode: версии платформ расходятся: x64=$ver arm64=$v_arm" >&2
    echo "opencode: $cur -> $ver"
    if [ "$CHECK" = 1 ]; then return 0; fi
    newer "$cur" "$ver" || { echo "opencode: актуально"; return 0; }
    echo "opencode: качаю arm64..."
    h_arm="$(hash_url "https://registry.npmjs.org/@opencode/cli-linux-arm64/-/cli-linux-arm64-$ver.tgz")"
    echo "opencode: качаю x64..."
    h_x64="$(hash_url "https://registry.npmjs.org/@opencode/cli-linux-x64-baseline/-/cli-linux-x64-baseline-$ver.tgz")"
    set_version "$AI" "$cur" "$ver"
    set_hashes "$AI" opencode "$h_arm" "$h_x64"
    commit_bump "$AI" opencode "$cur" "$ver"
}

# kimi-code: версия из /latest, бинари — скачать напрямую
bump_kimi() {
    local base="https://code.kimi.com/kimi-code/binaries"
    local cur ver h_arm h_x64
    cur="$(current_version "$AI" kimi-code)"
    ver="$(curl -fsS --max-time 30 "$base/latest" | tr -d '[:space:]')"
    require_ver kimi-code "$ver" || return 1
    echo "kimi-code: $cur -> $ver"
    if [ "$CHECK" = 1 ]; then return 0; fi
    newer "$cur" "$ver" || { echo "kimi-code: актуально"; return 0; }
    echo "kimi-code: качаю arm64..."
    h_arm="$(hash_url "$base/$ver/kimi-code-linux-arm64")"
    echo "kimi-code: качаю x64..."
    h_x64="$(hash_url "$base/$ver/kimi-code-linux-x64")"
    set_version "$AI" "$cur" "$ver"
    set_hashes "$AI" kimi-code "$h_arm" "$h_x64"
    commit_bump "$AI" kimi-code "$cur" "$ver"
}

# driftwm: версия в %driftwm-version, два хэша — vendor-TAR и source-TAR
bump_driftwm() {
    local file=faron/packages/driftwm.scm
    local cur ver h_vendor h_src
    cur="$(sed -n 's/.*(define %driftwm-version "\(.*\)").*/\1/p' "$file")"
    ver="$(gh_api "https://api.github.com/repos/malbiruk/driftwm/releases/latest" | jq -r .tag_name)"
    ver="${ver#v}"
    require_ver driftwm "$ver" || return 1
    echo "driftwm: $cur -> $ver"
    if [ "$CHECK" = 1 ]; then return 0; fi
    newer "$cur" "$ver" || { echo "driftwm: актуально"; return 0; }
    echo "driftwm: качаю vendor..."
    h_vendor="$(hash_url "https://github.com/malbiruk/driftwm/releases/download/v$ver/driftwm-$ver-vendor.tar.xz")"
    echo "driftwm: качаю source..."
    h_src="$(hash_url "https://github.com/malbiruk/driftwm/archive/refs/tags/v$ver.tar.gz")"
    python3 - "$file" "$cur" "$ver" "$h_vendor" "$h_src" <<'EOF'
import re, sys
path, cur, ver, hv, hs = sys.argv[1:6]
s = open(path).read()
a = f'(define %driftwm-version "{cur}")'
assert s.count(a) == 1
s = s.replace(a, f'(define %driftwm-version "{ver}")')
hashes = list(re.finditer(r'\(base32 "([0-9a-z]{52})"\)', s))
assert len(hashes) == 2, f"driftwm: found {len(hashes)} hashes"
s = s[::-1].replace(hashes[1].group(1)[::-1], hs[::-1], 1)[::-1]  # source
s = s[::-1].replace(hashes[0].group(1)[::-1], hv[::-1], 1)[::-1]  # vendor
open(path, "w").write(s)
EOF
    commit_bump "$file" driftwm "$cur" "$ver"
}

# --- main ------------------------------------------------------------------

run() { # обёртка: одна ошибка пакета не валит остальные
    "$@" || echo "$1: ПРОПУЩЕН (см. ошибку выше)" >&2
}

want opencode && run bump_opencode
want claude-code && run bump_claude
want antigravity && run github_bump antigravity "$AI" \
    google-antigravity/antigravity-cli LATEST 0 \
    "https://github.com/google-antigravity/antigravity-cli/releases/download/{V}/" \
    agy_cli_linux_arm64.tar.gz agy_cli_linux_x64.tar.gz
want qwen-code && run github_bump qwen-code "$AI" \
    QwenLM/qwen-code '^v[0-9]+\.[0-9]+\.[0-9]+$' 1 \
    "https://github.com/QwenLM/qwen-code/releases/download/{T}/" \
    qwen-code-linux-arm64.tar.gz qwen-code-linux-x64.tar.gz
want kimi-code && run bump_kimi
want yazi && run github_bump yazi "$BIN" \
    sxyazi/yazi LATEST 1 \
    "https://github.com/sxyazi/yazi/releases/download/{T}/" \
    yazi-aarch64-unknown-linux-gnu.zip yazi-x86_64-unknown-linux-gnu.zip
want codebase-memory-mcp && run github_bump codebase-memory-mcp "$BIN" \
    DeusData/codebase-memory-mcp LATEST 1 \
    "https://github.com/DeusData/codebase-memory-mcp/releases/download/{T}/" \
    codebase-memory-mcp-linux-arm64-portable.tar.gz \
    codebase-memory-mcp-linux-amd64-portable.tar.gz
want driftwm && run bump_driftwm
want onlyoffice-desktopeditors && run github_bump onlyoffice-desktopeditors \
    faron/packages/onlyoffice.scm \
    ONLYOFFICE/DesktopEditors LATEST 1 \
    "https://github.com/ONLYOFFICE/DesktopEditors/releases/download/{T}/" \
    onlyoffice-desktopeditors-aarch64.tar.xz \
    onlyoffice-desktopeditors-x64.tar.xz

if [ "$CHECK" = 0 ]; then
    echo
    echo "Напомню: git-fetch пакеты бампятся вручную (нужен guix):"
    echo "  glow (+go-стек), tg-ws-proxy-go, anilib-cli, polymc"
fi
