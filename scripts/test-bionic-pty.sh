#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${V2_SRC:?Set V2_SRC to the OpenCode v2 source tree}"
ANDROID_BUN="${ANDROID_BUN:-$ROOT_DIR/artifacts/transplant/android-bun/bun-1.4.0/bun}"
PTY_LIB="$(bash "$ROOT_DIR/scripts/select-bionic-pty.sh")"
[[ -x "$ANDROID_BUN" && -d "$SRC_DIR/node_modules" ]] || {
  echo "Android Bun or source dependencies missing" >&2; exit 1;
}
cd "$SRC_DIR/packages/core"
export BUN_PTY_LIB="$PTY_LIB"
exec "$ANDROID_BUN" test test/pty/pty-session.test.ts "${@}"
