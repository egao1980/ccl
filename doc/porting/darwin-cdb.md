# Darwin arm64 interface databases (`.cdb`)

## Status

`ccl:darwin-arm64-headers;` is required by the `:darwinarm64` FTD
(`compiler/ARM64/arm64-backend.lisp`).  Like every `*headers*` /
`*headers64*` tree it is **gitignored**.

Bring-up currently uses a **byte-copy of `darwin-x86-headers64`**.  That
is enough for fixed-arity kernel-import / cold-load `#_` names.  It is
**not** an arm64-translated database — regenerate before relying on
arch-sensitive struct layouts or Cocoa.

`struct stat` happens to match (`sizeof` 144) on the x86 copy vs Apple
Silicon today — do not generalize from that.

Full regeneration needs [Clozure/ccl-ffigen](https://github.com/Clozure/ccl-ffigen)
(workspace checkout: `ccl-ffigen/`).  Helpers: `tools/darwin-arm64-cdb/`.

## Regenerate libc core (worked Aug 2026)

```sh
# 1. ffigen5 already built with Makefile.darwin + include/clang-c
cd $CCL/darwin-arm64-headers/libc/C
$CCL/tools/darwin-arm64-cdb/libc-core-populate.sh   # -arch arm64, current SDK

# 2. parse → install-new-db-files overwrites *.cdb in place (keeps *.cdb-BAK)
cd $CCL
# BACK UP first — core-only parse replaces the WHOLE libc CDB set
cp -R darwin-arm64-headers/libc/*.cdb /tmp/libc-cdb-backup/
./darm64cl --no-init --batch < tools/darwin-arm64-cdb/parse-libc.lisp
```

**Do not leave a core-only CDB installed** over the bring-up x86 copy
unless you accept losing most `#_` entries.  Restore from backup after
validating the pipeline; expand `libc-core-populate.sh` until coverage
matches need, then install for real.

Layout smoke: `tools/darwin-cdb-stat-smoke.lisp`.

`ccl-ffigen/arm64-headers/` today is **Linux** aarch64, not Darwin.
Variadic markers (`:void` → `:variadic` sentinel) already work with the
x86-copy CDBs for `printf` / `snprintf`.

## Full Cocoa / historical lists

Port `darwin-x86-headers64/*/C/populate.sh` carefully — many 10.11 SDK
paths are gone.  Prefer growing `libc-core-populate.sh` and sibling
module scripts under `tools/darwin-arm64-cdb/` rather than committing
into the gitignored headers tree.
