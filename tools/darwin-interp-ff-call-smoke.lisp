;;;; Uncompiled #_ / interpreted %ff-call smoke (darwinarm64).
;;;;
;;;;   ./darm64cl --no-init --batch < tools/darwin-interp-ff-call-smoke.lisp
;;;;
;;;; Reloads arm642 handlers + %ff-call from source when the image
;;;; predates this change.  Does NOT save-application.
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)

;; C frames live on Lisp SP — %foreign-stack-pointer is SP.
(eval '(define-arm64-vinsn %foreign-stack-pointer (((dest :imm)) ())
         (add dest sp (:$ 0))))

;; arm642 acode handlers for with-variable-c-frame / %foreign-stack-pointer.
(let* ((src (merge-pathnames "compiler/ARM64/arm642.lisp" (ccl-directory))))
  (with-open-file (s src)
    (loop for f = (read s nil s)
          until (eq f s)
          when (and (consp f)
                    (eq (car f) 'defarm642)
                    (member (cadr f)
                            '(arm642-%foreign-stack-pointer
                              arm642-with-c-frame
                              arm642-with-variable-c-frame)))
          do (eval f))))

;; %do-ff-call + %ff-call from level-0.
(let* ((src (merge-pathnames "level-0/ARM64/arm64-def.lisp" (ccl-directory)))
       (forms ()))
  (with-open-file (s src)
    (loop for f = (read s nil s)
          until (eq f s)
          when (and (consp f)
                    (member (car f) '(defarm64lapfunction defun))
                    (member (cadr f) '(%do-ff-call %ff-call)))
          do (push f forms)))
  (dolist (f (nreverse forms)) (eval f)))

(use-interface-dir :libc)
;; Top-level EVAL of #_getpid → %ff-call (not aapcs64-ff-call).
(let ((pid (eval '(#_getpid))))
  (unless (and (integerp pid) (> pid 0))
    (error "interp getpid => ~s" pid))
  (format t "~&DARWIN-INTERP-FF-CALL-SMOKE-OK pid=~d~%" pid))
(quit 0)
