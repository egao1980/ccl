;;; Cross-compile setup for Darwin/arm64 (Apple Silicon).
;;; Parallel to tools/xlinuxarm64.lisp; tools/xarm64.lisp is the older name.

(in-package "CCL")

(defpackage "ARM64-DARWIN" (:use))

(defun load-darwinarm64-backend ()
  ;; Load .lisp sources: a stock host image's compile-ccl fasl predates
  ;; *arm64-xload-modules* / darwinarm64 entries.  Caller should already
  ;; have loaded arm64-branch nxenv/backend/nx1 (see
  ;; tools/bootstrap-darwinarm64-boot.lisp).
  (in-development-mode
    (load "ccl:lib;systems.lisp")
    (load "ccl:lib;compile-ccl.lisp"))
  (update-modules '(arm64-arch arm64-asm arm64-lap arm64-backend
                    arm64-vinsns arm642)
                  t)
  (setup-arm64-ftd *darwinarm64-backend*)
  (update-modules '(arm64-lapmacros arm64-disassemble ffi-darwinarm64) t)
  (unless (boundp '*arm64-xload-modules*)
    (error "ccl:lib;compile-ccl.lisp did not define *arm64-xload-modules*"))
  (update-modules *arm64-xload-modules* t)
  ;; Shared *arm64-target-arch* defaults to linux-style nil at #x1300b.
  ;; Darwin static space lives at #x200000000 (see platform-darwinarm64.h).
  ;; fulltag-nil = #xb; nil = static + 4K + tag.
  (let* ((arch (backend-target-arch *darwinarm64-backend*))
         (nil-value #x20000100b))
    (setf (arch::target-nil-value arch) nil-value)
    (format t "~&;; darwinarm64 nil-value => #x~x~%" nil-value)))

(load-darwinarm64-backend)
