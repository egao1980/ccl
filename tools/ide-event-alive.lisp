;;;; Post-Listener event-thread health.
;;;; Single top-level form after COCOA so Hemlock Listener process-reset
;;;; can't skip the ping loop and still hit IDE-EVENT-ALIVE-OK.
;;;;   ./tools/run-darwin-ide-smoke.sh 90 tools/ide-event-alive.lisp IDE-EVENT-ALIVE-OK
(in-package :ccl)

(defun %ea (fmt &rest a)
  (apply #'format t fmt a) (terpri) (force-output)
  (with-open-file (s "/tmp/ide-event-alive-detail.log" :direction :output
                     :if-exists :append :if-does-not-exist :create)
    (apply #'format s fmt a) (terpri s) (force-output s)))

(ignore-errors (delete-file "/tmp/ide-event-alive-detail.log"))
(ignore-errors (delete-file "/tmp/ide-event-alive-status"))

(setq *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (%ea "DEBUGGER ~a" c)
        (force-output)
        (#_exit 99)))

(defun %cip-wait (f)
  (let ((return-values :unset))
    (let ((wrapper (lambda ()
                     (setq return-values (multiple-value-list (funcall f))))))
      (ccl::%interrupt-event-process wrapper t)
      (when (eq return-values :unset)
        (error "%cip-wait: wrapper did not run"))
      (apply #'values return-values))))

(%ea "require")
(require "COCOA")
(%ea "finished=~s" (timed-wait-on-semaphore gui::*cocoa-ide-finished-launching* 60))

;; ONE form: ensure + pings + marker + exit.  If process-reset aborts this
;; form, the marker is never printed and the harness fails.
(let ((ok 0) (fail 0) (shown nil))
  (%ea "ensure")
  (setq shown
        (%cip-wait
         (lambda ()
           (#/setActivationPolicy: *nsapp* 0)
           (#/activateIgnoringOtherApps: *nsapp* #$YES)
           (#/ensureListener: (#/delegate *nsapp*) (%null-ptr))
           (#/count (#/orderedWindows *nsapp*)))))
  (%ea "shown n=~s" shown)
  (dotimes (i 8)
    (handler-case
        (let ((n (%cip-wait
                  (lambda ()
                    (#/count (#/orderedWindows *nsapp*))))))
          (%ea "ping ~s n=~s" i n)
          (incf ok))
      (error (c)
        (%ea "ping ~s ERROR ~a" i c)
        (incf fail))))
  (%ea "summary ok=~s fail=~s" ok fail)
  (with-open-file (s "/tmp/ide-event-alive-status" :direction :output
                     :if-exists :supersede :if-does-not-exist :create)
    (format s "~s~%" (list :ok ok :fail fail :shown shown))
    (force-output s))
  (unless (and (>= ok 6) (zerop fail))
    (%ea "FAIL")
    (force-output)
    (#_exit 1))
  (format t "~&IDE-EVENT-ALIVE-OK~%")
  (force-output)
  (#_exit 0))
