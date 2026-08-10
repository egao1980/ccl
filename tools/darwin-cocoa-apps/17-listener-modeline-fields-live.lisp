(in-package :ccl)
;;; Bisect: live buffer-modeline-fields list vs named lookup.
;;; DRAWRECT_FIELD_MODE=live-list | live-names | live-funcall-only
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
      (ecase *mode*
        (:live-list
         ;; Exact failing pattern: mapcar over live fields list.
         (let ((string
                (apply #'concatenate 'string
                       (mapcar
                        #'(lambda (field)
                            (or (ignore-errors
                                  (funcall (hi::modeline-field-function field) buffer))
                                ""))
                        (hi::buffer-modeline-fields buffer)))))
           (setq *last-built* string)))
        (:live-names
         ;; Same fields, but via names then find (known-good pattern).
         (let* ((names (mapcar #'hi::modeline-field-name
                               (hi::buffer-modeline-fields buffer)))
                (string (%build-from-fields buffer names)))
           (setq *last-built* (cons names string))))
        (:live-funcall-only
         ;; Call each field function; no concatenate/apply.
         (dolist (field (hi::buffer-modeline-fields buffer))
           (ignore-errors
             (funcall (hi::modeline-field-function field) buffer)))
         (setq *last-built* :funcall-only))
        (:live-list-no-ignore
         ;; No ignore-errors — surface real errors.
         (let ((string
                (apply #'concatenate 'string
                       (mapcar
                        #'(lambda (field)
                            (funcall (hi::modeline-field-function field) buffer))
                        (hi::buffer-modeline-fields buffer)))))
           (setq *last-built* string)))))
    (#/restoreGraphicsState context)))
