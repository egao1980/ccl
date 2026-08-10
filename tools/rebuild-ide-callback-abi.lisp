;;;; Prepend to IDE rebuild: tip callback ABI + force cocoa-editor recompile.
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)
(format t "~&;; loading tip callback generators~%")
(finish-output)
(load "ccl:lib;ffi-linuxarm64.lisp")
(load "ccl:lib;ffi-darwinarm64.lisp")
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
