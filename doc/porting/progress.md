# Progress notes on an arm64 port


## August 2026 — unbiased + DUAL_MAP=0

* `darwinarm64-heap-exec-bias-p` stays `nil` (vinsns no longer overrides backend).
* Full cross-bootstrap + cold-load + `:purify t` produces an unbiased image.
* Kernel / `platform-darwinarm64.h` default `DARWIN_ARM64_DUAL_MAP=0`.
* Compiled `#_` / math / cocoa CDB / purify smokes green on DM=0.
* Interpreted `%ff-call` landed; frame re-establish after `_SPffcall` (needs
  image rebuild from boot after tip `3ba8197b`). Mid-session vinsns reload
  + `save-application` corrupts the image — always rebuild from bootstrap.
* **OBJC-SUPPORT + NSString smoke green** (surgical tip reload into image;
  `tools/darwin-objc-bridge-smoke.lisp`): skip `:variadic` for `objc_msgSend*`;
  aapcs64 N-word; exception globals via `%set-kernel-global-ptr-from-offset`;
  cocoa CDB shims (`YES`/`NO`, msgsend prototypes, `instancetype`/generics/
  `struct id`, NSConstantString); `initialized-nsobject-p` → `:objc_object`;
  soft `ns:protocol` printer when Protocol absent from modern objc-classes.cdb.
* **N-word/varargs ungated** (lazy `objc-method-signature-info` compile).
  ≤128-bit records expand to N× `:unsigned-doubleword`/`%%get-unsigned-longlong`
  (CCL x8664-shaped). `#/stringWithFormat:` (varargs) still SIGSEGVs.
* **substring heisenbug = Apple arm64 tagged pointers**, not N-word RA:
  `tagged-objc-instance-p` used x86 low-nibble test; arm64 uses bit 63.
  Short NSStrings failed `recognize-objc-object` all-or-nothing per process.
* **Bare `(require "OBJC-SUPPORT")` SIGSEGVs** on stale image; tip reload of
  `%ff-call` / `expand-ff-call` / expander / `aapcs64-ff-call` first → ~OK.
  Integrate via full unbiased rebuild (do not mid-session `save-application`).
  Still open: bake tip into image; Darwin variadic send; require residual
  flake; Protocol CDB inject.

## August 2026 — Darwin/arm64 boot image (egao1980)

Built `arm64-boot.image` via host CCL 1.13 (Rosetta) and got the native
kernel past image load into cold load.

### Bootstrap (host)

* Stock 1.13 lacks `aapcs64-ff-call` / `arm64-lap-function` nx1 hook —
  load arm64-branch `nxenv.lisp`, `backend.lisp`, `nx1.lisp` first
  (`tools/bootstrap-darwinarm64-boot.lisp`).
* **Must reload `acode-rewrite.lisp` after nxenv** — loading nxenv
  reassigns operator IDs; without reload, `aapcs64-ff-call` has no
  rewrite entry and `%setf-macptr` of `(ff-call … :address)` becomes
  `mov xN,rnil` (x23=`rnil`).
* `tools/xdarwinarm64.lisp` must load `compile-ccl.lisp` (not fasl) and
  patch arch `nil-value` to Darwin static layout.

### Kernel / image load (Darwin W^X + ASLR)

* Static/image bases cannot sit in low memory. Darwin uses
  `STATIC_BASE_ADDRESS=#x200000000`, `IMAGE_BASE=#x300000000000`
  (platform-darwinarm64.h + xarm64fasload darwin backend).
* File `mmap`+`MAP_FIXED` fails for nonzero file offsets → `MapFile`
  uses anon commit + `read` (Windows-style).
* Heap mapped RW (no RWX); do **not** RX-protect dynamic (needs stores).
* `mrs ctr_el0` SIGILL on Apple Silicon → `sys_icache_invalidate`.
* Darwin `arm64-trap-support` xp accessors use measured ucontext offsets
  (not Linux `mcontext.regs`).
* `%kernel-import` returns a **fixnum-locative** (raw addr, PPC-style);
  `_SPffcall` treats non-macptr bits as the entry point (fixed subtag
  compare to use `w2`, not stale `imm2`).
* JIT path (later): Apple `MAP_JIT` + `pthread_jit_write_protect_np` /
  `pthread_jit_write_with_callback_np` — same model as **LuaJIT /
  V8 / JSC / CPython copy-and-patch / PyPy / Wasmtime** (see
  `darwin.md` cross-runtime survey). CCL already wants a separate
  code-vector / MAP_JIT region on darwinarm64; do **not** MAP_JIT the
  mixed heap.

