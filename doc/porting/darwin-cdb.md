# Darwin arm64 interface databases (`.cdb`)

## Status

`ccl:darwin-arm64-headers;` is required by the `:darwinarm64` FTD
(`compiler/ARM64/arm64-backend.lisp`).  Like every `*headers*` /
`*headers64*` tree it is **gitignored**.

**libc** was regenerated Aug 2026 from the current MacOSX.sdk via
`tools/darwin-arm64-cdb/libc-populate.sh` + `parse-libc.lisp`
(`-arch arm64`).  Critical record layouts (`stat`, sockets, `dirent`,
`rusage`, …) match `sizeof`.  Other modules (Cocoa, …) may still be
the x86-64 bring-up copy until their populate scripts land.

Helpers: `tools/darwin-arm64-cdb/`.  Needs
[Clozure/ccl-ffigen](https://github.com/Clozure/ccl-ffigen) (workspace:
`ccl-ffigen/`).

## Regenerate libc

```sh
mkdir -p /tmp/libc-cdb-backup
cp $CCL/darwin-arm64-headers/libc/*.cdb /tmp/libc-cdb-backup/

cd $CCL/darwin-arm64-headers/libc/C
$CCL/tools/darwin-arm64-cdb/libc-populate.sh

cd $CCL
./darm64cl --stack-size 16M --thread-stack-size 16M --no-init --batch \
  < tools/darwin-arm64-cdb/parse-libc.lisp
# Expect PARSE-LIBC-OK; quit may SIGSEGV after install — check *.cdb mtimes
```

* ~84% of the historical x86 `populate.sh` headers still exist; missing
  are mostly openssl/sql/odbc (`h-to-ffi.sh` skips them).
* **`math.h` skipped** — `math.ffi` stack-overflows the FFI reader.
* Do **not** install `libc-core-populate.sh` output over a full CDB.

Layout smoke: `tools/darwin-cdb-stat-smoke.lisp`.

## Other modules / Cocoa

Port `darwin-x86-headers64/*/C/populate.sh` the same way (`-arch arm64`,
current SDK).  Prefer scripts under `tools/darwin-arm64-cdb/` (versioned)
over the gitignored headers tree.
