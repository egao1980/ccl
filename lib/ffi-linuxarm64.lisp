;;;-*- Mode: Lisp; Package: CCL -*-
;;;
;;; Copyright 2026 (CCL ARM64 port)
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

;;; Linux arm64 FTD entry points.  All AAPCS64 logic is shared with
;;; Darwin and lives in lib/ffi-arm64.lisp (callback generators) and
;;; compiler/ARM64/arm64-backend.lisp (classification + expand-ff-call).

(in-package "CCL")

;;; The ARM64-LINUX package holds the four FTD entrypoints consumed by
;;; foreign-types.lisp / nfcomp.lisp's %with-cross-compilation-target.
;;;
;;; The name of the architecture is arm64.  The 64-bit nature is implied.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package "ARM64-LINUX")
    (make-package "ARM64-LINUX" :use '("CL" "CCL")))
  (require "FFI-ARM64"))

(defun arm64-linux::record-type-returns-structure-as-first-arg (rtype)
  (arm64::record-type-returns-structure-as-first-arg rtype))

(defun arm64-linux::expand-ff-call (callform args &key (arg-coerce #'null-coerce-foreign-arg) (result-coerce #'null-coerce-foreign-result))
  (arm64::expand-ff-call callform args
                         :arg-coerce arg-coerce
                         :result-coerce result-coerce))

(defun arm64-linux::generate-callback-bindings (stack-ptr fp-args-ptr argvars argspecs result-spec struct-result-name)
  (arm64::generate-callback-bindings
   stack-ptr fp-args-ptr argvars argspecs result-spec struct-result-name))

(defun arm64-linux::generate-callback-return-value (stack-ptr fp-args-ptr result return-type struct-return-arg)
  (arm64::generate-callback-return-value
   stack-ptr fp-args-ptr result return-type struct-return-arg))
