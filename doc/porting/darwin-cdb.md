# Darwin arm64 interface databases (`.cdb`)

## Status

`ccl:darwin-arm64-headers;` is **gitignored**.

| Module | Status |
|--------|--------|
| **libc** | Regenerated arm64 (current MacOSX.sdk), includes **math.h** |
| **cocoa** | Populate script ready; full Cocoa.h parse still too heavy — keep x86 copy |
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

## Regenerate libc

```sh
cd $CCL/darwin-arm64-headers/libc/C
$CCL/tools/darwin-arm64-cdb/libc-populate.sh
cd $CCL
./darm64cl --stack-size 16M --thread-stack-size 16M --no-init --batch \
  < tools/darwin-arm64-cdb/parse-libc.lisp
```

## Cocoa

`cocoa-populate.sh` produces filtered `.ffi` (including ~8 MB Cocoa.h).
Do not replace bring-up cocoa `*.cdb` until a sliced parse completes in
reasonable time — see `tools/darwin-arm64-cdb/README.md`.
