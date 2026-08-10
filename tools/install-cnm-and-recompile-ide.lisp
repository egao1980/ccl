;;;; Bake tip CNM helpers + tip objc:defmethod; delete IDE fasls for recompile.
;;;; Usage: ./darm64cl --no-init --batch < tools/install-cnm-and-recompile-ide.lisp
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)
(require "OBJC-SUPPORT")
(load "ccl:tools;cnm-funcall-defs.lisp")
(load "ccl:tools;patch-objc-defmethod-cnm.lisp")
(format t "~&tip CNM + objc:defmethod installed~%")

(dolist (name '("cocoa-window" "cocoa-listener" "cocoa-editor" "app-delegate"
                "hemlock-text" "cocoa-utils" "preferences" "search-files"
                "cocoa-doc" "cocoa-backtrace" "xinspector" "xapropos"
                "apropos-window" "asdf-browser" "hemlock-commands"
                "cocoa-typeout" "ide-application" "console-window"
                "file-dialogs" "menus" "start"))
  (dolist (p (directory (format nil "ccl:cocoa-ide;fasls;~a*.*" name)))
    (format t "~&deleting ~s~%" p)
    (ignore-errors (delete-file p))))

(format t "~&saving darm64cl.image~%")
(save-application "darm64cl.image")
