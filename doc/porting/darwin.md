# Darwin (macOS)

On arm64, macOS prevents us from having a static area at a fixed address.
On x86-64, we used the `pagezero_size` linker option to reserve some low
memory, but this no longer works.

> From https://forums.developer.apple.com/forums/thread/655950
> 
> "Modifying pagezero_size isn't a supportable option in the arm64
> environment. arm64 code must be in an ASLR binary, which using a
> custom pagezero_size is incompatible with. An ASLR binary encodes
> signed pointers using a large random size along with the expected
> page zero size, and this combination is going to extend beyond the
> range of values covered in the lower 32-bits. Further, even if
> that did work, 32-bit pointers are completely incompatible with
> the arm64e architecture, which is available as a preview
> technology.

On an arm64 Mac, building with something like
`cc -Wl,-pagezero_size,0x4000 -g foo.c`, seems to work, but it produces
a binary that won't run: "error: Malformed Mach-o file" is what
the debugger prints out.

On an Intel Mac, that same `cc -Wl,-pagezero_size,0x4000 -g foo.c`
does produce a working binary.

On other ports, `nil` is basically a really popular constant, and when
treated as a pointer, it refers to a fixed address in low-ish memory.
On an Apple Silicon Mac, it looks like we're going to have to keep `nil` in
a register (rnil) because we can't rely on having a fixed address for it.
This means we will access kernel globals and `nil`-relative symbols as
offsets from rnil.

## 16 KiB pages (Apple Silicon)

Intel macOS uses 4 KiB pages; Apple Silicon uses **16 KiB**
(`sysconf(_SC_PAGESIZE)` / `getpagesize()` → 16384).

`mprotect` / `mmap` require addresses and lengths aligned to the OS
page size. CCL historically hardcodes `log2_page_size = 12` in
`*-exceptions.c` and uses 4 KiB-oriented stack-guard sizes
(`CSTACK_SOFTPROT = 100<<10` = 102400, not a multiple of 16384).
That yields `mprotect` **EINVAL** and `Bug("couldn't protect …")`
during TCR/stack setup.

Workaround in this port:

* After `page_size = sysconf(_SC_PAGESIZE)`, set `log2_page_size`
  from the live page size (do not leave the 4 KiB default).
* Round stack soft/hard guard sizes up to `page_size` before
  `mprotect`.
* Heap **image files** remain 4 KiB-aligned on disk
  (`heap-image.lisp`); `seek_to_next_page` must keep using 4 KiB,
  not the OS page size.

## ARM ABI
Official ARM documentation: https://github.com/ARM-software/abi-aa

