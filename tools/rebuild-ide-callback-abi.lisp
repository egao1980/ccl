;;;; Prepend to IDE rebuild: tip callback ABI + force cocoa-editor recompile.
;;;; Includes x8 sret frame (CBF-16) + x9 trampoline index.
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil
      *cerror-on-constant-redefinition* nil)
(format t "~&;; tip callback-frame offsets + generators~%")
(finish-output)
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
;; Inspector DISASSEMBLE-LINES for arm64.
(compile-file "ccl:compiler;ARM64;arm64-disassemble.lisp"
              :output-file "ccl:bin;arm64-disassemble"
              :verbose t :print nil)
(load "ccl:bin;arm64-disassemble")
(assert (fboundp 'disassemble-lines))
(format t "~&;; disassemble-lines ok~%")
(finish-output)
;; Struct-returning ObjC IMPs must be re-expanded with tip generators.
(dolist (f '("cocoa-ide/fasls/cocoa-editor.da64fsl"
             "cocoa-ide/fasls/cocoa-listener.da64fsl"
             "cocoa-ide/fasls/xapropos.da64fsl"
             "cocoa-ide/fasls/hemlock-text.da64fsl"))
  (when (probe-file f)
    (delete-file f)
    (format t "~&;; deleted ~s~%" f)))
(finish-output)
(load "ccl:tools;rebuild-clozure-cl64-ide.lisp")
)
