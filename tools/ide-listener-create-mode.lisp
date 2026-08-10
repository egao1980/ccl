;;;; Compare ensureListener vs newListener process survival.
;;;;   IDE_NL_MODE=ensure|new ./tools/run-darwin-ide-smoke.sh 60 \\
;;;;     tools/ide-listener-create-mode.lisp IDE-LISTENER-CREATE-MODE-OK
(in-package :ccl)

(defun %p (fmt &rest a)
  (apply #'format t fmt a) (terpri) (force-output)
  (with-open-file (s "/tmp/ide-listener-create-mode-detail.log" :direction :output
                     :if-exists :append :if-does-not-exist :create)
    (apply #'format s fmt a) (terpri s) (force-output s)))

(ignore-errors (delete-file "/tmp/ide-listener-create-mode-detail.log"))
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
  (let ((e (getenv "IDE_NL_MODE")))
    (if e (intern (string-upcase e) :keyword) :ensure)))

(%p "require")
(require "COCOA")
(%p "finished=~s mode=~s"
    (timed-wait-on-semaphore gui::*cocoa-ide-finished-launching* 60)
    *mode*)
(load (merge-pathnames "tools/ide-modeline-stream-concat-patch.lisp" (ccl-directory)))

(let* ((wc-class (find-class 'gui::hemlock-listener-window-controller))
       (snap
        (lambda ()
          (let ((lw 0) (procs '()))
            (dotimes (i (#/count (#/orderedWindows *nsapp*)))
              (let* ((w (#/objectAtIndex: (#/orderedWindows *nsapp*) i))
                     (wc (#/windowController w)))
                (when (typep wc wc-class)
                  (incf lw)
                  (let ((doc (#/document wc)))
                    (unless (%null-ptr-p doc)
                      (push (gui::hemlock-document-process doc) procs))))))
            (list :lw lw
                  :alive (count-if (lambda (p)
                                     (and p (not (process-exhausted-p p))))
                                   procs)
                  :procs (mapcar (lambda (p)
                                   (and p (list (process-name p)
                                                (process-whostate p))))
                                 procs))))))
  (%cip-wait
   (lambda ()
     (#/setActivationPolicy: *nsapp* 0)
     (#/activateIgnoringOtherApps: *nsapp* #$YES)
     (ecase *mode*
       (:ensure (#/ensureListener: (#/delegate *nsapp*) (%null-ptr)))
       (:new (#/newListener: (#/delegate *nsapp*) (%null-ptr))))
     t))
  (%p "after0 ~s" (%cip-wait snap))
  (sleep 0.5)
  (%p "after1 ~s" (%cip-wait snap))
  (sleep 1.0)
  (%p "after2 ~s" (%cip-wait snap))
  (let ((s (%cip-wait snap)))
    (%p "final ~s" s)
    (if (and (>= (getf s :lw) 1) (>= (getf s :alive) 1))
      (progn (format t "~&IDE-LISTENER-CREATE-MODE-OK~%") (force-output) (#_exit 0))
      (progn (force-output) (#_exit 1)))))
