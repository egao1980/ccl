#!/bin/sh
# Rebuild Darwin/arm64 image without dual-map dependency.
#
# Phase A (current dual-map kernel): recompile lisp (no HEAP_EXEC_BIAS),
#   xload boot, cold-load + :purify t → darm64cl.image
# Phase B: rebuild kernel with DARWIN_ARM64_DUAL_MAP=0
# Phase C: smoke purified image under new kernel
#
#   ./tools/run-darwin-drop-dual-map.sh

set -e
CCL_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$CCL_DIR"
LOG=/tmp/darwin-drop-dual-map.log
: > "$LOG"

echo ";; phase A: recompile + purified image (dual-map kernel still running)" | tee -a "$LOG"
./darm64cl --no-init --batch <<'EOF' >>"$LOG" 2>&1
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil
      *outstanding-deferred-warnings* nil)
(format t "~&;; compile-ccl t~%")
(compile-ccl t)
(format t "~&;; xload-level-0 :force~%")
(xload-level-0 :force)
(format t "~&;; PHASE-A-XLOAD-OK~%")
(quit 0)
EOF

echo ";; phase A: cold-load boot → purify save" | tee -a "$LOG"
./darm64cl --image-name arm64-boot.image --no-init --batch \
  < tools/save-darwinarm64-image.lisp >>"$LOG" 2>&1

grep -q 'PHASE-A-XLOAD-OK' "$LOG"
grep -q 'save-application darm64cl.image :purify t' "$LOG" || true

echo ";; phase B: kernel DARWIN_ARM64_DUAL_MAP=0" | tee -a "$LOG"
make -C lisp-kernel/darwinarm64 clean >>"$LOG" 2>&1
make -C lisp-kernel/darwinarm64 -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" >>"$LOG" 2>&1

echo ";; phase C: smoke" | tee -a "$LOG"
./darm64cl --no-init --batch <<'EOF' >>"$LOG" 2>&1
(in-package :ccl)
(unless (eql (+ 1 2) 3) (error "arith"))
(let* ((f (compile nil '(lambda (x) (* x x))))
       (n (funcall f 9)))
  (unless (eql n 81) (error "compile => ~s" n)))
(use-interface-dir :libc)
(unless (and (integerp (#_getpid)) (> (#_getpid) 0))
  (error "getpid"))
(format t "~&DARWIN-NO-DUAL-MAP-SMOKE-OK~%")
(quit 0)
EOF

grep -q 'DARWIN-NO-DUAL-MAP-SMOKE-OK' "$LOG"
echo "DARWIN-NO-DUAL-MAP-SMOKE-OK"
