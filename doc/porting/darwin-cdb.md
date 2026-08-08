# Darwin arm64 interface databases (`.cdb`)

## Status

`ccl:darwin-arm64-headers;` is **gitignored**.

| Module | Status |
|--------|--------|
| **libc** | Regenerated arm64 (current MacOSX.sdk), includes **math.h** |
| **cocoa** | Regenerated arm64 ObjC: Foundation + AppKit (+ objc runtime) |
| other | Still x86 bring-up copies |

Helpers: `tools/darwin-arm64-cdb/`. Needs
[Clozure/ccl-ffigen](https://github.com/Clozure/ccl-ffigen) (workspace:
`ccl-ffigen/`). Local ffigen5 patch maps `CXType_Half`/`Float16` → `float`.

## math.h fix

Apple `math.ffi` pulled in ~1.4k Availability macros; expanding them
stack-overflowed `process-defined-macros`. `__fp16` intrinsics became
`(null ())` (unmapped clang kinds).

Fix: `filter-ffi.py` (drop Availability/ptrcheck macros + `(null)`
functions) wired into `h-to-ffi.sh`; `parse-ffi.lisp` skips bad
functions; ffigen5 Half/Float16 → float.

Smoke: `tools/darwin-math-smoke.lisp` (`#_sin`/`#_cos`/`#_sqrt`).

## Cocoa fix

Bring-up used `-x c`, so cocoa CDBs had **0** `objc-class` forms.
Regen uses **`FFIGEN_LANG=objective-c`**, `-F…/Frameworks`, and
Foundation + AppKit (not only the Cocoa umbrella).

Full umbrellas + thousands of macros made `process-defined-macros`
look hung (re-eval every unevaluable macro each pass). Fixes:

* `process-defined-macros`: unevaluable → `:pending`; retry only after
  a pass that defines new constants
* `FILTER_FFI_MACROS=frameworks`: keep Frameworks/ macros only

Typical CDB (~current SDK): ~617 objc-classes, ~11304 objc-methods.
Smoke: `tools/darwin-cocoa-smoke.lisp` (CDB keys; no objc-bridge load).

## Regenerate libc

```sh
cd $CCL/darwin-arm64-headers/libc/C
$CCL/tools/darwin-arm64-cdb/libc-populate.sh
cd $CCL
./darm64cl --stack-size 16M --thread-stack-size 16M --no-init --batch \
  < tools/darwin-arm64-cdb/parse-libc.lisp
```

## Regenerate cocoa

```sh
mkdir -p /tmp/cocoa-cdb-backup
cp $CCL/darwin-arm64-headers/cocoa/*.cdb /tmp/cocoa-cdb-backup/

cd $CCL/darwin-arm64-headers/cocoa/C
$CCL/tools/darwin-arm64-cdb/cocoa-populate.sh

cd $CCL
./darm64cl --stack-size 16M --thread-stack-size 16M --no-init --batch \
  < tools/darwin-arm64-cdb/parse-cocoa.lisp
```
