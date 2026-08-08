/* SPDX-License-Identifier: Apache-2.0 */

/*
 * Darwin/arm64 (Apple Silicon) platform header.
 *
 * Low-tag scheme matches linuxarm64 / compiler/ARM64.  Unlike
 * darwinx8664 we cannot reserve low memory with -pagezero_size (see
 * doc/porting/darwin.md); STATIC_BASE_ADDRESS in arm64-constants.h is
 * provisional and will need a register-relative (rnil) redesign.
 */

#define WORD_SIZE 64
#define PLATFORM_OS PLATFORM_OS_DARWIN
#define PLATFORM_CPU PLATFORM_CPU_ARM64
#define PLATFORM_WORD_SIZE PLATFORM_WORD_SIZE_64

#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif

#include <sys/signal.h>
#include <sys/ucontext.h>

typedef mcontext_t MCONTEXT_T;
typedef ucontext_t ExceptionInformation;
#define UC_MCONTEXT(UC) UC->uc_mcontext

#define MAXIMUM_MAPPABLE_MEMORY (512L<<30L)
/* Preferred image base; ASLR may relocate. Same provisional value as linuxarm64. */
#define IMAGE_BASE_ADDRESS 0x300000000000L

/*
 * Dual-map bias for W^X: lisp heap stays RW at its canonical VA;
 * mach_vm_remap creates an RX alias at VA+HEAP_EXEC_BIAS.  Instruction
 * fetches that NX-fault on the RW mapping are restarted at PC+bias
 * (handle_protection_violation).  Bias must preserve low tag bits
 * (fulltag-misc=12 code-vector entry points).
 *
 * Call sites only add HEAP_EXEC_BIAS when the code-vector VA is in the
 * IMAGE_BASE band (addr>>40 == 0x30).  MAP_JIT AREA_CODE allocations
 * and other non-heap RX regions use a plain br/blr.
 */
#ifndef HEAP_EXEC_BIAS
#define HEAP_EXEC_BIAS 0x004000000000ULL
#endif

#include "lisptypes.h"
#include "arm64-constants.h"

/*
 * Low addresses (0x12000 / 0x03fff000) cannot be MAP_FIXED on arm64
 * Darwin (EINVAL).  Use a high address that mmap FIXED RW accepts.
 * Must match xdump/xarm64fasload.lisp *darwinarm64-xload-backend*
 * :static-space-address and the arch nil-value patched in
 * tools/xdarwinarm64.lisp (nil = STATIC_BASE + 4K + fulltag_nil).
 */
#undef STATIC_BASE_ADDRESS
#define STATIC_BASE_ADDRESS 0x0000000200000000ULL

#ifndef TCR_BIAS
#define TCR_BIAS (0)
#endif

#ifndef unbound
#define unbound unbound_marker
#endif
#ifndef slot_unbound
#define slot_unbound slot_unbound_marker
#endif
#ifndef stack_alloc_marker
#define stack_alloc_marker SUBTAG(fulltag_imm_1, 6)
#endif

#ifndef ABI_VERSION_CURRENT
#define ABI_VERSION_MIN 1046
#define ABI_VERSION_CURRENT 1046
#define ABI_VERSION_MAX 1046
#endif

#ifndef lisp_frame_size
#define lisp_frame_size sizeof(lisp_frame)
#endif

#ifndef fixnum_bitmask
#define fixnum_bitmask(n)  (1LL<<((n)+fixnumshift))
#endif

#ifndef NSAVEREGS
#define NSAVEREGS 4
#endif

#ifndef subtag_single_float
#define subtag_single_float fulltag_single_float
#endif

/* is_node_fulltag: prefer gc.h's ARM64 definition when present. */

/* AArch64 instructions are 32-bit; also defined under DARWIN in arm64-exceptions.h. */
#ifndef __lisp_kernel_opcode_defined
#define __lisp_kernel_opcode_defined
typedef uint32_t opcode, *pc;
#endif

#define DARWIN_USE_PSEUDO_SIGRETURN 1

extern void darwin_sigreturn(ExceptionInformation *, unsigned);
extern natural os_major_version;

/* Unix-signal bring-up (no Mach exception server yet): handlers must
 * RETURN to _sigtramp, which calls __sigreturn with the kernel token.
 * Raw darwin_sigreturn() fails under SA_VALIDATE_SIGRETURN_FROM_SIGTRAMP
 * (default since Mojave) → Bug("sigreturn returned") → abort/134.
 * _sigtramp is also not an exported symbol on arm64, so the x86
 * darwin_sigaction() workaround cannot be linked.  Empty SIGRETURN
 * matches linuxarm64: rely on trampoline return.  Context updates
 * during suspend (GC) are in-place on the same ucontext. */
#define DarwinSigReturn(context) ((void)(context))
#define SIGRETURN(context) ((void)(context))

/* arm_thread_state64_t: __x[0..28], __fp, __lr, __sp, __pc, __cpsr, __flags */
#define xpGPRvector(x) ((natural *)(&(UC_MCONTEXT(x)->__ss.__x)))
#define xpGPR(x,gprno) (xpGPRvector(x)[gprno])
#define set_xpGPR(x,gpr,new) xpGPR((x),(gpr)) = (natural)(new)
#define xpSP(x) (UC_MCONTEXT(x)->__ss.__sp)
#define xpLR(x) (UC_MCONTEXT(x)->__ss.__lr)
#define xpPC(x) (*(pc *)&(UC_MCONTEXT(x)->__ss.__pc))
#define set_xpPC(x, new) (xpPC(x) = (pc)(new))
#define xpFaultAddress(x) (UC_MCONTEXT(x)->__es.__far)
#define xpPSR(x) (UC_MCONTEXT(x)->__ss.__cpsr)

#include <mach/mach.h>
#include <mach/mach_error.h>
#include <mach/machine/thread_state.h>
#include <mach/machine/thread_status.h>

#include "os-darwin.h"
