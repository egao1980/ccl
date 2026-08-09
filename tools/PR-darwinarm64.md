## Summary

Darwin/arm64 (Apple Silicon) bring-up on `arm64`: W^X/MAP_JIT, NX/I-cache
stability, ObjC bridge, and throw/uwp parity for callbacks.

### Kernel / image
- Unbiased heap (`darwinarm64-heap-exec-bias-p` nil); production `DUAL_MAP=0`
- `%make-code-executable` in LAP; RX alias teardown in `UnCommitMemory`
- NXArgv clear: `(:* (:* :char))` (was byte-index smash → Cocoa dlopen flake)

### ObjC / FFI
- Apple arm64 tagged pointers (bit 63) in `tagged-objc-instance-p`
- Darwin method varargs stack-only → `#/stringWithFormat:`
- `ns:protocol` via `%ensure-class-declaration` (+ CDB inject scaffolding)
- arm64 `%throw`, `%throwing-through-cleanup-p`, lazy callback trampoline /
  `objc-propagate-throw`

### Rebuild / MAP_JIT fasl notes
- Level-0 `$fasl-code-vector` uses MAP_JIT only when `*darwinarm64-map-jit-fasls*`
  is T (post-purify / saved image). Cold-load keeps code on the heap so purify
  works and lisp never toggles WP from MAP_JIT-resident code.
- `rebuild-ccl` on darwinarm64: tip LAP host install before `compile-ccl`;
  two-phase kernel `DUAL_MAP=1` → purify → `DUAL_MAP=0`; boot image via
  Rosetta `tools/bootstrap-darwinarm64-boot.lisp` (native `xload-level-0`
  still cold-load faults in `%FIND-PKG` — open).
- `compile-file` emits heap code-vectors (MAP_JIT is interactive-only): MAP_JIT
  uvectors are outside the lisp heap and do not fasl-dump.
- Host ensure: heap-install tip `arm64-lap` (MAP_JIT uvectors do not
  fasl-dump / used to UDF when tip LAP lived wrongly), then restore MAP_JIT
  alloc + `%enable-darwinarm64-map-jit-fasls` so `compile-ccl` loads fasls
  into MAP_JIT (no NX tax). Verified: wiped `(compile-ccl t)` ~23s, no UDF.
- Historical UDF (`insn 0x00000000` at `0x306…`): NX redirect into a
  **zeroed** `HEAP_EXEC_BIAS` RX alias while calling `ARM64-LAP-GENERATE-CODE`
  on the impure heap — not the MAP_JIT arena. Remap probe now requires the
  first word at bias to match canonical before skipping `mach_vm_remap`.

### Verification
- Surgical: `tools/darwin-open-issues-smoke.lisp`, `tools/throwing-cleanup-smoke.lisp`
- **Clean bake (required before merge):**
  ```bash
  ./tools/rebuild-darwinarm64-unbiased.sh
  # ends with tools/darwin-clean-build-smoke.lisp (no surgical reload)
  ```
- Optional: full ANSI / `run-tests` on the new image

Companion ccl-tests: https://github.com/egao1980/ccl-tests/pull/1

## Test plan
- [x] Surgical open-issue / throwing smokes on tip source
- [ ] `./tools/rebuild-darwinarm64-unbiased.sh` → `DARWIN-ARM64-UNBIASED-REBUILD-OK`
- [ ] Bare `(require "OBJC-SUPPORT")` — no Undefined `%THROW` warnings
- [ ] Optional: ANSI + CCL tests on purified tip image
- [ ] Native `(rebuild-ccl :full t)` end-to-end (blocked: acode-rewrite UDF)
