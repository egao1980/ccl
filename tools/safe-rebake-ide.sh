#!/bin/sh
# Safe IDE rebake wrapper: run Lisp dump to *.image.tip-new, then promote.
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/Clozure CL64.app"
IMG_DIR="$APP/Contents/Resources/ccl"
LIVE="$IMG_DIR/darm64cl.image"
TMP="$IMG_DIR/darm64cl.image.tip-new"
LOG="${TMP}.log"
TIMEOUT="${1:-900}"

rm -f "$TMP" "$LOG"
echo ";; rebake starting → $TMP (timeout ${TIMEOUT}s)" 

./tools/with-timeout "$TIMEOUT" ./darm64cl --image-name ./darm64cl.image --no-init --batch \
  --eval '(load "ccl:tools;safe-rebake-ide.lisp")' >"$LOG" 2>&1 &
PID=$!
echo ";; lisp pid $PID"

# Wait until tip-new is a plausible heap (write finishes before cocoa restart).
ok=0
i=0
while kill -0 "$PID" 2>/dev/null; do
  i=$((i + 1))
  if [ -f "$TMP" ]; then
    sz=$(wc -c <"$TMP" | tr -d ' ')
    if [ "$sz" -gt 1000000 ]; then
      # stable size for 2s
      sleep 2
      sz2=$(wc -c <"$TMP" | tr -d ' ')
      if [ "$sz" -eq "$sz2" ] && [ "$sz2" -gt 1000000 ]; then
        echo ";; tip-new ready (${sz2} bytes) — promoting"
        ok=1
        kill -TERM "$PID" 2>/dev/null || true
        sleep 2
        kill -KILL "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
        break
      fi
    fi
  fi
  # also succeed if lisp exits cleanly with a good file
  sleep 1
  if [ "$((i % 30))" -eq 0 ]; then
    echo ";; still waiting… $(wc -c <"$TMP" 2>/dev/null || echo 0) bytes, log tail:"
    tail -3 "$LOG" 2>/dev/null || true
  fi
done

if [ "$ok" -eq 0 ]; then
  wait "$PID" 2>/dev/null || true
  if [ -f "$TMP" ]; then
    sz=$(wc -c <"$TMP" | tr -d ' ')
    if [ "$sz" -gt 1000000 ]; then
      ok=1
      echo ";; lisp exited; tip-new ${sz} bytes"
    fi
  fi
fi

if [ "$ok" -ne 1 ]; then
  echo ";; FAIL: tip-new missing or too small" >&2
  tail -40 "$LOG" >&2 || true
  ls -la "$TMP" "$LIVE" 2>&1 || true
  exit 1
fi

cp -f "$LIVE" "$IMG_DIR/darm64cl.image.pre-promote" 2>/dev/null || true
mv -f "$TMP" "$LIVE"
echo ";; promoted → $LIVE ($(wc -c <"$LIVE" | tr -d ' ') bytes)"
# codesign kernel if present
if [ -x "$APP/Contents/MacOS/darm64cl" ]; then
  codesign --force -s - "$APP/Contents/MacOS/darm64cl" 2>/dev/null || true
fi
# GUI smoke: cocoa-ide images must not be probed with --batch --eval
# (Initial runs IDE toplevel → CLASS-CELL-TYPEP noise). Launch the .app.
pkill -9 -f 'Clozure CL64.app/Contents/MacOS/darm64cl' 2>/dev/null || true
sleep 1
open "$APP"
ok_gui=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  sleep 1
  if pgrep -f 'Clozure CL64.app/Contents/MacOS/darm64cl' >/dev/null; then
    ok_gui=1
    break
  fi
done
if [ "$ok_gui" -eq 1 ]; then
  echo ";; GUI smoke ok (app stayed up ≥1s)"
  # leave running for the user; do not quit
else
  echo ";; WARN: GUI app did not stay up" >&2
  tail -20 "$LOG" >&2 || true
  exit 2
fi
echo ";; done"
tail -5 "$LOG" || true
exit 0
