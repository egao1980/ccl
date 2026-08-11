;;;; Patch x8→x9 callback trampolines in the running IDE heap and dump.
;;;; Does NOT recompile cocoa fasls (avoids the tip-FFI typing/GC regression).
;;;;
;;;; Load from a Listener that already has typing (pre-safe-rebake heap):
;;;;   (load "ccl:tools;patch-tramps-only-dump-ide.lisp")
;;;; Or type that form and Ctrl+Enter.
(in-package :ccl)

(setq *warn-if-redefine-kernel* nil
      *cerror-on-constant-redefinition* nil
      *outstanding-deferred-warnings* nil)

(load "ccl:level-1;arm64-callback-support.lisp")
(load "ccl:lib;dumplisp.lisp")

(let ((n (fix-arm64-callback-trampolines-for-x9 t)))
  (format t "~&;; fixed ~s trampoline(s) x8→x9~%" n)
  (force-output)
  (unless (plusp n)
    (warn "No x8 trampolines found (already x9, or empty %pascal-functions%).")))

(pushnew 'fix-arm64-callback-trampolines-for-x9 *restore-lisp-functions*)

#+arm64-target (setq *log-callback-errors* t)

(let* ((bundle (ensure-directory-pathname "ccl:Clozure CL64.app;"))
       (res-ccl (merge-pathnames ";Contents;Resources;ccl;" bundle))
       (live (make-pathname :name (standard-kernel-name) :type "image" :defaults res-ccl))
       (bak (make-pathname :defaults live :type "image.pre-tramp-only"))
       (tmp (make-pathname :defaults live :type "image.tramp-only"))
       (kernel-dst (make-pathname :name (standard-kernel-name) :type nil
                                  :defaults (merge-pathnames ";Contents;MacOS;" bundle))))
  (ensure-directories-exist live)
  (when (probe-file live)
    (copy-file live bak :if-exists :supersede)
    (format t "~&;; backed up live → ~s~%" bak)
    (force-output))
  (when (probe-file tmp) (delete-file tmp))
  (when (probe-file "ccl:darm64cl")
    (copy-file "ccl:darm64cl" kernel-dst :if-exists :supersede :preserve-attributes t)
    (format t "~&;; copied tip kernel~%")
    (force-output))
  (when (fboundp '%darwinarm64-register-code-heap)
    (%darwinarm64-register-code-heap)
    (format t "~&;; registered code heap~%")
    (force-output))
  (format t "~&;; save-application → ~s (via Initial; trampolines already x9)~%" tmp)
  (force-output)
  (let ((ide-class (or (find-class 'gui::cocoa-ide nil)
                       (find-class 'cocoa-ide nil))))
    (unless ide-class (error "cocoa-ide class missing"))
    ;; Does not return on success.  Requires working process-interrupt (x9).
    (save-application tmp
                      :application-class ide-class
                      :purify t)))
