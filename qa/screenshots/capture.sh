#!/usr/bin/env bash
# Captures de la scène témoin. Avec GPU : Forward+. Sans GPU (CI Linux) : Xvfb + Compatibility (signalé « _compat »).
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
OUT="${1:-}"
EXTRA=()
[ -n "$OUT" ] && EXTRA+=("--out=$OUT")
"$GODOT" --headless --path game --import >/dev/null 2>&1 || true
if [ -n "${DISPLAY:-}" ] || [ "$(uname)" = "Darwin" ] || [ "${OS:-}" = "Windows_NT" ]; then
  "$GODOT" --path game -s ../qa/screenshots/capture.gd -- --viewer "${EXTRA[@]}"
else
  xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --rendering-driver opengl3 --path game \
    -s ../qa/screenshots/capture.gd -- --viewer "${EXTRA[@]}"
fi
