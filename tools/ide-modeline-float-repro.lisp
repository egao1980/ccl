;;;; Repro: naked (float (ns:ns-rect-width (#/bounds …))) in modeline #/drawRect:.
;;;; Load via: ./darm64cl -I darm64cl.image --no-init --batch -e '(load "tools/ide-modeline-float-repro.lisp")'
;;;; Or: ./tools/run-darwin-ide-smoke.sh 120 tools/ide-modeline-float-repro-run.lisp MODELINE-FLOAT-REPRO-OK
(in-package :ccl)

(require "COCOA")
(timed-wait-on-semaphore gui::*cocoa-ide-finished-launching* 60)

(defparameter *ide-modeline-float-out* "/tmp/ide-modeline-float-repro.out")
(ignore-errors (delete-file *ide-modeline-float-out*))
(defparameter *ide-modeline-float-err* nil)
(defparameter *ide-modeline-float-ok* nil)
(defparameter *ide-modeline-float-w* nil)
(defparameter *ide-modeline-float-h* nil)

(defun ide-modeline-float-lg (fmt &rest a)
  (with-open-file (s *ide-modeline-float-out* :direction :output
                     :if-exists :append :if-does-not-exist :create)
    (apply #'format s fmt a) (terpri s) (force-output s))
  (apply #'format t fmt a) (terpri) (force-output))

;;; Intentionally unprotected — mirrors the pre-f6a57c79 modeline path.
(objc:defmethod (#/drawRect: :void) ((self gui::modeline-view) (rect :<NSR>ect))
  (declare (ignorable rect))
  (handler-case
      (let* ((bounds (#/bounds self))
             (w (float (ns:ns-rect-width bounds) 1.0d0))
             (h (float (ns:ns-rect-height bounds) 1.0d0)))
        (setq *ide-modeline-float-w* w
              *ide-modeline-float-h* h
              *ide-modeline-float-ok* t)
        (#/set (#/colorWithCalibratedWhite:alpha: ns:ns-color 0.9d0 1.0d0))
        (#_NSRectFill bounds))
    (error (c)
      (setq *ide-modeline-float-err* (princ-to-string c))
      (ide-modeline-float-lg "DRAW-ERR ~a" c))))

(gui::queue-for-gui
 (lambda () (#/newListener: (#/delegate *nsapp*) (%null-ptr))))
(#_usleep 1500000)

(gui::execute-in-gui
 (lambda ()
   (dotimes (i (#/count (#/orderedWindows *nsapp*)))
     (let* ((w (#/objectAtIndex: (#/orderedWindows *nsapp*) i))
            (wc (#/windowController w)))
       (when (typep wc 'gui::hemlock-listener-window-controller)
         (let* ((hv (gui::hemlock-view w))
                (pane (hi::hemlock-view-pane hv))
                (ml (ignore-errors (gui::text-pane-mode-line pane))))
           (ide-modeline-float-lg "ml=~s" ml)
           (when ml
             (#/setNeedsDisplay: ml t)
             (#/display w)
             (#/display ml)
             (ide-modeline-float-lg "after display ok=~s err=~s w=~s h=~s"
                                    *ide-modeline-float-ok*
                                    *ide-modeline-float-err*
                                    *ide-modeline-float-w*
                                    *ide-modeline-float-h*))))))))

(cond (*ide-modeline-float-err*
       (ide-modeline-float-lg "MODELINE-FLOAT-REPRO-ERR ~a" *ide-modeline-float-err*)
       (format t "~&MODELINE-FLOAT-REPRO-ERR~%")
       (force-output)
       (#_exit 1))
      (*ide-modeline-float-ok*
       (ide-modeline-float-lg "MODELINE-FLOAT-REPRO-OK w=~s h=~s"
                              *ide-modeline-float-w* *ide-modeline-float-h*)
       (format t "~&MODELINE-FLOAT-REPRO-OK~%")
       (force-output)
       (quit 0))
      (t
       (ide-modeline-float-lg "MODELINE-FLOAT-REPRO-NO-DRAW")
       (format t "~&MODELINE-FLOAT-REPRO-NO-DRAW~%")
       (force-output)
       (#_exit 2)))
