# Darwin arm64 port — current status

## Build

```text
cd lisp-kernel/darwinarm64 && make clean && make
./darm64cl --no-init
(rebuild-ccl :full t)
```

Verified on this tree:

| Check | Result |
|-------|--------|
| `(rebuild-ccl :full t)` twice (second without LAP preload) | OK — self-hosting |
| `tools/darwin-clean-build-smoke.lisp` | OK |
| Cocoa / ObjC (`require :cocoa`, `ns:ns-make-rect`) | OK |
| Math / FFI smokes (`tools/darwin-math-smoke.lisp`, `tools/darwin-interp-ff-call-smoke.lisp`) | OK |
| `ccl-tests` Rove suite | 244/244 |
| `test-ccl-and-suites` ANSI+CCL | 21920/21920 (~39s) |

Helper scripts (optional):

```bash
./tools/run-darwin-arm64-ci.sh          # smokes
./tools/run-darwin-arm64-test-suites.sh # ccl-tests + ANSI
```

## Architecture

- **Executable Lisp code** lives in a **MAP_JIT** private mapping (`darwin_arm64_set_code_heap` / `%allocate-code-vector`) — Darwin stand-in for `AREA_CODE`.
- **`:purify t` (default)** moves pure objects into `AREA_READONLY` as **RX**. The dynamic heap is never executable.
- **W^X:** only kernel C toggles write-protect (`darwin_arm64_jit_*`). Lisp must not call `DarwinProtectMemory` / `DarwinUnProtectMemory` for MAP_JIT pages.
- **Pure-page dirty under W^X:** first write → `mprotect(RW)`; NX fault on fetch in `AREA_READONLY` → `mprotect(RX)` and retry (`lisp-kernel/arm64-exceptions.c`). A **FATAL** NX fault means an attempt to execute from the RW **dynamic** heap.
- **`compile-file` always uses MAP_JIT** on native Darwin (`compiler/ARM64/arm64-lap.lisp`). Eval-when `:compile-toplevel` must run code while the file is compiling; heap code vectors are NX. Fasl dump only needs readable bytes.

## Layout

- Kernel target: `lisp-kernel/darwinarm64/` → `../../darm64cl`
- Headers: `platform-darwinarm64.h`, `darwinarm64/Makefile`
- Exceptions / W^X: `arm64-exceptions.c` (Darwin NX / pure-page RW↔RX)
- MAP_JIT helpers: `lisp-kernel/darwin_arm64_jit.c`, `level-0/ARM64/arm64-utils.lisp`
- Image dump: clear MAP_JIT macptrs before save; remmap on restart (`level-1/l1-readloop.lisp`, `level-1/l1-boot-2.lisp`)
- CDB / ObjC: `darwin-arm64-headers/` (see `doc/porting/darwin-cdb.md`)

## Follow-ups

- Upstream Clozure merge: reviewable PR against `Clozure/ccl` `arm64` with Darwin CI notes.

See also: `doc/porting/darwin.md`, `tools/PR-darwinarm64.md`.