As permitted by the standard 64-bit ARM ABI, Apple reserves register x18.
(Linux apparently doesn't.)

The architectural stack pointer SP must be 16-byte aligned whenever it is
used to access memory.  This is hardware-enforced.
As a matter of ABI policy, SP must be 16-byte aligned at public
C function boundaries.

For example, here is a way to lose:
```
str x1, [sp, #-8]! ;OK, but sp now has only 8 byte alignment...
str x0, [sp, #-8]! ;... so this subsequent store fails
```

## MAP_JIT and the W^X policy
On arm64, macOS enforces a policy called W^X.  This means that a memory
region can be either writable or executable, but never both at the same
time.

Apple documents the accommodation for dynamic languages at
https://developer.apple.com/documentation/apple-silicon/porting-just-in-time-compilers-to-apple-silicon.

Practical constraints (also hit by SBCL, V8, OpenJDK, Firefox):

* Allocate code with `mmap(..., PROT_READ|PROT_WRITE|PROT_EXEC,
  MAP_PRIVATE|MAP_ANON|MAP_JIT, ...)`.  Despite RWX in the call, the
  region is **not** simultaneously writable and executable.
* Toggle with `pthread_jit_write_protect_np(0)` (write / not exec) and
  `pthread_jit_write_protect_np(1)` (exec / not write); then
  `sys_icache_invalidate`.
* Officially **one** `MAP_JIT` region per process (with Hardened
  Runtime + `com.apple.security.cs.allow-jit` when hardened).
* `MAP_JIT|MAP_FIXED` is rejected (EINVAL) — cannot pin the JIT region
  at `IMAGE_BASE_ADDRESS`.
* File-backed `mmap`+`MAP_FIXED` with a **nonzero file offset** also
  fails with EINVAL on arm64 Darwin; image load uses anon commit +
  `read` instead (same idea as the Windows `MapFile` path).
* `mrs ctr_el0` for I-cache line size SIGILLs at EL0 on Apple Silicon;
  use `sys_icache_invalidate` instead.

CCL traditionally mixes code and data in one dynamic area.  That fights
per-thread WP on a single MAP_JIT region (a store from RX code into the
same region needs RW).  Upstream direction (see Clozure/ccl#11 discussion):
a separate code area / code-vector slot (SBCL-style), not “MAP_JIT the
whole heap”.

**Bring-up lesson:** do **not** `mprotect` the whole dynamic area RX after
image load.  Boot code runs from pure/readonly (RX is fine there) and from
kernel subprims; heap stores (`SPgvset`, cons init) must keep dynamic RW.
With dynamic RX, `handle_alloc_trap` succeeds then `SPgvset` takes
`EXC_BAD_ACCESS` and cold-load misreports a nested “read” fault (Darwin
`si_code` ≠ Linux `SEGV_ACCERR` — use ESR.WnR).  Runtime mutation of
dynamic code still needs MAP_JIT / a separate code area.

## Workarounds researched (2026-08)

Sources: Clozure/ccl#11 (xrme / mdbergmann), Apple JIT porting guide + DTS,
SBCL `darwin-jit`, Clasp/V8/Wasmtime/Firefox, Kyle Avery JIT notes.

### W^X — do not MAP_JIT the mixed heap

Apple Silicon **never** allows simultaneous W+X (Hardened Runtime or not;
DTS: RWX is “inherently invalid”).  `pthread_jit_write_protect_np` is
per-thread for **all** `MAP_JIT` pages: RX to run a store, RW to commit
it — impossible if code and data share one JIT region → infinite fault
loop (mdbergmann on #11).

| Approach | Pros | Cons / notes |
| --- | --- | --- |
| **Separate `AREA_CODE` / code-vector** (SBCL-style) | Matches Apple + SBCL; WP only around compile/GC | Big allocator/GC change; may lose PC-relative constants (xrme). Prototype direction: `no-defun-allowed/ccl` |
| **`mach_vm_remap` dual map** | Same phys at RW VA + RX VA; no WP toggle | mdbergmann: worked past `l1-init` in one session; fragile; two VAs for every code page |
| **WP toggles in subprims only** | Small kernel change | Misses inline vinsn stores → incomplete |
| **Purify + native image** (xrme brainstorm) | Image code as Mach-O/ELF RX; `MAP_JIT` only for redefs | Save/merge story for dead code vectors |
| **Entitlements** (`allow-jit` / `allow-unsigned-executable-memory`) | Needed for hardened/signing; unsigned ad-hoc kernels often already get `MAP_JIT` | Do **not** restore true RWX on Apple Silicon; `disable-executable-page-protection` ≡ unsigned-exec there |

**Boot path (already):** map heap RW → fill → `mprotect` RX (page-aligned).
**Runtime compile:** needs one of the rows above before FASL redefine works.

Modern Apple docs push `pthread_jit_write_with_callback_np` + allowlist
(`jit-write-allowlist`); optional later hardening once a code area exists.

### UUO / SIGILL / Mach exceptions

CCL UUOs are `udf #n` → hardware `EXC_BAD_INSTRUCTION` → BSD `SIGILL`
(XNU `ux_exception.c`).

* **lldb:** stops on Mach exception and may never deliver `SIGILL`. Use
  `settings set platform.plugin.darwin.ignored-exceptions EXC_BAD_INSTRUCTION`
  (LLVM/lldb pattern) so the Unix handler runs.
* **Unix path (current Darwin arm64):** `use_mach_exception_handling = false`;
  accessors must be Darwin form `uc_mcontext->__ss.__pc` / `__x[]` /
  `__es.__far` (V8/Wasmtime), not Linux `mcontext.regs`. Lisp-side
  `arm64-trap-support` uses measured offsets; keep C macros in sync.
* **Nested fault:** if the handler reads a bad PC/context, cold load
  reports “unhandled read fault” instead of the UUO. Add a recursion
  guard (mdbergmann hit infinite handler re-entry). Prove `xpPC` with a
  tiny `udf` + dump in the handler before chasing Lisp bugs.
* **Mach path (x86 Darwin / mdbergmann):** port
  `associate_tcr_with_exception_port` / `mach_exc_server` from
  `x86-exceptions.c`, then flip `use_mach_exception_handling`. Better
  for allocation traps and W^X faults once dual-map/code-area lands.

### Fixed addresses / ASLR

* `-pagezero_size` is unsupported on arm64 (malformed Mach-O / ASLR).
* Provisional high FIXED RW bases work for bring-up; longer term:
  rnil-relative statics (darwin.md intro).
* `MAP_JIT|MAP_FIXED` → EINVAL: cannot pin JIT at `IMAGE_BASE`. Floating
  `MAP_JIT` + reloc, dual-map, or purify-into-Mach-O.

### Smaller Darwin arm64 landmines (status)

* **16 KiB pages:** derive `log2_page_size` from `sysconf`; round guards;
  keep **image file** seeks at 4 KiB; short `read` on MapFile OK.
* **File `mmap`+`MAP_FIXED`+nonzero offset:** EINVAL → anon + `read`.
* **`mrs ctr_el0`:** SIGILL → `sys_icache_invalidate`.
* **x18 reserved** (Apple AAPCS64); **SP 16-byte** hardware-aligned.
* **PAC:** strip only if ever on arm64e; plain arm64 PCs are fine.

## Current Darwin arm64 bring-up bases

Provisional fixed bases that `mmap` FIXED RW accepts (low addresses do
not):

* `STATIC_BASE_ADDRESS` = `#x200000000`
* `IMAGE_BASE_ADDRESS` = `#x300000000000`

Nil = static + 4 KiB + `fulltag_nil` (`#x20000100b`).  Longer term this
should move to rnil-relative addressing without fixed static VA.
