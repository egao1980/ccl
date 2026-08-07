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

;;; Return 7 values:
;;; A list of RLET bindings
;;; A list of LET* bindings
;;; A list of DYNAMIC-EXTENT declarations for the LET* bindings
;;; A list of initializaton forms for (some) structure args
;;; A FOREIGN-TYPE representing the "actual" return type.
;;; A form which can be used to initialize FP-ARGS-PTR, relative
;;;  to STACK-PTR. (This unused on some platforms.)
;;; The byte offset of the foreign return address, relative to STACK-PTR
(defun arm64-darwin::generate-callback-bindings (stack-ptr fp-args-ptr
                                                 argvars argspecs result-spec
                                                 struct-result-name)
  (declare (ignore stack-ptr fp-args-ptr argvars argspecs result-spec
                   struct-result-name))
  (error "arm64-darwin::generate-callback-bindings not yet implemented"))

(defun arm64-darwin::generate-callback-return-value (stack-ptr fp-args-ptr
                                                     result return-type
                                                     struct-return-arg)
  (declare (ignore stack-ptr fp-args-ptr result return-type struct-return-arg))
  (error "arm64-darwin::generate-callback-return-value not yet implemented"))
