;;;; OPEN BUG reproducer: layout-sensitive heap corruption during Cocoa launch.
;;;;
;;;;   ./tools/run-darwin-ide-smoke.sh 240 tools/darwin-launch-layout-repro.lisp LAUNCH-LAYOUT-OK
;;;;
;;;; On affected image layouts this dies during (require "COCOA") with
;;;;   TYPE-ERROR: #<BOGUS object @ #x3020....DDEC> is not ... MACPTR
;;;;   in RELEASE-AUTORELEASE-POOL, process Initial(0)
;;;; i.e. an autorelease-pool macptr on the Initial thread becomes BOGUS
;;;; during application launch.  The same class of failure has been seen
;;;; as "can't determine class of object tag=4 typecode=76 bogus=T" on
;;;; fresh IDE instances, and as intermittent
;;;;   "GC: object ... claims 0x604....... suffix dnodes - corrupt uvector header"
;;;; kernel aborts during (rebuild-ccl :full t) / cocoa mini-app runs.
;;;;
;;;; Facts established so far (2026-08):
;;;;   * Deterministic for a given image + load sequence; ANY extra
;;;;     toplevel form before the defun below (or removing it) hides the
;;;;     bug — pure heap-layout sensitivity.
;;;;   * Not EGC-specific: (egc nil) and (egc t) prefixes both shift
;;;;     layout and hide it; explicit full GCs do not reproduce it.
;;;;   * Pools survive cross-thread GC hammering after launch: a pool
;;;;     created on Initial stays valid across 10 full GCs, and a pool
;;;;     local to Initial's stack survives GCs run from Initial.  The
;;;;     corruption happens only inside the launch window.
;;;;   * The BOGUS address's low 16 bits are stable (#x...DDEC) across
;;;;     ASLR runs — same object shape/offset within its segment.
;;;;
;;;; Next diagnostic step: lldb hardware watchpoint on the doomed
;;;; address (break at launch start, compute the address from the pool
;;;; allocation, watch for the stray write).  See doc/porting/darwin-cdb.md
;;;; for running darm64cl under lldb with Mach exceptions.

(in-package :ccl)
(defun %p (fmt &rest args) (apply #'format t fmt args) (terpri) (force-output))
(require "COCOA")
(timed-wait-on-semaphore gui::*cocoa-ide-finished-launching* 60)
(%p "cocoa up")
(%p "LAUNCH-LAYOUT-OK")
(#_exit 0)
