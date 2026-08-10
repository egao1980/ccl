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
;;; Trampoline layout (32 bytes, entered by FOREIGN code under AAPCS64).
;;; Index goes in x9 — NOT x8 — so the caller's indirect-result pointer
;;; in x8 survives into .SPcallback (AAPCS64 memory returns).
;;;
;;;    0: movz x9, #lo16(index)         ; unboxed callback index
;;;    4: movk x9, #hi16(index), lsl 16
;;;    8: ldr  x16, .+16                ; load _SPcallback address
;;;   12: br   x16                      ;   from the literal at +24
;;;   16: nop                           ; pad literal to 8-byte alignment
;;;   20: nop
;;;   24: .quad <_SPcallback kernel address>
;;;
;;; MATCHED PAIR: _SPcallback (lisp-kernel/spentry-E-ffi.s) reads the
;;; index from x9 and spills the preserved x8 sret at CBF-16.

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
      ;; Rd=9 (x9): movz/movk base encodings end in 9, not 8 (x8).
      (setf (%get-unsigned-long s 0)          ; movz x9,#lo16(index)
            (logior #xd2800009 (ash (ldb (byte 16 0) index) 5))
            (%get-unsigned-long s 4)          ; movk x9,#hi16(index),lsl #16
            (logior #xf2a00009 (ash (ldb (byte 16 16) index) 5))
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

;;; Heaps baked before the x9-index trampoline change still have movz/movk
;;; Rd=x8.  .SPcallback reads the index from x9 and treats x8 as AAPCS64
;;; sret — so xcmain / %xerr-disp never run (process-interrupt silent;
;;; type UUOs SEGV).  Patch Rd bits in place; safe on already-x9 stubs.
(defun fix-arm64-callback-trampolines-for-x9 (&optional (verbose nil))
  (let ((fixed 0))
    (when (boundp '%pascal-functions%)
      (let ((pf %pascal-functions%))
        (when (vectorp pf)
          (dotimes (i (length pf))
            (let ((pfe (svref pf i)))
              (when (and (vectorp pfe) (pfe.routine-descriptor pfe))
                (let* ((p (pfe.routine-descriptor pfe))
                       (i0 (%get-unsigned-long p 0))
                       (i1 (%get-unsigned-long p 4))
                       (rd0 (logand i0 #x1f))
                       (rd1 (logand i1 #x1f)))
                  (when (or (eql rd0 8) (eql rd1 8))
                    (let* ((new0 (logior (logandc2 i0 #x1f) 9))
                           (new1 (logior (logandc2 i1 #x1f) 9))
                           (scratch (make-array 32
                                                :element-type '(unsigned-byte 8))))
                      (dotimes (b 32)
                        (setf (aref scratch b) (%get-unsigned-byte p b)))
                      (with-macptrs ((s))
                        (%vect-data-to-macptr scratch s)
                        (setf (%get-unsigned-long s 0) new0
                              (%get-unsigned-long s 4) new1)
                        #+(and darwin-target arm64-target)
                        (ff-call (foreign-symbol-address
                                  "darwin_arm64_jit_install_code")
                                 :address p
                                 :address s
                                 :unsigned-fullword 32
                                 :void)
                        #-(and darwin-target arm64-target)
                        (progn
                          (dotimes (b 32)
                            (setf (%get-unsigned-byte p b)
                                  (%get-unsigned-byte s b)))
                          (ff-call (%kernel-import
                                    #.arm64::kernel-import-makedataexecutable)
                                   :address p
                                   :unsigned-fullword 32
                                   :void)))
                      (incf fixed)
                      (when verbose
                        (format t "~&;; trampoline ~s: x8 → x9~%"
                                (pfe.sym pfe))))))))))))
    fixed))
