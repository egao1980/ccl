;;;; Loaded after COCOA — safe to use #/ reader.
(in-package :ccl)

(load (merge-pathnames
       (format nil "tools/ide-modeline-hfa-bisect-~a.lisp"
               (string-downcase (symbol-name *mode*)))
       (ccl-directory)))
(%p "drawRect installed")

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
  (format t "~&IDE-MODELINE-HFA-BISECT-OK~%")
  (force-output)
  (#_exit 0))
