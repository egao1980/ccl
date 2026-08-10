;;;; Safe IDE rebake: never truncate the live app image until dump succeeds.
;;;;
;;;;   ./tools/with-timeout 900 ./darm64cl --image-name ./darm64cl.image --no-init --batch \
;;;;     < tools/safe-rebake-ide.lisp
;;;;
;;;; Writes Clozure CL64.app/.../darm64cl.image.tip-new, then replaces the live
;;;; image only after a non-empty dump.  Registers MAP_JIT before :purify.
;;;; Patches x8→x9 callback trampolines so xcmain / errdisp work.
(in-package :ccl)

(setq *warn-if-redefine-kernel* nil
      *cerror-on-constant-redefinition* nil
      *outstanding-deferred-warnings* nil)

;; Tip save-application (Initial process-interrupt requires x9 trampolines).
(load "ccl:lib;dumplisp.lisp")

(defvar *cocoa-ide-path* "ccl:Clozure CL64.app;")
(defvar *cocoa-ide-copy-headers-p* nil)
(defvar *cocoa-ide-install-altconsole* nil)
(defvar *cocoa-ide-bundle-suffix*
  (multiple-value-bind (os bits cpu) (host-platform)
    (declare (ignore os))
    (format nil "Clozure CL-~a~a" (string-downcase cpu) bits)))
(defvar *cocoa-ide-force-compile* nil)
(defvar *cocoa-ide-frameworks* nil)
(defvar *cocoa-ide-libraries* nil)

(format t "~&;; safe-rebake-ide → ~s~%" *cocoa-ide-path*)
(force-output)

(assert (probe-file *cocoa-ide-path*) () "Bundle missing: ~s" *cocoa-ide-path*)

;; Tip callback ABI generators (match rebuild-ide-callback-abi.lisp).
(format t "~&;; tip callback-frame offsets + generators~%")
(force-output)
(eval '(defconstant arm64::callback-frame.fp-save-offset -80))
(eval '(defconstant arm64::callback-frame.sret-offset -16))
(eval '(defconstant arm64::callback-frame.savelr-offset -168))
(eval '(defconstant arm64::callback-frame.stack-args-offset 64))
(load "ccl:lib;ffi-linuxarm64.lisp")
(load "ccl:lib;ffi-darwinarm64.lisp")
(load "ccl:level-1;arm64-callback-support.lisp")
(setf (ftd-callback-bindings-function *target-ftd*)
      #'arm64-darwin::generate-callback-bindings)
(setf (ftd-callback-return-value-function *target-ftd*)
      #'arm64-darwin::generate-callback-return-value)
;; Patch heap trampolines before anything that needs process-interrupt / UUOs.
(format t "~&;; fixed ~s early trampoline(s)~%"
        (fix-arm64-callback-trampolines-for-x9 t))
(force-output)
(compile-file "ccl:compiler;ARM64;arm64-disassemble.lisp"
              :output-file "ccl:bin;arm64-disassemble"
              :verbose t :print nil)
(load "ccl:bin;arm64-disassemble")
(assert (fboundp 'disassemble-lines))

(dolist (f '("cocoa-ide/fasls/cocoa-editor.da64fsl"
             "cocoa-ide/fasls/cocoa-listener.da64fsl"
             "cocoa-ide/fasls/xapropos.da64fsl"
             "cocoa-ide/fasls/hemlock-text.da64fsl"
             "cocoa-ide/fasls/file-dialogs.da64fsl"
             "cocoa-ide/fasls/search-files.da64fsl"
             "cocoa-ide/fasls/start.da64fsl"))
  (when (probe-file f)
    (delete-file f)
    (format t "~&;; deleted ~s~%" f)))
(force-output)

(load "ccl:cocoa-ide;defsystem.lisp")
(load-ide *cocoa-ide-force-compile*)
(format t "~&;; load-ide done~%")
(force-output)
;; Cocoa/ObjC defcallbacks from the heap may still be x8-index trampolines.
(let ((n (fix-arm64-callback-trampolines-for-x9 t)))
  (format t "~&;; fixed ~s callback trampoline(s) for x9 index~%" n)
  (force-output))

#+arm64-target (setq *log-callback-errors* t)

(let* ((bundle (ensure-directory-pathname *cocoa-ide-path*))
       (res-ccl (merge-pathnames ";Contents;Resources;ccl;" bundle))
       (live (make-pathname :name (standard-kernel-name) :type "image"
                            :defaults res-ccl))
       (bak (make-pathname :defaults live :type "image.pre-safe-rebake"))
       (tmp (make-pathname :defaults live :type "image.tip-new"))
       (kernel-dst (make-pathname :name (standard-kernel-name) :type nil
                                  :defaults (merge-pathnames
                                             ";Contents;MacOS;" bundle))))
  (ensure-directories-exist live)
  (when (probe-file live)
    (copy-file live bak :if-exists :supersede)
    (format t "~&;; backed up live → ~s~%" bak)
    (force-output))
  (when (probe-file tmp)
    (delete-file tmp))
  (format t "~&;; copy kernel → ~s~%" kernel-dst)
  (force-output)
  (copy-file (kernel-path) kernel-dst :if-exists :supersede :preserve-attributes t)
  (when (fboundp '%darwinarm64-register-code-heap)
    (format t "~&;; %darwinarm64-register-code-heap~%")
    (force-output)
    (%darwinarm64-register-code-heap))
  (format t "~&;; save-application → ~s (purify t)~%" tmp)
  (force-output)
  (let ((ide-class (or (find-class 'gui::cocoa-ide nil)
                       (find-class 'cocoa-ide nil))))
    (unless ide-class
      (error "cocoa-ide class missing after load-ide"))
    (format t "~&;; application-class ~s~%" ide-class)
    (force-output)
    ;; Does not return on success.  :purify t is OK for GUI .app launch;
    ;; --batch --eval smoke against a cocoa-ide image is not (Initial runs
    ;; IDE toplevel and fights the eval).
    (save-application tmp
                      :application-class ide-class
                      :purify t)))
