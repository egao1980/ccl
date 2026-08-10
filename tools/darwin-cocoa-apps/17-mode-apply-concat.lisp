(in-package :ccl)
;;; apply #'concatenate on mapcar of live fields — known red pattern.
(objc:defmethod (#/drawRect: :void) ((self gui::modeline-view) (rect :<NSR>ect))
  (declare (ignorable rect))
  (incf *draw-hits*)
  (let* ((bounds (#/bounds self))
         (context (#/currentContext ns:ns-graphics-context))
         (w (float (ns:ns-rect-width bounds) 1.0d0))
         (h (float (ns:ns-rect-height bounds) 1.0d0))
         (top (ns:make-ns-rect 0.0d0 0.0d0 w 0.5d0))
         (bot (ns:make-ns-rect 0.0d0 (- h 0.5d0) w 0.5d0))
         (buffer (gui::buffer-for-modeline-view self)))
    (#/saveGraphicsState context)
    (#/set (#/colorWithCalibratedWhite:alpha: ns:ns-color 0.9d0 1.0d0))
    (#_NSRectFill bounds)
    (#/set (#/colorWithCalibratedWhite:alpha: ns:ns-color 0.3333d0 1.0d0))
    (#_NSRectFill top)
    (#_NSRectFill bot)
    (when buffer
      (let ((string
             (apply #'concatenate 'string
                    (mapcar
                     #'(lambda (field)
                         (or (ignore-errors
                               (funcall (hi::modeline-field-function field) buffer))
                             ""))
                     (hi::buffer-modeline-fields buffer)))))
        (setq *last-built* string)))
    (#/restoreGraphicsState context)))
