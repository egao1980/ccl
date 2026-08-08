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

`library/parse-ffi.lisp` also skips functions that still fail type
reference (handler-case) and treats leaked `:null` as void.

## libc (including math.h)

```sh
mkdir -p /tmp/libc-cdb-backup
cp $CCL/darwin-arm64-headers/libc/*.cdb /tmp/libc-cdb-backup/

cd $CCL/darwin-arm64-headers/libc/C
$CCL/tools/darwin-arm64-cdb/libc-populate.sh

cd $CCL
./darm64cl --stack-size 16M --thread-stack-size 16M --no-init --batch \
  < tools/darwin-arm64-cdb/parse-libc.lisp
# load library/parse-ffi.lisp first if the image predates the skip/null fixes
```

Smoke: `tools/darwin-math-smoke.lisp`, `tools/darwin-cdb-stat-smoke.lisp`.

## Cocoa (populate OK; full umbrella parse still heavy)

```sh
cd $CCL/darwin-arm64-headers/cocoa/C
$CCL/tools/darwin-arm64-cdb/cocoa-populate.sh   # → ~7 .ffi incl. 8MB Cocoa.h
```

Parsing the full Cocoa umbrella currently stalls for a long time while
writing `new-functions.cdb` (multi-GB RSS). Keep the x86-copy cocoa CDB
until an ObjC-sliced populate (AppKit/Foundation subsets) lands.
`parse-cocoa.lisp` is ready when that slice exists.

## Notes

* `parse-standard-ffi-files` replaces `*.cdb` in place.
* See `doc/porting/darwin-cdb.md`.
