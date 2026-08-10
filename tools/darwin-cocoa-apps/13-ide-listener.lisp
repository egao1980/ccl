;;;; 13 — IDE Listener create after launch.
;;;; Marker: IDE-LISTENER-OK
;;;;
;;;; Uses objc-message-send (string selector) so the probe can be compiled
;;;; before COCOA provides #/newListener: stubs.
;;;;
;;;;   ./tools/run-darwin-ide-smoke.sh 90 tools/darwin-cocoa-apps/13-ide-listener.lisp IDE-LISTENER-OK
(in-package :ccl)

(defun %ide13-log (fmt &rest args)
  (apply #'format t fmt args) (terpri) (force-output)
  (with-open-file (s "/tmp/ide-listener-13.log" :direction :output
                     :if-exists :append :if-does-not-exist :create)
    (apply #'format s fmt args) (terpri s) (force-output s)))

(ignore-errors (delete-file "/tmp/ide-listener-13.log"))

(unless (fboundp '%invoke-objc-send-function)
  (error "missing tip CNM"))

(defun %ide13-precompile-hemlock-sends ()
  (let ((sig '(:void :id :<SEL> :<NSI>nteger :<NSI>nteger :<NSI>nteger)))
    (let ((f (compile-send-function-for-signature sig)))
      (setf (objc-method-signature-info-function (objc-method-signature-info sig)) f)
      (maphash (lambda (name msg)
                 (declare (ignore name))
                 (dolist (m (append (objc-message-info-methods msg)
                                    (objc-message-info-protocol-methods msg)))
                   (let ((si (objc-method-info-signature-info m)))
                     (when (and si (equal sig (objc-method-signature-info-type-signature si)))
                       (setf (objc-method-signature-info-function si) f)))))
               *objc-message-info*)
      (%ide13-log "precompiled note* send => ~s" f))))

(defun %ide13-listener-probe ()
  (objc:with-autorelease-pool
    (#/setActivationPolicy: *nsapp* 0)
    (#/activateIgnoringOtherApps: *nsapp* #$YES)
    (%ide13-precompile-hemlock-sends)
    (%ide13-log "before newListener windows=~s"
                (#/count (#/orderedWindows *nsapp*)))
    (objc-message-send (#/delegate *nsapp*) "newListener:"
                       :id (%null-ptr) :void)
    (%ide13-log "after newListener windows=~s"
                (#/count (#/orderedWindows *nsapp*)))
    t))

(%ide13-log "require COCOA…")
(require "COCOA")
(%ide13-log "modules loaded; wait finished-launching…")

(let ((ok (timed-wait-on-semaphore gui::*cocoa-ide-finished-launching* 45)))
  (%ide13-log "finished-launching => ~s" ok)
  (unless ok (error "IDE did not finish launching")))

(call-in-initial-process #'%ide13-listener-probe)

(format t "~&IDE-LISTENER-OK~%")
(quit 0)
