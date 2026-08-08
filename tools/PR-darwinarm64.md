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
