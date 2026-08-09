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
  two-phase kernel `DUAL_MAP=1` → purify → `DUAL_MAP=0`; **native**
  `xload-level-0` (no Rosetta). Darwin nil lives on a dedicated
  `*darwinarm64-target-arch*` (`#x20000100b`); sharing linux
  `*arm64-target-arch*` (`#x1300b`) was the `%FIND-PKG` cold-load fault.
  Optional Rosetta fallback: `%darwinarm64-cross-xload-boot-image`.
- `compile-file` emits heap code-vectors (MAP_JIT is interactive-only): MAP_JIT
  uvectors are outside the lisp heap and do not fasl-dump.
- Host ensure: heap-install tip `arm64-lap`, then restore MAP_JIT alloc +
  `%enable-darwinarm64-map-jit-fasls` so `compile-ccl` loads fasls into
  MAP_JIT (no NX tax).
- Historical UDF (`insn 0x00000000` at `0x306…`): NX redirect into a
  **zeroed** `HEAP_EXEC_BIAS` RX alias while calling heap
  `ARM64-LAP-GENERATE-CODE`. Root cause was region-probe skip on stale RX
  pages (leading-word/memcmp can false-match on the udf#0 sentinel). Fix:
  always `mach_vm_remap` in `darwin_arm64_remap_exec_alias` (NX path stays
  redirect-only, so remap-every-fault cost does not return).
- `:full` reload: darwinarm64 cold-load/purify uses
  `tools/save-darwinarm64-image.lisp` with retries (MAP_JIT-heavy host
  occasionally glitched `run-program`/fork).

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
- [ ] Native `(rebuild-ccl :full t)` end-to-end (no Rosetta)
