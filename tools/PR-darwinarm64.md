## Summary

Darwin/arm64 (Apple Silicon) bring-up on `arm64`: W^X via MAP_JIT code
arena + purify RX, ObjC bridge, Apple AAPCS64 FFI, throw/uwp parity.

Stock path: `(rebuild-ccl :full t)`. Details: `doc/porting/progress.md`.

### Kernel / image
- Executable Lisp code in MAP_JIT (`darwin_arm64_set_code_heap` /
  `%allocate-code-vector`); `:purify t` → `AREA_READONLY` RX
- Dynamic heap never executable
- Pure-page dirty under W^X: write → RW; NX fetch in readonly → RX retry
- WP toggles only in kernel C (`darwin_arm64_jit_*`)
- Clear MAP_JIT macptrs before dumplisp; remmap on restart

### Compiler / fasl
- Native Darwin `compile-file` always MAP_JIT (eval-when must run; heap NX)
- Fasl dump only needs readable bytes

### ObjC / FFI
- Apple arm64 tagged pointers (bit 63) in `tagged-objc-instance-p`
- Darwin method varargs stack-only → `#/stringWithFormat:`
- `ns:protocol` via `%ensure-class-declaration` (+ CDB inject scaffolding)
- arm64 `%throw`, `%throwing-through-cleanup-p`, lazy callback trampoline /
  `objc-propagate-throw`
- Variadic / natural-size stack overflow packing (Darwin AAPCS64)

### Verification
```bash
cd lisp-kernel/darwinarm64 && make clean && make
./darm64cl --no-init
(rebuild-ccl :full t)          # twice for self-host proof

./tools/run-darwin-arm64-ci.sh
./tools/run-darwin-smoke.sh 120 tools/darwin-clean-build-smoke.lisp
# ccl-tests + ANSI suites: run from a ccl-tests checkout against ./darm64cl
```

Companion ccl-tests: https://github.com/egao1980/ccl-tests

## Test plan
- [x] `(rebuild-ccl :full t)` end-to-end
- [x] Self-host second full rebuild without LAP preload
- [x] Clean-build / math / cocoa / interp-ff-call smokes
- [x] `ccl-tests` 244/244
- [x] ANSI+CCL `test-ccl-and-suites` 21920/21920
- [ ] Upstream Clozure PR against `Clozure/ccl` `arm64` + Darwin CI notes
