# Darwin arm64 interface databases (`.cdb`)

## Status

`ccl:darwin-arm64-headers;` is required by the `:darwinarm64` FTD
(`compiler/ARM64/arm64-backend.lisp`).  Like every `*headers*` /
`*headers64*` tree it is **gitignored**.

Bring-up currently uses a **byte-copy of `darwin-x86-headers64`**.  That
is enough for fixed-arity kernel-import / cold-load `#_` names.  It is
**not** an arm64-translated database — regenerate before relying on
arch-sensitive struct layouts or Cocoa.

Full regeneration needs [Clozure/ccl-ffigen](https://github.com/Clozure/ccl-ffigen)
(not vendored in this tree).  Until that lands, keep the x86-64 copy and
treat Cocoa / `#_` record layouts as unverified on arm64.

## Regenerate (outline)

1. Clone/build `ccl-ffigen` (`ffigen5` + `Makefile.darwin`, Xcode libclang).
2. Add `darwin-arm64-headers/<module>/C/{translate,populate}.sh` modeled
   on `darwin-x86-headers64` but with `-arch arm64` and the current
   `MacOSX.sdk` (not MacOSX10.11 + `-m64`).
3. Run populate → `.ffi` files.
4. Under a darwinarm64 image:
   `(require "PARSE-FFI")`
   `(parse-standard-ffi-files "libc")` (etc.)
   → writes `.cdb` under `ccl:darwin-arm64-headers;`.

`ccl-ffigen/arm64-headers/` today is **Linux** aarch64, not Darwin.

## Smoke after regen

* `(#_getpid)`, `(#_strlen …)` already work on the x86 copy (name-only).
* Prefer a record-layout probe (`(#_stat …)` / `(:struct :stat)` size vs
  `sizeof` from a tiny C helper) before trusting Cocoa CDBs.
