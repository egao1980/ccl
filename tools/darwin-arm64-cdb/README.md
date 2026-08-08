# Darwin/arm64 CDB regeneration helpers

Scripts live here because `*headers*` / `darwin-arm64-headers/` are
**gitignored**. Copy/run against the local headers tree.

## Prerequisites

* Built `ccl-ffigen/ffigen5` (`Makefile.darwin` + `include/clang-c`)
* Current MacOSX.sdk (`xcrun --show-sdk-path`)
* Writable `ccl/darwin-arm64-headers/libc/`

## Full libc populate (preferred)

```sh
# BACK UP bring-up / previous CDB
mkdir -p /tmp/libc-cdb-backup
cp $CCL/darwin-arm64-headers/libc/*.cdb /tmp/libc-cdb-backup/

cd $CCL/darwin-arm64-headers/libc/C
$CCL/tools/darwin-arm64-cdb/libc-populate.sh
# → ~324 .ffi (skips ~60 missing SDK headers; skips math.h — see below)

cd $CCL
./darm64cl --stack-size 16M --thread-stack-size 16M --no-init --batch \
  < tools/darwin-arm64-cdb/parse-libc.lisp
# parse may SIGSEGV on quit after success; check PARSE-LIBC-OK in the log
```

`math.h` is skipped: Apple’s `math.ffi` overflows the FFI reader control
stack even with large `--stack-size`.

Aug 2026 arm64 regen vs x86-copy bring-up (key counts):

| DB | x86-copy | arm64 regen |
|----|----------|-------------|
| functions | 4989 | **5169** |
| records | 5233 | 1662 (openssl/etc. gone; critical layouts match C) |
| constants | 13781 | **15814** |
| types | 2272 | **2511** |
| vars | 221 | **237** |
| `:stat` | 144 | 144 (= `sizeof`) |

Layout smoke: `tools/darwin-cdb-stat-smoke.lisp`.

## libc core (small slice — do not install over bring-up)

`libc-core-populate.sh` is for pipeline smoke only. A core-only parse
**replaces** the whole libc CDB set — restore from backup afterward.

## Notes

* `parse-standard-ffi-files` → `install-new-db-files` overwrites `*.cdb`
  in place (old → `*.cdb-BAK`).
* Full Cocoa / other modules: grow sibling `*-populate.sh` scripts here.
* See `doc/porting/darwin-cdb.md`.
