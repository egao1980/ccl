#!/bin/sh
# Darwin/arm64 Cocoa interface populate (ObjC runtime + Cocoa.h umbrella).
#
#   cd $CCL/darwin-arm64-headers/cocoa/C
#   $CCL/tools/darwin-arm64-cdb/cocoa-populate.sh
#   cd $CCL
#   ./darm64cl --stack-size 16M --thread-stack-size 16M --no-init --batch \
#     < tools/darwin-arm64-cdb/parse-cocoa.lisp
#
# BACK UP cocoa/*.cdb first. Uses the same h-to-ffi.sh + filter-ffi.py as libc.

set -e
HERE=$(cd "$(dirname "$0")" && pwd)
PATH="${HERE}:$PATH"
export PATH

if [ -z "${SDK}" ]; then
  SDK=$(xcrun --show-sdk-path)
fi
if [ $# -eq 1 ]; then
  SDK=$1
fi
if [ ! -d "$SDK" ]; then
  echo "SDK not found: $SDK" >&2
  exit 1
fi

rm -rf Applications Library System usr

CFLAGS="-arch arm64 -isysroot ${SDK} -ObjC"
CLANG_BIN=$(xcrun --find clang)
CLANG_ROOT=$(dirname "$(dirname "$CLANG_BIN")")
CLANG_INC="$CLANG_ROOT/lib/clang"
if [ -d "$CLANG_INC" ]; then
  VER=$(ls "$CLANG_INC" | tail -1)
  if [ -n "$VER" ] && [ -d "$CLANG_INC/$VER/include" ]; then
    CFLAGS="$CFLAGS -isystem $CLANG_INC/$VER/include"
  fi
fi
export CFLAGS SDK

# Modern SDKs moved objc headers under /usr/include/objc or the SDK share.
for h in \
  "${SDK}/usr/include/objc/objc-runtime.h" \
  "${SDK}/usr/include/objc/runtime.h" \
  "${SDK}/usr/include/objc/objc-exception.h" \
  "${SDK}/usr/include/objc/objc.h" \
  "${SDK}/usr/include/objc/Object.h" \
  "${SDK}/usr/include/objc/Protocol.h" \
  "${SDK}/System/Library/Frameworks/Cocoa.framework/Headers/Cocoa.h"
do
  h-to-ffi.sh "$h"
done

echo ";; cocoa-populate done under $(pwd)"
