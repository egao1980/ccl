;;;; Patch-only redefine of draw-modeline-string + modeline-view #/drawRect:
;;;; (full cocoa-editor reload hits class_addIvar). Join via stream, not APPLY.
(in-package :gui)

(defun draw-modeline-string (the-modeline-view)
  (ignore-errors
    (let* ((text-attributes (modeline-text-attributes the-modeline-view))
           (buffer (buffer-for-modeline-view the-modeline-view)))
      (when (and buffer
                 (typep text-attributes 'macptr)
                 (not (ccl::%null-ptr-p text-attributes)))
        (let* ((string
                (with-output-to-string (out)
                  (dolist (field (hi::buffer-modeline-fields buffer))
                    (write-string
                     (or (ignore-errors
                           (let ((s (funcall (hi::modeline-field-function field) buffer)))
                             (and (stringp s) s)))
                         "")
                     out)))))
          (when (plusp (length string))
            (let ((ns (#/autorelease (ccl::%make-nsstring string))))
              (when (and (typep ns 'macptr) (not (ccl::%null-ptr-p ns)))
                (#/drawAtPoint:withAttributes: ns
                                               (ns:make-ns-point 5.0d0 1.0d0)
                                               text-attributes)))))))))

(objc:defmethod (#/drawRect: :void) ((self modeline-view) (rect :<NSR>ect))
  (declare (ignorable rect))
  (let* ((bounds (#/bounds self))
         (context (#/currentContext ns:ns-graphics-context))
         (w (float (ns:ns-rect-width bounds) 1.0d0))
         (h (float (ns:ns-rect-height bounds) 1.0d0))
         (top (ns:make-ns-rect 0.0d0 0.0d0 w 0.5d0))
         (bot (ns:make-ns-rect 0.0d0 (- h 0.5d0) w 0.5d0)))
    (#/saveGraphicsState context)
    (#/set (#/colorWithCalibratedWhite:alpha: ns:ns-color 0.9d0 1.0d0))
    (#_NSRectFill bounds)
    (#/set (#/colorWithCalibratedWhite:alpha: ns:ns-color 0.3333d0 1.0d0))
    (#_NSRectFill top)
    (#_NSRectFill bot)
    (draw-modeline-string self)
    (#/restoreGraphicsState context)))

#+arm64-target
(setq *log-callback-errors* t)
