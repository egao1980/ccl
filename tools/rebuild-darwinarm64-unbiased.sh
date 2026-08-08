#!/bin/sh
# Full unbiased Darwin/arm64 rebuild → production DUAL_MAP=0 image.
#
# Same shape as a normal CCL platform rebuild: cross-xload boot image,
# cold-load + save-application :purify t, production kernel, smokes.
# No surgical fasl reload; tip source is baked by cold-load.
#
# Cold-load of arm64-boot.image needs a DUAL_MAP=1 kernel (impure heap).
# After :purify t, rebuild with DUAL_MAP=0 for production.  make clean
# between those two kernel builds — object files are not CDEFINES-aware.
#
#   ./tools/rebuild-darwinarm64-unbiased.sh
#
# Log: /tmp/darwinarm64-rebuild-unbiased.log
# Pid: /tmp/darwinarm64-rebuild.pid
# Needs: Rosetta dx86cl64, darwin-arm64-headers, tools/with-timeout.

set -e

# Detach into a new session on first entry.  Cursor/agent shells often
# tear down their process group when the tool returns; without setsid
# that kills the with-timeout waiter and orphans dx86cl64 mid-bootstrap.
if [ "${CCL_REBUILD_SESSION:-}" != "1" ]; then
  export CCL_REBUILD_SESSION=1
  export CCL_REBUILD_LOG="${CCL_REBUILD_LOG:-/tmp/darwinarm64-rebuild-unbiased.log}"
  : > "$CCL_REBUILD_LOG"
  exec perl -e '
    use strict;
    use warnings;
    use POSIX qw(setsid);
    setsid() or die "setsid: $!\n";
    my $log = $ENV{CCL_REBUILD_LOG};
    open STDIN,  "</dev/null"   or die "stdin: $!\n";
    open STDOUT, ">>", $log     or die "stdout: $!\n";
    open STDERR, ">&STDOUT"     or die "stderr: $!\n";
    exec @ARGV;
    die "exec: $!\n";
  ' -- "$0" "$@"
fi

CCL_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$CCL_DIR"
LOG="${CCL_REBUILD_LOG:-/tmp/darwinarm64-rebuild-unbiased.log}"
PIDFILE=/tmp/darwinarm64-rebuild.pid
WT="$CCL_DIR/tools/with-timeout"
BOOT_TIMEOUT="${CCL_BOOTSTRAP_TIMEOUT:-3600}"
COLD_TIMEOUT="${CCL_COLDLOAD_TIMEOUT:-1800}"
SMOKE_TIMEOUT="${CCL_SMOKE_TIMEOUT:-90}"
CLEAN_SMOKE_TIMEOUT="${CCL_CLEAN_SMOKE_TIMEOUT:-180}"
PROD_DM="${DARWIN_ARM64_DUAL_MAP:-0}"
NCPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo $$ > "$PIDFILE"
# stdout/stderr already append to $LOG after setsid — do not truncate again.

log() { echo "$*"; }
fail() { echo "$*" >&2; rm -f "$PIDFILE"; exit 1; }
finish() { rm -f "$PIDFILE"; }

# Forward stop signals to children (with-timeout forwards to its tree).
# Killing only this shell otherwise orphans dx86cl64 in its own pgrp.
stop_children() {
  log ";; signal: stopping child processes"
  for c in $(pgrep -P $$ 2>/dev/null || true); do
    kill -TERM "$c" 2>/dev/null || true
  done
  sleep 2
  for c in $(pgrep -P $$ 2>/dev/null || true); do
    kill -KILL "$c" 2>/dev/null || true
  done
}
trap 'stop_children; finish; exit 143' TERM INT HUP
trap finish EXIT

test -x ./dx86cl64 || fail "missing ./dx86cl64 (host bootstrap)"
test -d darwin-arm64-headers/libc || fail "missing darwin-arm64-headers (cdb populate)"
test -x "$WT" || fail "missing $WT"
test -f tools/bootstrap-darwinarm64-boot.lisp || fail "missing bootstrap script"
test -f tools/save-darwinarm64-image.lisp || fail "missing save-darwinarm64-image.lisp"
arch -x86_64 /usr/bin/true >/dev/null 2>&1 || fail "Rosetta required for arch -x86_64 bootstrap"

# Stale products from a previous attempt must not satisfy test -f.
rm -f arm64-boot.image darm64cl.image
rm -rf darm64cl.dSYM
make -C lisp-kernel/darwinarm64 clean >>"$LOG" 2>&1
rm -f darm64cl

log ";; [1/4] cross-bootstrap arm64-boot.image"
"$WT" "$BOOT_TIMEOUT" env CCL_DEFAULT_DIRECTORY="$CCL_DIR" \
  arch -x86_64 ./dx86cl64 --no-init --batch \
  < tools/bootstrap-darwinarm64-boot.lisp >>"$LOG" 2>&1 \
  || fail "bootstrap failed (see $LOG)"
test -f arm64-boot.image || fail "bootstrap did not write arm64-boot.image"

log ";; [2/4] cold-load kernel DUAL_MAP=1 + purify save"
make -C lisp-kernel/darwinarm64 clean >>"$LOG" 2>&1
make -C lisp-kernel/darwinarm64 -j"$NCPU" DUAL_MAP=1 \
  "VC_REVISION=\"cold\"" >>"$LOG" 2>&1 \
  || fail "DUAL_MAP=1 kernel build failed (see $LOG)"
test -x ./darm64cl || fail "missing ./darm64cl after DUAL_MAP=1 build"

"$WT" "$COLD_TIMEOUT" ./darm64cl --image-name arm64-boot.image --no-init --batch \
  < tools/save-darwinarm64-image.lisp >>"$LOG" 2>&1 \
  || fail "cold-load / save-application failed (see $LOG)"
test -f darm64cl.image || fail "save did not write darm64cl.image"

log ";; [3/4] production kernel DUAL_MAP=$PROD_DM (clean rebuild)"
make -C lisp-kernel/darwinarm64 clean >>"$LOG" 2>&1
make -C lisp-kernel/darwinarm64 -j"$NCPU" "DUAL_MAP=$PROD_DM" \
  "VC_REVISION=\"dm$PROD_DM\"" >>"$LOG" 2>&1 \
  || fail "DUAL_MAP=$PROD_DM kernel build failed (see $LOG)"
test -x ./darm64cl || fail "missing ./darm64cl after production build"

log ";; [4/4] smokes"
./tools/run-darwin-smoke.sh "$SMOKE_TIMEOUT" tools/darwin-math-smoke.lisp
./tools/run-darwin-smoke.sh "$SMOKE_TIMEOUT" tools/darwin-interp-ff-call-smoke.lisp
./tools/run-darwin-smoke.sh "$SMOKE_TIMEOUT" tools/darwin-cocoa-smoke.lisp
./tools/run-darwin-purify-smoke.sh
# Tip bake gate: level-0 %throw + objc varargs/Protocol/uwp (no surgical reload)
./tools/run-darwin-smoke.sh "$CLEAN_SMOKE_TIMEOUT" tools/darwin-clean-build-smoke.lisp

log "DARWIN-ARM64-UNBIASED-REBUILD-OK"
