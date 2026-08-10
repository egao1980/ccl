;;;; Patch: ObjC send without APPLY + install Hemlock note* send stubs.
;;;; Usage: ./darm64cl --no-init --batch < tools/install-objc-send-nofapply.lisp
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)
(require "OBJC-SUPPORT")

(defun objc-method-signature-info (sig)
  (values
   (or (gethash sig *objc-method-signatures*)
       (let ((info (make-objc-method-signature-info :type-signature sig)))
         (setf (objc-method-signature-info-function info)
               (lambda (&rest args)
                 (declare (dynamic-extent args))
                 (let ((f (handler-case
                              (compile-send-function-for-signature sig)
                            (error (c)
                              (%objc-unsupported-send-stub sig c)))))
                   (setf (objc-method-signature-info-function info) f)
                   (%invoke-objc-send-function f (car args) (cadr args) (cddr args))))
               (objc-method-signature-info-super-function info)
               (lambda (&rest args)
                 (declare (dynamic-extent args))
                 (let ((f (handler-case
                              (%compile-send-function-for-signature sig t)
                            (error (c)
                              (declare (ignore c))
                              (lambda (&rest a)
                                (declare (ignore a))
                                (error "ObjC super-send for signature ~s not supported on this backend"
                                       sig))))))
                   (setf (objc-method-signature-info-super-function info) f)
                   (%invoke-objc-send-function f (car args) (cadr args) (cddr args))))
               (gethash sig *objc-method-signatures*) info)))))

(defun %install-compiled-send-for-signature (sig)
  "Compile SIG's send function and install it on all known method signature-infos."
  (let ((f (compile-send-function-for-signature sig)))
    (setf (objc-method-signature-info-function (objc-method-signature-info sig)) f)
    (when (boundp '*objc-message-info*)
      (maphash (lambda (name msg)
                 (declare (ignore name))
                 (dolist (m (append (objc-message-info-methods msg)
                                    (objc-message-info-protocol-methods msg)))
                   (let ((si (objc-method-info-signature-info m)))
                     (when (and si (equal sig (objc-method-signature-info-type-signature si)))
                       (setf (objc-method-signature-info-function si) f)))))
               *objc-message-info*))
    f))

(format t "~&patched objc-method-signature-info (no APPLY)~%")

(format t "~&saving darm64cl.image~%")
(save-application "darm64cl.image")
