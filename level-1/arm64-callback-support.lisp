;;; -*- Mode: Lisp; Package: CCL -*-
;;; ARM64-SPECIFIC — a callback trampoline is raw machine code, so the
;;; body is inherently per-ISA; no PPC64 or Clozure-WIP analog encoding
;;; exists (PPC64 `ba' / ARM32 `ldr pc,[pc,#-4]` — see below).
;;;
;;; arm64-callback-support.lisp — callback trampoline generator for Matt
;;; Emerson's upstream ARM64 (low-tag) design.
;;;
;;; ISA-specific by nature (the body is raw machine code): the LOGIC
;;; mirrors arm-callback-support.lisp:19 and x86-callback-support.lisp:21
;;; (allocate a callback pointer, stamp the callback index into the
;;; register the kernel's _SPcallback reads, jump there, make the stub
;;; executable, return the pointer).  PPC64 reaches the subprim with a
;;; `ba' absolute branch and ARM32 with an `ldr pc,[pc,#-4]' literal
;;; jump; neither encoding exists on AArch64, hence the x16 literal jump.
;;;
;;; Trampoline layout (32 bytes, entered by FOREIGN code under AAPCS64;
;;; x8 (indirect-result reg, caller-saved for our purposes — _SPcallback
;;; consumes it immediately) and x16 (IP0 scratch) are safe to clobber):
;;;
;;;    0: movz x8, #lo16(index)         ; unboxed callback index
;;;    4: movk x8, #hi16(index), lsl 16
;;;    8: ldr  x16, .+16                ; load _SPcallback address
;;;   12: br   x16                      ;   from the literal at +24
;;;   16: nop                           ; pad literal to 8-byte alignment
;;;   20: nop
;;;   24: .quad <_SPcallback kernel address>
;;;
;;; MATCHED PAIR: _SPcallback (upstream-port/lisp-kernel/spentry-E-ffi.s)
;;; reads the index from arg_w = x8 (`mov save0, arg_w`).  Change this
;;; generator and that entry together.

(in-package "CCL")

#+(and darwin-target arm64-target)
(defun %darwin-jit-write-protect (enabled)
  "Unused — WP stays in kernel C (darwin_arm64_jit_*). Kept so old
callers bind without error."
  (declare (ignore enabled))
  nil)

(defun make-callback-trampoline (index &optional info)
  (declare (ignorable info))
  (let* ((p (%allocate-callback-pointer 32))
         (addr (%lookup-subprim-address
                #.(arm64::subprimitive-offset ".SPcallback")))
         ;; Assemble into a heap u8 scratch, then C-blit into the MAP_JIT
         ;; callback page.  Never call pthread_jit_write_protect_np from
         ;; MAP_JIT-resident lisp — that makes the caller non-executable.
         (scratch (make-array 32 :element-type '(unsigned-byte 8)
                              :initial-element 0)))
    (with-macptrs ((s))
      (%vect-data-to-macptr scratch s)
      (setf (%get-unsigned-long s 0)          ; movz x8,#lo16(index)
            (logior #xd2800008 (ash (ldb (byte 16 0) index) 5))
            (%get-unsigned-long s 4)          ; movk x8,#hi16(index),lsl #16
            (logior #xf2a00008 (ash (ldb (byte 16 16) index) 5))
            (%get-unsigned-long s 8)  #x58000090   ; ldr x16,.+16
            (%get-unsigned-long s 12) #xd61f0200   ; br x16
            (%get-unsigned-long s 16) #xd503201f   ; nop
            (%get-unsigned-long s 20) #xd503201f   ; nop
            (%%get-unsigned-longlong s 24) addr)
      #+(and darwin-target arm64-target)
      (ff-call (foreign-symbol-address "darwin_arm64_jit_install_code")
               :address p
               :address s
               :unsigned-fullword 32
               :void)
      #-(and darwin-target arm64-target)
      (dotimes (i 32)
        (setf (%get-unsigned-byte p i) (%get-unsigned-byte s i))))
    ;; Non-Darwin: I/D-cache sync via kernel import.  Darwin path already
    ;; icaches inside jit_install_code.
    #-(and darwin-target arm64-target)
    (ff-call (%kernel-import #.arm64::kernel-import-makedataexecutable)
             :address p
             :unsigned-fullword 32
             :void)
    p))
