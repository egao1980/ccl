#!/bin/sh
# Full unbiased Darwin/arm64 rebuild:
#   1) cross-bootstrap arm64-boot.image (Rosetta host)
#   2) cold-load + save-application :purify t
#   3) optional DUAL_MAP=0 kernel + smokes
#
# Usage:
#   ./tools/rebuild-darwinarm64-unbiased.sh
#   DARWIN_ARM64_DUAL_MAP=0 ./tools/rebuild-darwinarm64-unbiased.sh

set -e
CCL_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$CCL_DIR"
LOG=/tmp/darwinarm64-rebuild-unbiased.log
WT="$CCL_DIR/tools/with-timeout"
BOOT_TIMEOUT="${CCL_BOOTSTRAP_TIMEOUT:-3600}"
COLD_TIMEOUT="${CCL_COLDLOAD_TIMEOUT:-1800}"
DM="${DARWIN_ARM64_DUAL_MAP:-1}"
: > "$LOG"

echo ";; [1/3] cross-bootstrap arm64-boot.image" | tee -a "$LOG"
"$WT" "$BOOT_TIMEOUT" env CCL_DEFAULT_DIRECTORY="$CCL_DIR" \
  arch -x86_64 ./dx86cl64 --no-init --batch \
  < tools/bootstrap-darwinarm64-boot.lisp >>"$LOG" 2>&1
test -f arm64-boot.image

echo ";; [2/3] kernel + cold-load save (DUAL_MAP=$DM)" | tee -a "$LOG"
make -C lisp-kernel/darwinarm64 -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" \
  CDEFINES_EXTRA="-DDARWIN_ARM64_DUAL_MAP=$DM" >>"$LOG" 2>&1

"$WT" "$COLD_TIMEOUT" ./darm64cl --image-name arm64-boot.image --no-init --batch \
  < tools/save-darwinarm64-image.lisp >>"$LOG" 2>&1
test -f darm64cl.image

echo ";; [3/3] smokes" | tee -a "$LOG"
CCL_SMOKE_TIMEOUT="${CCL_SMOKE_TIMEOUT:-90}" ./tools/run-darwin-arm64-ci.sh | tee -a "$LOG"
if [ "$DM" = "0" ]; then
  DARWIN_ARM64_DUAL_MAP=0 ./tools/run-darwin-drop-dual-map.sh | tee -a "$LOG"
fi

echo "DARWIN-ARM64-UNBIASED-REBUILD-OK"
