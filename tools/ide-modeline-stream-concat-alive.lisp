;;;; Install fixed modeline string draw (stream-concat join + drawAtPoint) and
;;;; prove Listener #/display stays alive. Avoid full cocoa-editor reload
;;;; (class_addIvar); load tools/ide-modeline-stream-concat-patch.lisp instead.
;;;;   ./tools/run-darwin-ide-smoke.sh 120 tools/ide-modeline-stream-concat-alive.lisp \\
;;;;     IDE-MODELINE-STREAM-CONCAT-ALIVE-OK
(in-package :ccl)

(defun %p (fmt &rest a)
  (apply #'format t fmt a) (terpri) (force-output)
  (with-open-file (s "/tmp/ide-modeline-stream-concat-alive-detail.log" :direction :output
                     :if-exists :append :if-does-not-exist :create)
    (apply #'format s fmt a) (terpri s) (force-output s)))

(ignore-errors (delete-file "/tmp/ide-modeline-stream-concat-alive-detail.log"))
(setq *debugger-hook*
      (lambda (c h) (declare (ignore h)) (%p "DBG ~a" c) (force-output) (#_exit 99)))

(defun %cip-wait (f)
  (let ((return-values :unset))
    (let ((wrapper (lambda ()
                     (setq return-values (multiple-value-list (funcall f))))))
      (ccl::%interrupt-event-process wrapper t)
      (when (eq return-values :unset) (error "wrapper did not run"))
      (apply #'values return-values))))

(%p "require")
(require "COCOA")
(%p "finished=~s" (timed-wait-on-semaphore gui::*cocoa-ide-finished-launching* 60))

(%p "load stream-concat patch…")
(handler-case
    (progn
      (load (merge-pathnames "tools/ide-modeline-stream-concat-patch.lisp" (ccl-directory)))
      (%p "patched"))
  (error (c) (%p "patch ERR ~a" c) (force-output) (#_exit 1)))

(let ((ok 0) (fail 0))
  (%p "ensure+display")
  (%cip-wait
   (lambda ()
     (#/setActivationPolicy: *nsapp* 0)
     (#/activateIgnoringOtherApps: *nsapp* #$YES)
     (#/ensureListener: (#/delegate *nsapp*) (%null-ptr))
     (dotimes (i (#/count (#/orderedWindows *nsapp*)))
       (#/display (#/objectAtIndex: (#/orderedWindows *nsapp*) i)))
     t))
  (%p "shown")
  (dotimes (i 8)
    (handler-case
        (progn
          (%cip-wait
           (lambda ()
             (dotimes (j (#/count (#/orderedWindows *nsapp*)))
               (#/display (#/objectAtIndex: (#/orderedWindows *nsapp*) j)))
             t))
          (incf ok)
          (%p "ping ~s" i))
      (error (c) (incf fail) (%p "err ~a" c))))
  (%p "summary ok=~s fail=~s" ok fail)
  (unless (and (>= ok 6) (zerop fail))
    (force-output)
    (#_exit 1))
  (format t "~&IDE-MODELINE-STREAM-CONCAT-ALIVE-OK~%")
  (force-output)
  (#_exit 0))
