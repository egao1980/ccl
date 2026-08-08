;;;; Uncompiled #_ / interpreted %ff-call smoke (darwinarm64).
;;;;
;;;;   ./darm64cl --no-init --batch < tools/darwin-interp-ff-call-smoke.lisp
;;;;
;;;; Reloads vinsns/handlers/%ff-call from source when the image
;;;; predates this change.  Does NOT save-application.
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)
(require "ARM64ENV")

;; Reload alloc-variable-c-frame + %foreign-stack-pointer vinsns.
(let* ((src (merge-pathnames "compiler/ARM64/arm64-vinsns.lisp" (ccl-directory))))
  (with-open-file (s src)
    (loop for f = (read s nil s)
          until (eq f s)
          when (and (consp f)
                    (eq (car f) 'define-arm64-vinsn)
                    (let ((name (cadr f)))
                      (or (eq name '%foreign-stack-pointer)
                          (and (consp name)
                               (member (car name)
                                       '(alloc-variable-c-frame
                                         discard-c-frame))))))
          do (eval f))))

;; arm642 acode handlers.
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

;; %do-ff-call + %ff-call.
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
;; True interpreter path: funcall of %ff-call (nx1 would rewrite
;; (%ff-call …) to aapcs64-ff-call when compiling).
(let* ((addr (%reference-external-entry-point (external "getpid")))
       (pid (%ff-call addr :signed-fullword)))
  (unless (and (integerp pid) (> pid 0))
    (error "interp %ff-call getpid => ~s" pid))
  ;; Also exercise sharp-macro → eval (interprets %ff-call).
  (let ((pid2 (eval '(#_getpid))))
    (unless (eql pid pid2)
      (error "eval #_getpid => ~s, direct %ff-call => ~s" pid2 pid)))
  (format t "~&DARWIN-INTERP-FF-CALL-SMOKE-OK pid=~d~%" pid))
(quit 0)
