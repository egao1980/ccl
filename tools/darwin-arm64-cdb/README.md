# Darwin/arm64 CDB regeneration helpers

Scripts live here because `*headers*` / `darwin-arm64-headers/` are
**gitignored**.

## Prerequisites

* Built `ccl-ffigen/ffigen5` (`Makefile.darwin` + `include/clang-c`)
* Current MacOSX.sdk (`xcrun --show-sdk-path`)

## FFI filter (required)

`h-to-ffi.sh` runs `filter-ffi.py` after ffigen5:

* drops **Availability\*** / **ptrcheck.h** macros (circular expand →
  control-stack overflow in `process-defined-macros`)
* drops `(function …)` forms containing `(null)` (unmapped clang kinds;
  patched ffigen5 maps Half/Float16 → float)
* `FILTER_FFI_MACROS=all|frameworks|none|default` — cocoa uses
  `frameworks` (keep `/Frameworks/` macros only)

`library/parse-ffi.lisp` also skips functions that still fail type
reference (handler-case), treats leaked `:null` as void, and marks
unevaluable macros `:pending` so Cocoa-scale .ffi does not re-eval
forever.

## libc (including math.h)

```sh
mkdir -p /tmp/libc-cdb-backup
cp $CCL/darwin-arm64-headers/libc/*.cdb /tmp/libc-cdb-backup/

cd $CCL/darwin-arm64-headers/libc/C
$CCL/tools/darwin-arm64-cdb/libc-populate.sh

cd $CCL
./darm64cl --stack-size 16M --thread-stack-size 16M --no-init --batch \
  < tools/darwin-arm64-cdb/parse-libc.lisp
```

Smoke: `tools/darwin-math-smoke.lisp`, `tools/darwin-cdb-stat-smoke.lisp`.

## Cocoa (ObjC)

Must use `-x objective-c` (`FFIGEN_LANG`) — `-x c` yields **0**
objc-classes.

```sh
mkdir -p /tmp/cocoa-cdb-backup
cp $CCL/darwin-arm64-headers/cocoa/*.cdb /tmp/cocoa-cdb-backup/

cd $CCL/darwin-arm64-headers/cocoa/C
$CCL/tools/darwin-arm64-cdb/cocoa-populate.sh
# → objc runtime + Foundation + AppKit; FILTER_FFI_MACROS=frameworks

cd $CCL
./darm64cl --stack-size 16M --thread-stack-size 16M --no-init --batch \
  < tools/darwin-arm64-cdb/parse-cocoa.lisp
```

Smoke: `tools/darwin-cocoa-smoke.lisp` (~600+ classes / ~10k+ methods).

## Notes

* `parse-standard-ffi-files` replaces `*.cdb` in place.
* See `doc/porting/darwin-cdb.md`.
