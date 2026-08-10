;;;; Patch modeline drawRect then Listener #/display bisect.
;;;; Post-COCOA body lives in a LOADed file (stdin + #/ reader races).
;;;;   DRAWRECT_MODE=borders|point|empty-attrs|real-attrs|full \
;;;;   ./tools/run-darwin-ide-smoke.sh 120 tools/ide-modeline-hfa-bisect.lisp IDE-MODELINE-HFA-BISECT-OK
(in-package :ccl)

(defun %p (fmt &rest a)
  (apply #'format t fmt a) (terpri) (force-output)
  (with-open-file (s "/tmp/ide-modeline-hfa-bisect-detail.log" :direction :output
                     :if-exists :append :if-does-not-exist :create)
    (apply #'format s fmt a) (terpri s) (force-output s)))

(ignore-errors (delete-file "/tmp/ide-modeline-hfa-bisect-detail.log"))
(setq *debugger-hook*
      (lambda (c h) (declare (ignore h)) (%p "DBG ~a" c) (force-output) (#_exit 99)))

(defun %cip-wait (f)
  (let ((return-values :unset))
    (let ((wrapper (lambda ()
                     (setq return-values (multiple-value-list (funcall f))))))
      (ccl::%interrupt-event-process wrapper t)
      (when (eq return-values :unset) (error "wrapper did not run"))
      (apply #'values return-values))))

(defparameter *mode*
  (let ((e (getenv "DRAWRECT_MODE")))
    (if e (intern (string-upcase e) :keyword) :borders)))
(%p "mode=~s" *mode*)

(require "COCOA")
(%p "finished=~s" (timed-wait-on-semaphore gui::*cocoa-ide-finished-launching* 60))

(load (merge-pathnames "tools/ide-modeline-hfa-bisect-run.lisp" (ccl-directory)))
