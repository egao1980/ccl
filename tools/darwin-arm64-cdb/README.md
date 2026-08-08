# Darwin/arm64 CDB regeneration helpers

Scripts live here because `*headers*` / `darwin-arm64-headers/` are
**gitignored**. Copy/run against the local headers tree.

## Prerequisites

* Built `ccl-ffigen/ffigen5` (`Makefile.darwin` + `include/clang-c`)
* Current MacOSX.sdk (`xcrun --show-sdk-path`)
* Writable `ccl/darwin-arm64-headers/libc/`

## libc core (recommended first slice)

```sh
cd $CCL/darwin-arm64-headers/libc/C
$CCL/tools/darwin-arm64-cdb/libc-core-populate.sh
# → .ffi under ./Library/... or ./usr/...

cd $CCL
./darm64cl --no-init --batch < tools/darwin-arm64-cdb/parse-libc.lisp
# → darwin-arm64-headers/libc/new-*.cdb

$CCL/tools/darwin-arm64-cdb/install-new-cdb.sh \
  $CCL/darwin-arm64-headers/libc
```

Layout probe after install: `tools/darwin-cdb-stat-smoke.lisp`.

Full Cocoa / historical header lists still need a curated port of the
x86 `populate.sh` (many 10.11 paths are gone). See `doc/porting/darwin-cdb.md`.

**Important:** `parse-standard-ffi-files` calls `install-new-db-files`,
which replaces `*.cdb` in place (old → `*.cdb-BAK`). A core-only
populate therefore **shrinks** the libc database — back up first and
restore the bring-up copy until coverage is complete.
