;;;; Darwin/arm64: ObjC Lisp #/init + call-next-method smoke.
;;;; Requires tip %throwing-through-cleanup-p + split-frame %call-next-objc-method.
;;;;
;;;;   ./darm64cl --no-init --batch < tools/darwin-objc-call-next-smoke.lisp
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)

(unless (fboundp '%throwing-through-cleanup-p)
  (error "missing %throwing-through-cleanup-p"))

(require "OBJC-SUPPORT")

;; Compiled normal UWP must not look like a throw (propagate-throw false positive).
(defun %cnm-smoke-uwp ()
  (unwind-protect 'ok
    (when (%throwing-through-cleanup-p)
      (error "compiled normal uwp falsely throwing: ~s"
             (%throwing-through-cleanup-p)))))
(%cnm-smoke-uwp)
(format t "~&compiled-normal-uwp=NIL~%")

(defclass cnm-smoke (ns:ns-object) () (:metaclass ns:+ns-object))
(objc:defmethod #/init ((self cnm-smoke))
  (call-next-method))

(let ((o (make-instance 'cnm-smoke)))
  (format t "~&cnm-init => ~s~%" o)
  (unless (typep o 'cnm-smoke)
    (error "make-instance cnm-smoke => ~s" o)))

;; Stock always-apply call-next-method against split-frame %call-next
(defclass cnm-smoke-apply (ns:ns-object) () (:metaclass ns:+ns-object))
(objc:defmethod #/init ((self cnm-smoke-apply))
  (flet ((call-next-method (&rest args)
           (declare (dynamic-extent args))
           (apply #'%call-next-objc-method self (@class "CnmSmokeApply")
                  (@selector "init") '(:id) args)))
    (call-next-method)))

(let ((o (make-instance 'cnm-smoke-apply)))
  (format t "~&cnm-apply-init => ~s~%" o)
  (unless (typep o 'cnm-smoke-apply)
    (error "make-instance cnm-smoke-apply => ~s" o)))

(defclass cnm-smoke-void (ns:ns-object) () (:metaclass ns:+ns-object))
(objc:defmethod (#/cnmPing :void) ((self cnm-smoke-void))
  nil)
(#/cnmPing (#/alloc cnm-smoke-void))
(format t "~&void-callback ok~%")

(format t "~&DARWIN-OBJC-CALL-NEXT-SMOKE-OK~%")
(quit 0)
