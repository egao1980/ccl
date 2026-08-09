;;;; Darwin/arm64 AAPCS64 composite return smoke.
;;;; Poll — CCL smokes hang or die quickly; do not block indefinitely.
;;;;
;;;; Covers HFA (NSSize/NSPoint/NSRect), GPR≤16B (NSRange), and that
;;;; expand-ff-call never stuffs the result buffer into x0.
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)

(format t "~&;; darwin-struct-return-smoke~%")
(finish-output)

(use-interface-dir :cocoa)

(defun flat-arglist (form)
  "Walk LET/%stack-block wrappers to the inner %ff-call."
  (cond ((atom form) nil)
        ((eq (car form) '%ff-call) form)
        (t (or (flat-arglist (car form))
               (flat-arglist (cdr form))))))

;; Reload tip expand-ff-call + helpers from source (image may be stale).
(let* ((src (merge-pathnames "compiler/ARM64/arm64-backend.lisp" (ccl-directory)))
       (wanted '(arm64::hfa-leaf-reps arm64::record-hfa-info
                 arm64::classify-record-return
                 arm64::record-type-returns-structure-as-first-arg
                 arm64::struct-from-regbuf-values
                 arm64::expand-ff-call))
       (forms ()))
  (with-open-file (s src)
    (loop for f = (read s nil s)
          until (eq f s)
          when (and (consp f) (eq (car f) 'defun)
                    (member (cadr f) wanted :test #'eq))
          do (push f forms)))
  (format t "~&;; found helpers ~s~%" (mapcar #'cadr (reverse forms)))
  (dolist (f (nreverse forms)) (eval f))
  (setf (ftd-ff-call-expand-function *target-ftd*) #'arm64-darwin::expand-ff-call)
  (setf (ftd-ff-call-struct-return-by-implicit-arg-function *target-ftd*)
        #'arm64-darwin::record-type-returns-structure-as-first-arg)
  (format t "~&;; expand helpers ok (~d)~%" (length forms))
  (finish-output))

;; Compiler path: vinsns + aapcs64-ff-call (required for compiled #/ sends).
(let* ((vsrc (merge-pathnames "compiler/ARM64/arm64-vinsns.lisp" (ccl-directory)))
       (wanted '(ff-call-return-registers macptr-to-structure-return-reg))
       (n 0))
  (with-open-file (s vsrc)
    (loop for f = (read s nil s)
          until (eq f s)
          when (and (consp f) (eq (car f) 'define-arm64-vinsn)
                    (let ((name (cadr f)))
                      (or (member name wanted)
                          (and (consp name) (member (car name) wanted)))))
          do (eval f) (incf n)))
  (format t "~&;; vinsns ok (~d)~%" n)
  (finish-output))

(let* ((src (merge-pathnames "compiler/ARM64/arm642.lisp" (ccl-directory)))
       (helpers ())
       (ffcall nil))
  (with-open-file (s src)
    (loop for f = (read s nil s)
          until (eq f s)
          do (cond ((and (consp f)
                         (member (car f) '(defun defarm642))
                         (member (cadr f)
                                 '(arm642-aapcs64-stack-arg-bytes
                                   arm642-align-up
                                   arm642-aapcs64-ff-call)))
                    (if (eq (cadr f) 'arm642-aapcs64-ff-call)
                      (setq ffcall f)
                      (push f helpers))))))
  (dolist (h (nreverse helpers)) (eval h))
  (eval ffcall)
  (format t "~&;; aapcs64-ff-call ok~%")
  (finish-output))

;; nx1 must accept :structure-return
(let* ((src (merge-pathnames "compiler/nx1.lisp" (ccl-directory)))
       (form nil))
  (with-open-file (s src)
    (loop for f = (read s nil s)
          until (eq f s)
          when (and (consp f) (eq (car f) 'defun)
                    (eq (cadr f) 'nx1-ff-call-internal))
          do (setq form f)))
  (when form (eval form) (format t "~&;; nx1-ff-call-internal ok~%"))
  (finish-output))

(flet ((class-of-spec (spec)
         (arm64::classify-record-return (parse-foreign-type spec)))
       (implicit (spec)
         (funcall (ftd-ff-call-struct-return-by-implicit-arg-function *target-ftd*)
                  spec)))
  (assert (eq (class-of-spec :<NSS>ize) :hfa))
  (assert (eq (class-of-spec :<NSP>oint) :hfa))
  (assert (eq (class-of-spec :<NSR>ect) :hfa))
  (assert (eq (class-of-spec :<NSR>ange) :gpr))
  (assert (null (implicit :<NSS>ize)))
  (assert (null (implicit :<NSR>ect)))
  (assert (null (implicit :<NSR>ange)))
  (format t "~&;; classify ok~%")
  (finish-output))

(flet ((expanded (result-spec)
         (funcall (ftd-ff-call-expand-function *target-ftd*)
                  '(%ff-call ENTRY)
                  `(S :address FONT :address SEL ,result-spec)
                  :arg-coerce #'null-coerce-foreign-arg
                  :result-coerce #'null-coerce-foreign-result))
       (has-registers (ex)
         (member :registers (flat-arglist ex)))
       (result-as-x0-p (ex)
         ;; Broken shape: first :address value is the result buffer S.
         (let ((ff (flat-arglist ex)))
           (and (eq (third ff) :address)
                (eq (fourth ff) 'S)))))
  (let ((ex (expanded :<NSS>ize)))
    (format t "~&;; NSSize expand=~%~S~%" ex)
    (finish-output)
    (assert (has-registers ex) () "NSSize needs :registers: ~s" ex)
    (assert (not (result-as-x0-p ex)) () "NSSize still passes result as x0: ~s" ex))
  (let ((ex (expanded :<NSR>ange)))
    (assert (has-registers ex) () "NSRange needs :registers: ~s" ex)
    (assert (not (result-as-x0-p ex)) () "NSRange still passes result as x0: ~s" ex))
  (let ((ex (expanded :<NSR>ect)))
    (assert (has-registers ex) () "NSRect HFA needs :registers: ~s" ex)
    (assert (not (result-as-x0-p ex)) () "NSRect still passes result as x0: ~s" ex))
  (format t "~&;; expand shape ok~%")
  (finish-output))

;; Live ObjC needs :registers in %ff-call + .SPffcall-return-registers.
(let* ((src (merge-pathnames "level-0/ARM64/arm64-def.lisp" (ccl-directory)))
       (ff nil)
       (laps ()))
  (with-open-file (s src)
    (loop for f = (read s nil s)
          until (eq f s)
          do (cond ((and (consp f) (eq (car f) 'defun) (eq (cadr f) '%ff-call))
                    (setq ff f))
                   ((and (consp f) (eq (car f) 'defarm64lapfunction)
                         (member (cadr f)
                                 '(%do-ff-call-return-registers
                                   %do-ff-call-structure-return)))
                    (push f laps)))))
  (dolist (f (nreverse laps))
    (handler-case (eval f)
      (error (e) (format t "~&;; lap reload ~a: ~a~%" (cadr f) e))))
  (when ff
    (eval ff)
    (format t "~&;; %ff-call reloaded~%")
    (finish-output)))

(require "OBJC-SUPPORT")
(format t "~&;; objc-support loaded~%")
(finish-output)

(let* ((src (merge-pathnames "objc-bridge/objc-runtime.lisp" (ccl-directory)))
       (wanted '(objc-message-send-stret
                 objc-message-send-stret-with-selector
                 objc-message-send-super-stret
                 objc-message-send-super-stret-with-selector))
       (forms ()))
  (with-open-file (s src)
    (loop for f = (read s nil s)
          until (eq f s)
          when (and (consp f) (eq (car f) 'defmacro) (member (cadr f) wanted))
          do (push f forms)))
  (dolist (f (nreverse forms))
    (handler-case (eval f)
      (error (e) (format t "~&;; macro ~a: ~a~%" (cadr f) e))))
  (format t "~&;; stret macros ok (~d)~%" (length forms))
  (finish-output))

(objc:with-autorelease-pool
  (let* ((font (#/systemFontOfSize: ns:ns-font 12.0d0))
         (g (#/glyphWithName: font #@"i"))
         (adv (#/advancementForGlyph: font g))
         (bb (#/boundingRectForGlyph: font g)))
    (format t "~&;; font=~s glyph=~s~%" font g)
    (format t "~&;; adv width=~s height=~s~%"
            (ns:ns-size-width adv) (ns:ns-size-height adv))
    (format t "~&;; bbox origin=(~s,~s) size=(~s,~s)~%"
            (ns:ns-rect-x bb) (ns:ns-rect-y bb)
            (ns:ns-rect-width bb) (ns:ns-rect-height bb))
    (finish-output)
    (assert (and (floatp (ns:ns-size-width adv))
                 (plusp (ns:ns-size-width adv))))
    (let* ((s (%make-nsstring "abcdef"))
           (r (ns:make-ns-range 1 3))
           (sub (#/substringWithRange: s r)))
      (assert (equal (%get-cstring (#/UTF8String sub)) "bcd")))))

(format t "~&DARWIN-STRUCT-RETURN-SMOKE-OK~%")
(quit)