### Current status — cold load complete, REPL works

Past `expand-ff-call` / rwlock. `%walk-dynamic-area` fault was
**not** primarily the pre-trap clobber (still fixed): heap free zone
below `allocptr` contained image trailer magic `nepOILCMegam`
(LE swab of `OpenMCLImage`). Cause: Darwin `MapFile` read
OS-page-rounded (16KiB) nbytes from a 4KiB-padded section → pulled
next file bytes into the zero pad that `walk-dynamic-area` walks as
nil-conses toward the sentinel. Fix: commit 16KiB, read payload only.

**W^X bring-up:** dual-map RX alias at `VA+HEAP_EXEC_BIAS`
(`mach_vm_remap` + NX→RX redirect in `handle_protection_violation`).
Cold load then died executing the `rename-package` docstring: GC was
not updating RX-biased PC/LR/`savelr` locatives, so `RET` after
compaction landed in reused heap. Fix: unbias/rebias in
`mark_pc_root` / `locative_forwarding_address` / purify/impurify
locref paths (`arm64-gc.c`).

**Callbacks / MAP_JIT:** write fault at `0x3fdf` was failed RWX
`mmap` (−1) + `%inc-ptr` in `%make-executable-page`. Fix: `MAP_JIT`
(`#x0800`) + `pthread_jit_write_protect_np` when stamping trampolines
(`l1-callbacks.lisp`, `arm64-callback-support.lisp`).

**FFI load order:** `ffi-darwinarm64` `(require "FFI-LINUXARM64")`
fell back to `.lisp` → `parse-file-options-line` → `STRING-TRIM`
before `MISC`. Fix: cross-compile `ffi-linuxarm64.da64fsl` and
`bin-load-provide` it before darwin FFI in `l1-boot-2`.

**Milestone:** `./darm64cl --image-name arm64-boot.image` finishes
cold load and reaches the listener (`DarwinARM6464`). Smoke:
`(+ 1 2)` → 3, `(ash 1 40)` → 2^40, `:darwinarm64-target` in
`*features*`.

**W^X call tax (Aug 2026):** dual-map NX→RX redirect in the fault
handler made every lisp→lisp call cost one Mach signal (~1µs→ms).
Fix: add `HEAP_EXEC_BIAS` before `br`/`blr` to code-vectors in
`spentry-D` (`br_codevector`), `call/jump-known-{symbol,function}`
vinsns, and LAP `br-codevector`. After rebuild: funcall 1e6 ~2.5ms
(was ~3.2s); `format`/`make-hash-table` string keys / CLOS match
Rosetta. Rebuild: bootstrap boot image + `save-application` `:purify nil`.


Cross-runtime JIT survey (LuaJIT / V8 / JSC / CPython / PyPy) in
`darwin.md` — reinforces separate `AREA_CODE` + MAP_JIT, not mixed heap.

### Smoke

```
make -C lisp-kernel/darwinarm64
# host: arch -x86_64 ./dx86cl64 --no-init --batch < tools/bootstrap-darwinarm64-boot.lisp
./darm64cl --image-name arm64-boot.image
```

## August 2026 — Darwin/arm64 kernel scaffold (egao1980)

Started Apple Silicon kernel bring-up on top of the `arm64` branch
(Linux/arm64 already boots + ANSI green).

Added:

* `lisp-kernel/darwinarm64/Makefile` → builds `darm64cl` (ASLR, no pagezero)
* Expanded `platform-darwinarm64.h` (xp accessors, ABI shims)
* `lisp-kernel/arm64-darwin-mach.c` — full Mach exception server
  (UUOs via EXC_BAD_INSTRUCTION → synthetic ucontext → signal_handler)
* `darwin_sigreturn` in `arm64-asmutils.s`; Darwin `pseudo_sigreturn` is
  `udf #0` (re-enters Mach for `do_pseudo_sigreturn`)
* `tools/xdarwinarm64.lisp` (alias of the darwinarm64 cross-setup)

Dual-map: eager remap on (`DARWIN_ARM64_DUAL_MAP=1`); NX redirect
without remap-in-handler (fixed purified `#_` compile livelock).
Production `:purify t` + MAP_JIT runtime.  Smoke timeouts via
`tools/with-timeout`.  Still open: ASLR rnil-relative statics.
`_SPffcall` stack-arg SP bump (GPR 9+), Darwin variadic-on-stack
(`:variadic` sentinel), and Darwin natural-size packing for
non-variadic stack overflow landed.  MAP_JIT code heap + conditional
`HEAP_EXEC_BIAS` (IMAGE_BASE only) landed for runtime compile;
fasl cold-load still uses the dual-mapped heap (WP-off would NX
earlier MAP_JIT pages).  Mach exception ports are on
(`use_mach_exception_handling`).  Save policy remains `:purify nil`
(`tools/save-darwinarm64-image.lisp`) until dual-map is dropped.

