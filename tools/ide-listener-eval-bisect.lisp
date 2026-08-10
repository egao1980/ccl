;;;; Bisect Listener eval / redisplay death after enqueue.
;;;; IDE_EVAL_MODE=
;;;;   enqueue-only | wait-no-display | wait-display | insert-only
;;;;
;;;;   IDE_EVAL_MODE=enqueue-only ./tools/run-darwin-ide-smoke.sh 60 \\
;;;;     tools/ide-listener-eval-bisect.lisp IDE-LISTENER-EVAL-BISECT-OK
(in-package :ccl)

(defun %p (fmt &rest a)
  (apply #'format t fmt a) (terpri) (force-output)
  (with-open-file (s "/tmp/ide-listener-eval-bisect-detail.log" :direction :output
                     :if-exists :append :if-does-not-exist :create)
    (apply #'format s fmt a) (terpri s) (force-output s)))

(ignore-errors (delete-file "/tmp/ide-listener-eval-bisect-detail.log"))
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
  (let ((e (getenv "IDE_EVAL_MODE")))
    (if e (intern (string-upcase e) :keyword) :enqueue-only)))
(%p "mode=~s" *mode*)

(%p "require")
(require "COCOA")
(%p "finished=~s" (timed-wait-on-semaphore gui::*cocoa-ide-finished-launching* 60))
(load (merge-pathnames "tools/ide-modeline-stream-concat-patch.lisp" (ccl-directory)))
(%p "patched")

(defparameter *eval-seen* :unset)
(defparameter *eval-sem* (make-semaphore))

(%p "ensure")
(%cip-wait
 (lambda ()
   (#/setActivationPolicy: *nsapp* 0)
   (#/activateIgnoringOtherApps: *nsapp* #$YES)
   (#/ensureListener: (#/delegate *nsapp*) (%null-ptr))
   t))
(%p "ensured")

(let* ((doc (#/topListener (find-class 'gui::hemlock-listener-document)))
       (proc (and doc (not (%null-ptr-p doc)) (gui::hemlock-document-process doc))))
  (%p "proc=~s" proc)
  (unless proc (force-output) (#_exit 1))
  (ecase *mode*
    (:enqueue-only
     (gui::eval-in-listener-process proc "(progn (setq ccl::*eval-seen* 1) nil)")
     (%p "enqueued")
     (sleep 1)
     (%p "slept seen=~s" *eval-seen*))
    (:wait-no-display
     (gui::eval-in-listener-process
      proc
      "(progn (setq ccl::*eval-seen* (+ 40 2)) (signal-semaphore ccl::*eval-sem*) nil)")
     (%p "wait=~s seen=~s"
         (timed-wait-on-semaphore *eval-sem* 15)
         *eval-seen*))
    (:wait-display
     (gui::eval-in-listener-process
      proc
      "(progn (setq ccl::*eval-seen* (+ 40 2)) (signal-semaphore ccl::*eval-sem*) nil)")
     (%p "wait=~s seen=~s"
         (timed-wait-on-semaphore *eval-sem* 15)
         *eval-seen*)
     (%cip-wait
      (lambda ()
        (dotimes (j (#/count (#/orderedWindows *nsapp*)))
          (#/display (#/objectAtIndex: (#/orderedWindows *nsapp*) j)))
        t))
     (%p "displayed"))
    (:insert-only
     (%cip-wait
      (lambda ()
        (let* ((ts (slot-value doc 'gui::textstorage))
               (buf (gui::hemlock-buffer ts))
               (hi::*current-buffer* buf))
          (hi::insert-string (hi::buffer-point buf) "hello")
          (dotimes (j (#/count (#/orderedWindows *nsapp*)))
            (#/display (#/objectAtIndex: (#/orderedWindows *nsapp*) j)))
          t)))
     (%p "inserted+displayed")))
  (format t "~&IDE-LISTENER-EVAL-BISECT-OK~%")
  (force-output)
  (#_exit 0))
