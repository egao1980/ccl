;;;-*- Mode: Lisp; Package: CCL -*-
;;;
;;; Copyright 2026 (CCL ARM64 port)
;;; Based on vendor/ccl/lib/ffi-linuxppc64.lisp (Copyright 2007-2009 Clozure Associates)
;;;
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;     http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

;;; Shared AAPCS64 FFI support for the arm64 targets (Linux and Darwin).
;;; The OS-specific files (ffi-linuxarm64.lisp / ffi-darwinarm64.lisp)
;;; define only the four FTD entry points as thin delegators into this
;;; file; OS differences (Darwin variadic-on-stack, natural-size stack
;;; packing) are handled in the compiler (arm642-aapcs64-ff-call) keyed
;;; on the target OS, not by divergent copies of this logic.
;;;
;;; AAPCS64 reference summary (per IHI 0055C, §5-§6):
;;;   - X0..X7   : integer/pointer args (8 GPR slots); return in X0..X1
;;;   - V0..V7   : SIMD&FP args (8 VFP slots); return in V0..V1
;;;   - X8       : indirect-result-area pointer (caller-allocated buffer
;;;                when return is a composite > 16 bytes)
;;;   - X19..X28 : callee-save; X29 frame pointer; X30 link register
;;;   - SP       : 16-byte aligned at public boundaries
;;;
;;; Composite argument rules (AAPCS64 §6.8): HFAs of 1-4 identical
;;; float/double leaves go to V regs (all-or-nothing); other composites
;;; <= 16 bytes go to 1-2 GPRs (all-or-nothing); larger composites are
;;; passed by reference.  Returns (§6.9): HFA in v0..vN, <=16B in X0/X1,
;;; larger through the X8 indirect result buffer.
;;;
;;; Classification + expand-ff-call live in arm64-backend.lisp
;;; (arm64::classify-record-return / arm64::record-hfa-info /
;;; arm64::expand-ff-call).

(in-package "CCL")

