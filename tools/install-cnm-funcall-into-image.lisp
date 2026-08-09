;;;; Install tip %call-next-objc-method (funcall-by-arity) into darm64cl.image.
;;;; Usage: ./darm64cl --no-init --batch < tools/install-cnm-funcall-into-image.lisp
(in-package :ccl)
(require "OBJC-SUPPORT")
(load "ccl:tools;cnm-funcall-defs.lisp")
(format t "~&installed %invoke-objc-send-function / %call-next-objc-method~%")
(save-application "darm64cl.image")
