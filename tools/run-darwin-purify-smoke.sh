#!/bin/sh
# Experimental Darwin/arm64 :purify t save + reload smoke.
#
#   ./tools/run-darwin-purify-smoke.sh
#
# Leaves production darm64cl.image alone.  Exit 0 only if child prints
# DARWIN-PURIFY-SMOKE-OK.

set -e
CCL_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$CCL_DIR"
IMG=/tmp/darm64cl-purify-test.image
LOG=/tmp/darwin-purify-smoke.log

rm -f "$IMG"
./darm64cl --no-init --batch < tools/darwin-purify-smoke.lisp > "$LOG" 2>&1 || {
  echo "parent save failed:" >&2
  tail -40 "$LOG" >&2
  exit 1
}

./darm64cl --image-name "$IMG" --no-init --batch < tools/darwin-purify-smoke-child.lisp >> "$LOG" 2>&1 || {
  echo "purified child failed:" >&2
  tail -50 "$LOG" >&2
  exit 1
}

grep -q 'DARWIN-PURIFY-SMOKE-OK' "$LOG"
echo "DARWIN-PURIFY-SMOKE-OK"