;;;-----------------------------------------------------------------------
;;; generate-callback-bindings
;;;-----------------------------------------------------------------------
;;; PPC64 LINE-PORT (vendor/ccl/lib/ffi-linuxppc64.lisp:81-175) against
;;; the callback-frame contract (arm64-arch.lisp callback-frame.*; built
;;; by .SPcallback, lisp-kernel/spentry-E-ffi.s).
;;; stack-ptr = CBF: x0..x7 saves at +0..56, the C caller's stack args
;;; CONTIGUOUS at +64, x8 sret spill at -16, d0..d7 saves at -80..-24,
;;; saved LR at -168 (arm64-arch.lisp callback-frame.*).
;;;
;;; ARM64-DEVIATIONs from the PPC64 source:
;;;  - 8 FP arg regs (d0..d7), not PowerOpen's 13 (f1..f13).
;;;  - an FP register arg consumes NO slot in the linear gpr/stack
;;;    offset stream: delta = 0 when the arg lands in d0..d7.
;;;  - little-endian: sub-word integers read at bias 0.
;;;  - single-float register args were saved as the d-register's low 64
;;;    bits: plain %get-single-float at the slot base.
;;;  - records (non-HFA): <=64 bits arrive in one GPR slot, read
;;;    low-justified; 65..128 bits inline in two slots; >128 bits arrive
;;;    BY REFERENCE in one GPR (AAPCS64 B.4).
;;;  - records (HFA): 1..4 homogeneous float/double leaves arrive in
;;;    consecutive V regs (NSPoint/NSSize/NSRect/CGRect), unpacked from
;;;    the FP save area.
;;;    KNOWN GAP: an HFA that does not fit in the remaining V regs
;;;    should spill wholly to the stack; we signal an error (no known
;;;    callback signature overflows V0..V7 with an HFA).
;;;  - KNOWN GAP: a 9..16-byte non-HFA record with exactly one GPR left
;;;    goes wholly to the stack under AAPCS64 (no register/stack split);
;;;    this generator would read it one slot early.  No boot-path
;;;    callback has such a signature.
(defun arm64::generate-callback-bindings (stack-ptr fp-args-ptr argvars argspecs result-spec struct-result-name)
  (collect ((lets)
            (rlets)
            (inits)
            (dynamic-extent-names))
    (let* ((rtype (parse-foreign-type result-spec))
           (fp-regs-form nil))
      (flet ((set-fp-regs-form ()
               (unless fp-regs-form
                 (setq fp-regs-form `(%inc-ptr ,stack-ptr ,arm64::callback-frame.fp-save-offset)))))
        ;; AAPCS64 composite returns (mirror expand-ff-call / x8664 callbacks):
        ;;   :memory → indirect result in x8; trampoline preserves x8, kernel
        ;;             spills it at CBF-16 (callback-frame.sret-offset).
        ;;   :gpr/:hfa → value in x0/x1 or v0..vN; allocate a local record and
        ;;             copy out in generate-callback-return-value.  NEVER treat
        ;;             x0 as a stret pointer.
        (when (typep rtype 'foreign-record-type)
          (let ((class (arm64::classify-record-return rtype)))
            (ecase class
              (:memory
               ;; Bind the caller's sret buffer; do not shift real args.
               (lets (list struct-result-name
                           `(%get-ptr ,stack-ptr ,arm64::callback-frame.sret-offset)))
               (setq rtype *void-foreign-type*))
              ((:gpr :hfa)
               ;; Local result buffer; copy into CBF GPRs / V saves on exit.
               (rlets (list struct-result-name
                            (or (foreign-record-type-name rtype)
                                (unparse-foreign-type rtype))))
               ;; HFA return writes d0..dN via fp-args-ptr even if no FP args.
               (when (eq class :hfa)
                 (set-fp-regs-form))))))
        (when (typep rtype 'foreign-float-type)
          (set-fp-regs-form))
        (do* ((argvars argvars (cdr argvars))
              (argspecs argspecs (cdr argspecs))
              (fp-arg-num 0)
              (offset 0 (+ offset delta))
              (delta 8 8)
              (bias 0 0)
              (use-fp-args nil nil))
             ((null argvars)
              (values (rlets) (lets) (dynamic-extent-names) (inits) rtype fp-regs-form
                      arm64::callback-frame.savelr-offset))
          (let* ((name (car argvars))
                 (spec (car argspecs))
                 (argtype (parse-foreign-type spec))
                 (bits (ensure-foreign-type-bits argtype)))
            (multiple-value-bind (hfa-rep hfa-count)
                (if (typep argtype 'foreign-record-type)
                  (arm64::record-hfa-info argtype)
                  (values nil nil))
              (cond
                ;; AAPCS64 HFA arg: unpack V-reg saves into a local record.
                (hfa-rep
                 (setq delta 0)
                 (unless (<= (+ fp-arg-num hfa-count) 8)
                   (error "arm64 callback: HFA ~s needs ~d V regs but only ~d remain"
                          (unparse-foreign-type argtype)
                          hfa-count
                          (- 8 fp-arg-num)))
                 (when name
                   (let* ((rname (or (foreign-record-type-name argtype)
                                     (unparse-foreign-type argtype)))
                          (leaves (arm64::hfa-leaf-reps argtype))
                          (getter (if (eq hfa-rep :double-float)
                                    '%get-double-float
                                    '%get-single-float)))
                     (rlets (list name rname))
                     (set-fp-regs-form)
                     (dotimes (i hfa-count)
                       (let* ((leaf (nth i leaves))
                              (dst-off (cdr leaf)))
                         (incf fp-arg-num)
                         (inits `(setf (,getter ,name ,dst-off)
                                       (,getter ,fp-args-ptr
                                                ,(* 8 (1- fp-arg-num))))))))))
                ;; Non-HFA <=64-bit record in one GPR.
                ((and (typep argtype 'foreign-record-type)
                      (<= bits 64))
                 (when name (rlets (list name (foreign-record-type-name argtype))))
                 ;; ARM64-DEVIATION (LE): copy the slot verbatim — the value
                 ;; is low-justified in its doubleword.
                 (when name (inits `(setf (%%get-unsigned-longlong ,name 0)
                                     (%%get-unsigned-longlong ,stack-ptr ,offset)))))
                (t
                 (let* ((access-form
                         `(,(cond
                             ((typep argtype 'foreign-single-float-type)
                              (when (< (incf fp-arg-num) 9)
                                (setq use-fp-args t
                                      delta 0))
                              '%get-single-float)
                             ((typep argtype 'foreign-double-float-type)
                              (when (< (incf fp-arg-num) 9)
                                (setq use-fp-args t
                                      delta 0))
                              '%get-double-float)
                             ((and (typep argtype 'foreign-integer-type)
                                   (= (foreign-integer-type-bits argtype) 64)
                                   (foreign-integer-type-signed argtype))
                              '%%get-signed-longlong)
                             ((and (typep argtype 'foreign-integer-type)
                                   (= (foreign-integer-type-bits argtype) 64)
                                   (not (foreign-integer-type-signed argtype)))
                              '%%get-unsigned-longlong)
                             ((or (typep argtype 'foreign-pointer-type)
                                  (typep argtype 'foreign-array-type))
                              '%get-ptr)
                             ((typep argtype 'foreign-record-type)
                              (if (<= bits 128)
                                (progn
                                  (setq delta 16)
                                  '%inc-ptr)
                                ;; Non-HFA >128-bit records arrive by
                                ;; reference (AAPCS64 B.4).
                                '%get-ptr))
                             (t
                              (cond ((typep argtype 'foreign-integer-type)
                                     (let* ((bits (foreign-integer-type-bits argtype))
                                            (signed (foreign-integer-type-signed argtype)))
                                       ;; ARM64-DEVIATION (LE): bias 0 for all
                                       ;; sub-word widths.
                                       (cond ((<= bits 8)
                                              (if signed
                                                '%get-signed-byte
                                                '%get-unsigned-byte))
                                             ((<= bits 16)
                                              (if signed
                                                '%get-signed-word
                                                '%get-unsigned-word))
                                             ((<= bits 32)
                                              (if signed
                                                '%get-signed-long
                                                '%get-unsigned-long))
                                             (t
                                              (error "Don't know how to access foreign argument of type ~s" (unparse-foreign-type argtype))))))
                                    (t
                                     (error "Don't know how to access foreign argument of type ~s" (unparse-foreign-type argtype))))))
                           ,(if use-fp-args fp-args-ptr stack-ptr)
                           ,(if use-fp-args (* 8 (1- fp-arg-num))
                                `(+ ,offset ,bias)))))
                   (when name (lets (list name access-form)))
                   (when use-fp-args (set-fp-regs-form))))))))))))

;;;-----------------------------------------------------------------------
;;; generate-callback-return-value
;;;-----------------------------------------------------------------------
;;; Kernel .SPcallback reloads x0/x1 from CBF+0/+8 and d0..d7 from CBF-80
;;; on exit.  Write scalar / register-returned composites into that area.
;;;
;;; ARM64-DEVIATION vs PPC64: singles are float bits in the d0 slot (s0),
;;; not double-extended.  Record returns use classify-record-return
;;; (:gpr / :hfa); :memory already wrote through the sret pointer and
;;; arrives here as :void.
(defun arm64::generate-callback-return-value (stack-ptr fp-args-ptr result return-type struct-return-arg)
  (cond
    ((typep return-type 'foreign-record-type)
     (let* ((class (arm64::classify-record-return return-type)))
       (ecase class
         (:gpr
          (let* ((bits (ensure-foreign-type-bits return-type))
                 (nbytes (ash (+ bits 7) -3)))
            ;; 32-bit chunks — same as struct-from-regbuf-values.
            (collect ((forms))
              (do* ((b 0 (+ b 4)))
                   ((>= b nbytes))
                (forms `(setf (%get-unsigned-long ,stack-ptr ,b)
                              (%get-unsigned-long ,struct-return-arg ,b))))
              `(progn ,@(forms)))))
         (:hfa
          (multiple-value-bind (rep count)
              (arm64::record-hfa-info return-type)
            (let* ((leaves (arm64::hfa-leaf-reps return-type))
                   (getter (if (eq rep :double-float)
                             '%get-double-float
                             '%get-single-float)))
              (collect ((forms))
                (dotimes (i count)
                  (let* ((byte-off (cdr (nth i leaves))))
                    (forms `(setf (,getter ,fp-args-ptr ,(* i 8))
                                  (,getter ,struct-return-arg ,byte-off)))))
                `(progn ,@(forms))))))
         (:memory
          ;; Bound as void; nothing to store.
          nil))))
    ((eq return-type *void-foreign-type*)
     nil)
    (t
     (let* ((return-type-keyword (foreign-type-to-representation-type return-type)))
       (case return-type-keyword
         (:single-float
          `(setf (%get-single-float ,fp-args-ptr 0) ,result))
         (:double-float
          `(setf (%get-double-float ,fp-args-ptr 0) ,result))
         (:address
          `(setf (%get-ptr ,stack-ptr 0) ,result))
         (:signed-doubleword
          `(setf (%%get-signed-longlong ,stack-ptr 0) ,result))
         (:unsigned-doubleword
          `(setf (%%get-unsigned-longlong ,stack-ptr 0) ,result))
         (t
          `(setf (%%get-signed-longlong ,stack-ptr 0) ,result)))))))

(provide "FFI-ARM64")
