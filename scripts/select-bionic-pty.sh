#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# A verified sidecar survives bun install --force and source node_modules cleanup.
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${BIONIC_PTY_SOURCE:-$HOME/app-work/pty-fix/lib/librust_pty_arm64_bionic.so}"
DEST="$ROOT_DIR/artifacts/transplant/pty-bionic/librust_pty_arm64_bionic.so"
EXPECTED=1c119d94771daf50742e403731294e5d5d7799073e9eda865c987468450c1aec

if [[ ! -f "$DEST" ]]; then
  [[ -f "$SOURCE" ]] || { echo "Missing Bionic PTY library: $SOURCE" >&2; exit 1; }
  [[ "$(sha256sum "$SOURCE" | cut -d' ' -f1)" == "$EXPECTED" ]] || {
    echo "Bionic PTY source checksum mismatch: $SOURCE" >&2; exit 1;
  }
  mkdir -p "$(dirname "$DEST")"
  cp -p "$SOURCE" "$DEST"
fi
[[ "$(sha256sum "$DEST" | cut -d' ' -f1)" == "$EXPECTED" ]] || {
  echo "Bionic PTY sidecar checksum mismatch: $DEST" >&2; exit 1;
}
LINKS="$(readelf -d "$DEST")"
if grep -Eq 'NEEDED.*lib(c|m|dl|pthread|rt)\.so\.[0-9]' <<< "$LINKS"; then
  echo "Bionic PTY sidecar depends on glibc: $DEST" >&2; exit 1
fi
SYMBOLS="$(nm -D --defined-only "$DEST")"
for symbol in bun_pty_spawn bun_pty_write bun_pty_read bun_pty_resize bun_pty_kill bun_pty_get_pid bun_pty_get_exit_code bun_pty_close; do
  grep -qw "$symbol" <<< "$SYMBOLS" || { echo "Missing PTY FFI symbol: $symbol" >&2; exit 1; }
done

# bun compile statically embeds this filename, regardless of BUN_PTY_LIB.
# Run after the final dependency install; resolve the actual package from core
# so this also handles hoisted, linked and fresh Bun dependency layouts.
if [[ -n "${V2_SRC:-}" ]]; then
  ANDROID_BUN="${ANDROID_BUN:-$ROOT_DIR/artifacts/transplant/android-bun/bun-1.4.0/bun}"
  TARGET="$(cd "$V2_SRC/packages/core" && "$ANDROID_BUN" -e '
    const path = require("node:path");
    const fs = require("node:fs");
    let dir = path.dirname(require.resolve("bun-pty"));
    while (!fs.existsSync(path.join(dir, "package.json"))) dir = path.dirname(dir);
    const pkg = JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf8"));
    if (pkg.name !== "bun-pty" || pkg.version !== "0.4.8") throw new Error("Unexpected bun-pty version");
    console.log(path.join(dir, "rust-pty/target/release/librust_pty_arm64.so"));
  ')"
  [[ -f "$TARGET" ]] || { echo "Missing bun-pty embedded library: $TARGET" >&2; exit 1; }
  if [[ "$(sha256sum "$TARGET" | cut -d' ' -f1)" != "$EXPECTED" ]]; then
    install -m 755 "$DEST" "$TARGET"
  fi
  [[ "$(sha256sum "$TARGET" | cut -d' ' -f1)" == "$EXPECTED" ]] || {
    echo "Embedded PTY checksum mismatch: $TARGET" >&2; exit 1;
  }
  echo "Verified bun-pty embedded Bionic library: $TARGET" >&2
fi
printf '%s\n' "$DEST"
