#!/bin/sh
# IDE smokes: workspace darm64cl + CFProcessPath so NSBundle sees Clozure CL64.app.
# (Copying into MacOS/ breaks codesign → immediate SIGKILL.)
# Usage: run-darwin-ide-smoke.sh [TIMEOUT] smoke.lisp [MARKER]
set -e
CCL_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$CCL_DIR"
APP="$CCL_DIR/Clozure CL64.app"
WT="$CCL_DIR/tools/with-timeout"

TIMEOUT=120
if [ $# -ge 1 ] && expr "$1" : '[0-9][0-9]*$' >/dev/null 2>&1; then
  TIMEOUT=$1
  shift
fi
if [ $# -lt 1 ]; then
  echo "usage: $0 [TIMEOUT] smoke.lisp [MARKER]" >&2
  exit 2
fi
SMOKE=$1
shift
MARK=${1:-}
if [ -z "$MARK" ]; then
  base=$(basename "$SMOKE" .lisp)
  MARK=$(printf '%s' "$base" | tr '[:lower:]' '[:upper:]')-OK
fi
LOG=/tmp/$(basename "$SMOKE" .lisp).log

# Keep a tip image inside the app Resources for consistency; kernel stays workspace.
mkdir -p "$APP/Contents/Resources/ccl"
cp -f "$CCL_DIR/darm64cl.image" "$APP/Contents/Resources/ccl/darm64cl.image"

export CFProcessPath="$APP/Contents/MacOS/darm64cl"
# Ensure the path exists (touch stub if missing) without replacing a signed binary.
if [ ! -e "$CFProcessPath" ]; then
  mkdir -p "$(dirname "$CFProcessPath")"
  cp -f "$CCL_DIR/darm64cl" "$CFProcessPath" || touch "$CFProcessPath"
fi

"$WT" "$TIMEOUT" env CFProcessPath="$CFProcessPath" \
  "$CCL_DIR/darm64cl" --no-init --batch < "$SMOKE" > "$LOG" 2>&1 || {
  ec=$?
  echo "IDE-SMOKE FAIL: $SMOKE exit=$ec. Tail:" >&2
  tail -50 "$LOG" >&2
  exit "$ec"
}
if ! grep -q "$MARK" "$LOG"; then
  echo "IDE-SMOKE FAIL: $SMOKE missing marker $MARK. Tail:" >&2
  tail -50 "$LOG" >&2
  exit 1
fi
echo "$MARK"
