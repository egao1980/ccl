;;;; Bake arm64 HFA callback unpacking + init-keyword fixes; force IDE
;;;; objc:defmethod recompile (NSRect HFAs) on next COCOA require.
;;;;   ./darm64cl --no-init --batch < tools/bake-callback-hfa.lisp
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)

(format t "~&;; compile ffi-linuxarm64~%")
(compile-file "ccl:lib;ffi-linuxarm64.lisp"
              :output-file "ccl:bin;ffi-linuxarm64"
              :verbose t :print nil)
(load "ccl:bin;ffi-linuxarm64")
(format t "~&;; tip generate-callback-bindings in image~%")

;; Init-keyword :instancetype + no-APPLY init sends (may already be baked).
(let* ((src (merge-pathnames "objc-bridge/objc-support.lisp" (ccl-directory)))
       (wanted '(objc-init-result-type-p process-init-message
                 send-init-message-for-class)))
  (with-open-file (s src)
    (loop for f = (read s nil s)
          until (eq f s)
          when (and (consp f) (eq (car f) 'defun) (member (cadr f) wanted))
          do (eval f))))
(let* ((src (merge-pathnames "objc-bridge/objc-runtime.lisp" (ccl-directory)))
       (wanted '(send-objc-init-message)))
  (with-open-file (s src)
    (loop for f = (read s nil s)
          until (eq f s)
          when (and (consp f) (eq (car f) 'defun) (member (cadr f) wanted))
          do (eval f))))
(clrhash *class-init-keywords*)
(register-objc-init-messages)

;; Force recompile of IDE methods that take NSRect/NSSize HFAs.
(dolist (name '("cocoa-editor" "cocoa-typeout" "hemlock-text"
                "preferences-views" "search-files" "cocoa-window"
                "cocoa-listener" "cocoa-doc" "cocoa-utils"
                "preferences" "hemlock-commands" "app-delegate"
                "menus" "start" "xinspector" "xapropos"
                "apropos-window" "cocoa-backtrace" "file-dialogs"
                "console-window" "ide-application" "asdf-browser"
                "processes-window" "inspector" "cocoa-grep"
                "cocoa-remote-lisp" "ide-self-update"
                "cocoa-editor" "hemlock"))
  (dolist (dir '("ccl:cocoa-ide;fasls;" "ccl:cocoa-ide;hemlock;fasls;"))
    (dolist (p (directory (format nil "~a~a*.*" dir name)))
      (format t "~&deleting ~s~%" p)
      (ignore-errors (delete-file p)))))

(format t "~&saving darm64cl.image~%")
(save-application "darm64cl.image")
