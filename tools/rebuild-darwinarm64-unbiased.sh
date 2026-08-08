#!/bin/sh
# Full unbiased Darwin/arm64 rebuild → production DUAL_MAP=0 image.
#
# Cold-load of arm64-boot.image needs DUAL_MAP=1 (impure heap).  After
# :purify t save, rebuild the kernel with DUAL_MAP=0 for production.
#
#   ./tools/rebuild-darwinarm64-unbiased.sh
#
# Log: /tmp/darwinarm64-rebuild-unbiased.log
# Needs: Rosetta dx86cl64, darwin-arm64-headers, tools/with-timeout.

set -e
CCL_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$CCL_DIR"
LOG=/tmp/darwinarm64-rebuild-unbiased.log
WT="$CCL_DIR/tools/with-timeout"
BOOT_TIMEOUT="${CCL_BOOTSTRAP_TIMEOUT:-3600}"
COLD_TIMEOUT="${CCL_COLDLOAD_TIMEOUT:-1800}"
SMOKE_TIMEOUT="${CCL_SMOKE_TIMEOUT:-90}"
CLEAN_SMOKE_TIMEOUT="${CCL_CLEAN_SMOKE_TIMEOUT:-180}"
PROD_DM="${DARWIN_ARM64_DUAL_MAP:-0}"
NCPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
: > "$LOG"

fail() { echo "$*" | tee -a "$LOG" >&2; exit 1; }

test -x ./dx86cl64 || fail "missing ./dx86cl64 (host bootstrap)"
test -d darwin-arm64-headers/libc || fail "missing darwin-arm64-headers (cdb populate)"
test -x "$WT" || fail "missing $WT"
arch -x86_64 /usr/bin/true >/dev/null 2>&1 || fail "Rosetta required for arch -x86_64 bootstrap"

echo ";; [1/4] cross-bootstrap arm64-boot.image" | tee -a "$LOG"
"$WT" "$BOOT_TIMEOUT" env CCL_DEFAULT_DIRECTORY="$CCL_DIR" \
  arch -x86_64 ./dx86cl64 --no-init --batch \
  < tools/bootstrap-darwinarm64-boot.lisp >>"$LOG" 2>&1
test -f arm64-boot.image

echo ";; [2/4] cold-load under DUAL_MAP=1 + purify save" | tee -a "$LOG"
make -C lisp-kernel/darwinarm64 clean >>"$LOG" 2>&1
make -C lisp-kernel/darwinarm64 -j"$NCPU" \
  'CDEFINES=-DDARWIN -DARM64 -D_REENTRANT -D_DARWIN_C_SOURCE -DDARWIN_ARM64_DUAL_MAP=1 -DVC_REVISION=\"cold\"' \
  >>"$LOG" 2>&1
"$WT" "$COLD_TIMEOUT" ./darm64cl --image-name arm64-boot.image --no-init --batch \
  < tools/save-darwinarm64-image.lisp >>"$LOG" 2>&1
test -f darm64cl.image

echo ";; [3/4] production kernel DUAL_MAP=$PROD_DM" | tee -a "$LOG"
make -C lisp-kernel/darwinarm64 -j"$NCPU" \
  "CDEFINES=-DDARWIN -DARM64 -D_REENTRANT -D_DARWIN_C_SOURCE -DDARWIN_ARM64_DUAL_MAP=$PROD_DM -DVC_REVISION=\"dm$PROD_DM\"" \
  >>"$LOG" 2>&1

echo ";; [4/4] smokes" | tee -a "$LOG"
./tools/run-darwin-smoke.sh "$SMOKE_TIMEOUT" tools/darwin-math-smoke.lisp
./tools/run-darwin-smoke.sh "$SMOKE_TIMEOUT" tools/darwin-interp-ff-call-smoke.lisp
./tools/run-darwin-smoke.sh "$SMOKE_TIMEOUT" tools/darwin-cocoa-smoke.lisp
./tools/run-darwin-purify-smoke.sh
# Tip bake gate: level-0 %throw + objc varargs/Protocol/uwp (no surgical reload)
./tools/run-darwin-smoke.sh "$CLEAN_SMOKE_TIMEOUT" tools/darwin-clean-build-smoke.lisp

echo "DARWIN-ARM64-UNBIASED-REBUILD-OK" | tee -a "$LOG"