## May 21 – June 23
I looked a bit at Manfred Bergmann’s code at
https://github.com/mdbergmann/ccl/tree/arm64-arch-foundation. This code is
a Claude-assisted port of CCL using high tags.  It cross-creates a
bootstrapping image and manages to start it and load several fasl files.
This is quite impressive.

After long consideration, I decided that using low tags like the existing
CCL ports is a better choice.  This is mainly due to risk that future
platforms will stop supporting the TBI (top byte ignore) feature that
the high tag scheme depends on.

I used the [ccl-ffigen](https://github.com/Clozure/ccl-ffigen) tool
to process `.h` files.  The `.ffi` files will need to be
translated by Lisp code into the `.cdb` files that the `#_` and `#$`
reader macros consult.

I wrote out a (low) tagging scheme based on the existing ports.  The
traditional multi-level tagging (tag/lisptag/fulltag) as seen on
ppc64 doesn't really fit, but that's not problematic.  Defined uvector
header subtags, too.  Defined register partitioning.  (Much of this is
found in the file `ccl:compiler;ARM64;arm64-arch.lisp`.)

The majority of the effort over the past few weeks went to the assembler.
Some design points:
 * table-driven, like on other ports (mdbergmann code is driven by code)
 * works by parsing the LAP notation, finding a list of instruction templates
 for the mnemonic in question, and matching the supplied operands with the
 patterns defined in the templates.
 * used Claude Code to generate the instruction templates, avoiding the
 need to type in instruction encodings from the ARM manual, or from binutils
 or LLVM.

The LAP interface is starting to work.  LAP macros work.  The early
milestone I mention on https://github.com/Clozure/ccl/wiki/ARM64-port-draft-milestones now works:

```
(let ((*target-backend* (find-backend :darwinarm64)))
  (%define-arm64-lap-function
   'fact
   '((let ((n arg_z))
       (check-nargs 1)
       @l0
       (cmp n (:$ 0))
       (b.ne @continue)
       (mov arg_z (:$ '1))
       (ret)
       @continue
       (build-lisp-frame imm0)
       (str arg_z (:@! vsp (:$ -8)))
       (sub arg_z arg_z (:$ '1))
       (b.lt @l0)
       (ldr arg_y (:@+ vsp (:$ 8)))
       (restore-lisp-frame)
       (call-subprim .SPbuiltin-times)))))
#<XFUNCTION #x30200224F28D>
?  (uvref * 1)
#<XCODE-VECTOR #x30200224F22D>
? (dotimes (i (uvsize *)) (format t "~&~d: #x~8,'0x" i (uvref * i)))
0: #xF10020DF
1: #x54000040
2: #x0000000F
3: #xF100019F
4: #x54000061
5: #xD280010C
6: #xD65F03C0
7: xD2800B40
8: #xA9BE67E0
9: #xA9017BE7
10: #xF81F8F2C
11: #xD100218C
12: #x54FFFEEB
13: #xF840872B
14: #xA9417BE7
15: #xF94007F9
16: #x910083FF
17: #x910676E0
18: #xD63F0000
NIL
?
```
The Lisp disassembler doesn't work yet, but an arm64 disassembler shows
the following:
```
 0: f10020df subs xzr, x6, #0x8, lsl #0
 4: 54000040 b.eq #0xc
 8: 0000000f udf #0xf
 c: f100019f subs xzr, x12, #0x0, lsl #0
10: 54000061 b.ne #0x1c
14: d280010c movz x12, #0x8, lsl #0
18: d65f03c0 ret x30
1c: d2800b40 movz x0, #0x5a, lsl #0
20: a9be67e0 stp x0, x25, [sp, #-0x20]!
24: a9017be7 stp x7, x30, [sp, #0x10]
28: f81f8f2c str x12, [x25, #-0x8]!
2c: d100218c sub x12, x12, #0x8, lsl #0
30: 54fffeeb b.lt #0xc
34: f840872b ldr x11, [x25], #0x8
38: a9417be7 ldp x7, x30, [sp, #0x10]
3c: f94007f9 ldr x25, [sp, #0x8]
40: 910083ff add sp, sp, #0x20, lsl #0
44: 910676e0 add x0, x23, #0x19d, lsl #0
48: d63f0000 blr x0
```
What this shows:
* LAP macros working (e.g., `check-nargs`, `build-lisp-frame`
* The assembler working and supporting various register names (e.g,
`arg_z`) and operand types
* Generation of a function object (well, an xfunction object, because
we're cross-compiling) with a code-vector object that contains the
machine instructions.

Coming up next: add support for arm64 vinsn notation; define arm64 visns;
start filling in the arm642.lisp file (which is essentially the compiler
backend & code generator).  When that starts working, we'll be able to
cross-compile simple lambdas.


# compiling simple lambdas

At this point, the assembler (and maybe the disassemler) works well
enough to define simple lap functions.
```
CCL> (let ((*target-backend* (find-backend :darwinarm64)))
  (%define-arm64-lap-function
   'foo
   '((let ((offset arg_z))
       (cmp nargs (:$ '3))
       (b.le @done)
       (sub imm0 nargs (:$ '3))
       (add vsp vsp imm0)
       @done
       (mov arg_z rnil)
       (ret)))))
#<XFUNCTION #x302001C7977D>
CCL> (arm64-disassemble-xfunction *)
  (udf (:$ 0))                                              ; 00000000
  (cmp nargs (:$ 24))                                       ; F10060DF
  (b.le L20)                                                ; 5400006D
  (sub imm0 nargs (:$ 24))                                  ; D10060C0
  (add vsp vsp imm0)                                        ; 8B000339
L20
  (mov arg_z rnil)                                          ; AA1703EC
  (ret)                                                     ; D65F03C0
NIL
CCL> 
```

The next step is to cross-compile simple lambdas. 

`(compile-named-function '(lambda (x) x) :target :darwinarm64)`

In order to proceed,
it's necessary to start filling out arm642.lisp, and defining some arm64
vinsns.

Do `(setq *arm642-debug-mask* 2)`, and when the minimum parts of arm642 are filled in, you'll get:
```
CCL> (compile-named-function '(lambda (x) x) :target :darwinarm64)

 vinsns for NIL (after generation)
#<@0 CHECK-EXACT-NARGS 1>
#<@0 SAVE-LISP-CONTEXT-NO-STACK-ARGS>
#<@0 VPUSH-REGISTER #<LREG 2 GPR [12]/LISP>>
#<@0 SAVE-NFP>
#<@0 RESTORE-NFP>
#<@0 POPJ>
```



# Calling functions

On a non-x86 port, there is a separate value stack and control stack.
The value stack is always unambiguously nodes, from top to bottom.

The control stack (which is typically the architectural stack pointer)
contains frames.  Non-leaf functions need to save a frame.  A leaf
function doesn't clobber its return address or reference any constants.
Building a frame is a multi-instruction sequence, and `pc_luser_xp()`
needs to recognize the case of building a frame on the control stack
and make it look like an atomic operation.

# Returning values

Single values are returned in `arg_z`.  Multiple values are returned
on the stack, in left-to-right order (i.e., for a stack that grows down,
the rightmost value is on the top of the stack).

# Calling external (foreign) functions

The register and stack usage conventions for lisp code and external
(or foreign) are completely different.  For arm64, the AAPCS64 document
describes the standard ABI.  Apple platforms diverge from the
standard ABI in a few places.  See https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms for information about that.

### ANSI suite green (post NX-bias) — remaining flakes fixed

* **`CCL.40055-3`**: test bug in ccl-tests — bare `require-type` read as
  `CL-TEST::REQUIRE-TYPE`. Fixed with `ccl:require-type` (see egao1980/ccl-tests).
* **`ENSURE-DIRECTORIES-EXIST.8`**: needs empty `scratch/`; `run-tests` now
  `rm -rf scratch` after `make clean`.
* **Intermittent SIGILL** (`Unhandled exception 4 … neither udf nor brk`) during
  monolithic `:compile t` runs: `arm64-lap-generate-code` never called
  `%make-code-executable` (ARM32/PPC/nfasload already did). Fresh codevectors
  could hit a stale I-cache line on the RX dual-map alias. Fixed in
  `compiler/ARM64/arm64-lap.lisp`. Also tear down RX alias in `UnCommitMemory`
  before replacing the RW mapping (`lisp-kernel/memory.c`).
* Verified: 6/6 consecutive full `run-tests` + ccl-specific group, 0 failures.

