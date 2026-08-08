;;;; -*- Mode: Lisp; Package: CCL -*-
;;;;
;;;; SPDX-License-Identifier: Apache-2.0

(in-package "CCL")

;;; Darwin varies from the standard 64-ARM ABI in a few small ways.
;;; https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms
;;;
;;; Critical: ff-call macroexpansion uses (ftd-ff-call-expand-function
;;; *target-ftd*).  An empty expand-ff-call returns NIL, so every
;;; (ff-call …) under the Darwin FTD became literal NIL — cold-load
;;; %MAKE-RWLOCK-PTR then did `mov xN,rnil` + trap-unless-macptr.

;;; Reuse Linux AAPCS64 callback generators until Darwin-specific
;;; packing is wired.  Fixed-arity stack overflow (GPR 9+) is handled
;;; by _SPffcall + arm642-aapcs64-ff-call.  Still TODO here: Apple
;;; variadic-on-stack (all `...` args on the stack; needs prototype /
;;; CDB) and natural-size stack packing for odd-sized non-variadic
;;; overflow.  Ensures ARM64-LINUX package + definitions exist when
;;; only Darwin is loaded.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "ARM64-LINUX")
    (make-package "ARM64-LINUX" :use '("CL" "CCL")))
  (require "FFI-LINUXARM64"))

(defun arm64-darwin::record-type-returns-structure-as-first-arg (rtype)
  (arm64::record-type-returns-structure-as-first-arg rtype))

(defun arm64-darwin::expand-ff-call (callform args
                                     &key
                                       (arg-coerce
                                        #'null-coerce-foreign-arg)
                                       (result-coerce
                                        #'null-coerce-foreign-result))
  ;; Shared AAPCS64 path for now.  Darwin-only: variadic args all on
  ;; stack, natural-size stack packing, signed-char — needed for libc
  ;; varargs later; kernel-import cold-load calls are fixed-arity.
  (arm64::expand-ff-call callform args
                         :arg-coerce arg-coerce
                         :result-coerce result-coerce))

(defun arm64-darwin::generate-callback-bindings (stack-ptr fp-args-ptr
                                                 argvars argspecs result-spec
                                                 struct-result-name)
  (arm64-linux::generate-callback-bindings
   stack-ptr fp-args-ptr argvars argspecs result-spec struct-result-name))

(defun arm64-darwin::generate-callback-return-value (stack-ptr fp-args-ptr
                                                     result return-type
                                                     struct-return-arg)
  (arm64-linux::generate-callback-return-value
   stack-ptr fp-args-ptr result return-type struct-return-arg))
