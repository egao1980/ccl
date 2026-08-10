;;;; Verify File → New Listener stays open.
;;;; Watcher process: cocoa Listener create process-resets the batch tty.
;;;;   ./tools/run-darwin-ide-smoke.sh 90 tools/ide-new-listener-persist.lisp \\
;;;;     IDE-NEW-LISTENER-PERSIST-OK
(in-package :ccl)

(defun %p (fmt &rest a)
  (apply #'format t fmt a) (terpri) (force-output)
  (with-open-file (s "/tmp/ide-new-listener-persist-detail.log" :direction :output
                     :if-exists :append :if-does-not-exist :create)
    (apply #'format s fmt a) (terpri s) (force-output s)))

(ignore-errors (delete-file "/tmp/ide-new-listener-persist-detail.log"))
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
(load (merge-pathnames "tools/ide-modeline-stream-concat-patch.lisp" (ccl-directory)))
(load (merge-pathnames "tools/ide-listener-persist-patch.lisp" (ccl-directory)))
(%p "patched; launching watcher")

(process-run-function "ide-nl-persist"
  (lambda ()
    (handler-case
        (progn
          (%cip-wait
           (lambda ()
             (#/setActivationPolicy: *nsapp* 0)
             (#/activateIgnoringOtherApps: *nsapp* #$YES)
             (#/newListener: (#/delegate *nsapp*) (%null-ptr))
             t))
          (%p "created")
          (let ((ok 0) (bad 0))
            (dotimes (i 16)
              (sleep 0.25)
              (let ((snap
                     (%cip-wait
                      (lambda ()
                        (let* ((doc (#/topListener
                                     (find-class 'gui::hemlock-listener-document)))
                               (proc (and doc (not (%null-ptr-p doc))
                                          (gui::hemlock-document-process doc))))
                          (list :doc-null (or (null doc) (%null-ptr-p doc))
                                :alive (and proc (not (process-exhausted-p proc)))
                                :who (and proc (process-whostate proc))))))))
                (%p "t=~s ~s" i snap)
                (if (and (not (getf snap :doc-null)) (getf snap :alive))
                  (incf ok)
                  (incf bad))))
            (%p "summary ok=~s bad=~s" ok bad)
            (force-output)
            (if (and (>= ok 10) (zerop bad))
              (progn
                (format t "~&IDE-NEW-LISTENER-PERSIST-OK~%")
                (force-output)
                (#_exit 0))
              (#_exit 1))))
      (error (c)
        (%p "watcher ERR ~a" c)
        (force-output)
        (#_exit 1)))))

;; Tty may be process-reset when Listener starts; park until watcher exits.
(loop (sleep 60))
