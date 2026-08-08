;;;; Uncompiled #_ / interpreted %ff-call smoke (darwinarm64).
;;;;
;;;;   ./darm64cl.smoke-bin --image-name darm64cl.image.prev-biased \
;;;;       --no-init --batch < tools/darwin-interp-ff-call-smoke.lisp
;;;;
;;;; Reloads %do-ff-call / %ff-call from source when the image predates
;;;; this change.  Does NOT save-application.
;;;;
;;;; Note: a top-level (%ff-call …) form is rewritten by nx1 to
;;;; aapcs64-ff-call when compiled.  True interpreter coverage is
;;;; FUNCALL of the runtime %ff-call, plus cheap-eval of #_getpid
;;;; (macroexpands to ff-call → %ff-call via call-check-regs).
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)
(require "ARM64ENV")

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

(unless (functionp (fboundp '%ff-call))
  (error "%ff-call not fbound after reload"))

(defun %interp-ff-call-smoke-wrap (fn a b)
  (funcall fn a b))

(let* ((addr (%reference-external-entry-point (external "getpid")))
       (pid (funcall #'%ff-call addr :signed-fullword))
       (pid-wrap (%interp-ff-call-smoke-wrap #'%ff-call addr :signed-fullword))
       (pid2 (cheap-eval-in-environment '(#_getpid) nil)))
  (unless (and (integerp pid) (> pid 0))
    (error "funcall %ff-call getpid => ~s" pid))
  (unless (eql pid pid-wrap)
    (error "wrap %ff-call => ~s, direct => ~s" pid-wrap pid))
  (unless (eql pid pid2)
    (error "cheap-eval #_getpid => ~s, funcall %ff-call => ~s" pid2 pid))
  (format t "~&DARWIN-INTERP-FF-CALL-SMOKE-OK pid=~d~%" pid))
(quit 0)
