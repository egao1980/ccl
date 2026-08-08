#!/bin/sh
# Rebuild Darwin/arm64 with chosen dual-map mode, purify, smoke.
# Default: DARWIN_ARM64_DUAL_MAP=1 (eager).  Override via env.
#
#   ./tools/run-darwin-drop-dual-map.sh
#   DARWIN_ARM64_DUAL_MAP=0 ./tools/run-darwin-drop-dual-map.sh

set -e
CCL_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$CCL_DIR"
LOG=/tmp/darwin-drop-dual-map.log
WT="$CCL_DIR/tools/with-timeout"
TIMEOUT="${CCL_SMOKE_TIMEOUT:-90}"
DM="${DARWIN_ARM64_DUAL_MAP:-1}"
: > "$LOG"

echo ";; kernel DARWIN_ARM64_DUAL_MAP=$DM" | tee -a "$LOG"
make -C lisp-kernel/darwinarm64 clean >>"$LOG" 2>&1
make -C lisp-kernel/darwinarm64 -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" \
  CDEFINES_EXTRA="-DDARWIN_ARM64_DUAL_MAP=$DM" >>"$LOG" 2>&1

echo ";; purify production image" | tee -a "$LOG"
"$WT" "$TIMEOUT" ./darm64cl --no-init --batch \
  < tools/save-darwinarm64-image.lisp >>"$LOG" 2>&1

MARKER="DARWIN-DUAL-MAP-${DM}-SMOKE-OK"
echo ";; smoke (expect $MARKER)" | tee -a "$LOG"
"$WT" "$TIMEOUT" ./darm64cl --no-init --batch <<LISP >>"$LOG" 2>&1
(in-package :ccl)
(unless (eql (+ 1 2) 3) (error "arith"))
(let* ((f (compile nil '(lambda (x) (* x x))))
       (n (funcall f 9)))
  (unless (eql n 81) (error "compile => ~s" n)))
(use-interface-dir :libc)
(defun %smoke-getpid () (#_getpid))
(unless (and (integerp (%smoke-getpid)) (> (%smoke-getpid) 0))
  (error "getpid"))
(format t "~&${MARKER}~%")
(quit 0)
LISP

grep -q "$MARKER" "$LOG"
echo "$MARKER"
if [ "$DM" = "0" ]; then
  echo "DARWIN-NO-DUAL-MAP-SMOKE-OK"
fi
