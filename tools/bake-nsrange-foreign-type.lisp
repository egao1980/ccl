;;;; Bake NSRange/NSRect typedef→record completion into darm64cl.image.
;;;;   ./darm64cl --no-init --batch < tools/bake-nsrange-foreign-type.lisp
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)
(require "OBJC-SUPPORT")
(use-interface-dir :cocoa)
(let* ((src (merge-pathnames "lib/foreign-types.lisp" (ccl-directory)))
       (wanted '(%adopt-typedef-record-layout ensure-foreign-type-bits
                 %foreign-record-via-typedef %foreign-type-or-record
                 %foreign-type-or-record-size))
       (n 0))
  (with-open-file (s src)
    (loop for f = (read s nil s)
          until (eq f s)
          when (and (consp f) (eq (car f) 'defun) (member (cadr f) wanted))
          do (eval f) (incf n)))
  (format t "~&baked ~d foreign-type helpers~%" n))
(assert (= 16 (%foreign-type-or-record-size '(:struct :<NSR>ange) :bytes)))
(assert (compile-send-function-for-signature
         '(:<NSR>ange :<NSR>ect (:* (:struct :<NST>ext<C>ontainer)))))
(assert (compile-send-function-for-signature
         '((:struct :<NSR>ange) :<NSR>ect (:* (:struct :<NST>ext<C>ontainer)))))
(format t "~&saving darm64cl.image~%")
(save-application "darm64cl.image")
