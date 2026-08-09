#!/bin/sh
# Unified Darwin/arm64 smoke gate.  Requires ./darm64cl + darm64cl.image.
# Exit nonzero on first failure.  Timeouts via tools/with-timeout.

set -e
CCL_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$CCL_DIR"
SMOKE="$CCL_DIR/tools/run-darwin-smoke.sh"
TIMEOUT="${CCL_SMOKE_TIMEOUT:-90}"

echo ";; darwinarm64 CI smokes (timeout=${TIMEOUT}s)"
"$SMOKE" "$TIMEOUT" tools/darwin-math-smoke.lisp
"$SMOKE" "$TIMEOUT" tools/darwin-purify-smoke.lisp
"$SMOKE" "$TIMEOUT" tools/darwin-cocoa-smoke.lisp
"$SMOKE" "$TIMEOUT" tools/darwin-interp-ff-call-smoke.lisp || {
  echo ";; interp ff-call smoke failed (optional until %ff-call lands in image)" >&2
  exit 1
}

# objc-bridge is optional until green
if [ "${CCL_CI_OBJC_BRIDGE:-}" = "1" ]; then
  "$SMOKE" "$TIMEOUT" tools/darwin-objc-bridge-smoke.lisp
fi

echo "DARWIN-ARM64-CI-OK"
