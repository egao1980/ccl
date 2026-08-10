;;;; Bake instancetype init-keyword registration + no-APPLY init sends.
;;;;   ./darm64cl --no-init --batch < tools/bake-objc-init-keywords.lisp
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)
(require "OBJC-SUPPORT")
(use-interface-dir :cocoa)

(let* ((src (merge-pathnames "objc-bridge/objc-support.lisp" (ccl-directory)))
       (wanted '(objc-init-result-type-p process-init-message
                 send-init-message-for-class))
       (n 0))
  (with-open-file (s src)
    (loop for f = (read s nil s)
          until (eq f s)
          when (and (consp f) (eq (car f) 'defun) (member (cadr f) wanted))
          do (eval f) (incf n)))
  (format t "~&baked objc-support ~d~%" n))

(let* ((src (merge-pathnames "objc-bridge/objc-runtime.lisp" (ccl-directory)))
       (wanted '(send-objc-init-message))
       (n 0))
  (with-open-file (s src)
    (loop for f = (read s nil s)
          until (eq f s)
          when (and (consp f) (eq (car f) 'defun) (member (cadr f) wanted))
          do (eval f) (incf n)))
  (format t "~&baked objc-runtime ~d~%" n))

;; Re-scan init messages with instancetype acceptance.
(clrhash *class-init-keywords*)
(register-objc-init-messages)
(format t "~&ns-view with-frame registered=~s~%"
        (and (find :with-frame
                   (all-init-keywords-for-class (find-class 'ns:ns-view))
                   :key #'car :test #'member)
             t))

(objc:with-autorelease-pool
  (let* ((r (ns:make-ns-rect 10d0 20d0 30d0 40d0))
         (v (make-instance 'ns:ns-view :with-frame r))
         (f (#/frame v)))
    (assert (= 10d0 (ns:ns-rect-x f)))
    (assert (= 40d0 (ns:ns-rect-height f)))
    (format t "~&make-instance :with-frame ok~%")))

(format t "~&saving darm64cl.image~%")
(save-application "darm64cl.image")
