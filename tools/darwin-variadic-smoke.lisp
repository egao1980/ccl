;;;; Smoke: Darwin/arm64 variadic-on-stack (Apple ABI).
;;;;
;;;;   ./darm64cl --no-init --batch < tools/darwin-variadic-smoke.lisp
;;;;
;;;; Reloads patched expander / nx1 / aapcs64-ff-call from source when
;;;; the image predates this change.
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)
(load "lib/foreign-types.lisp")
(load "compiler/nx1.lisp")
(let* ((src (merge-pathnames "compiler/ARM64/arm642.lisp" (ccl-directory)))
       (form (with-open-file (s src)
               (loop for f = (read s nil s)
                     until (eq f s)
                     when (and (consp f)
                               (eq (car f) 'defarm642)
                               (eq (cadr f) 'arm642-aapcs64-ff-call))
                       return f
                     finally (error "aapcs64-ff-call def not found")))))
  (eval form))
(use-interface-dir :libc)
(rlet ((buf (:array :char 64)))
  (dotimes (i 64) (setf (%get-byte buf i) 0))
  (with-cstrs ((fmt "%d %d %d"))
    (let* ((n (#_snprintf buf 64 fmt :int 1 :int 2 :int 3))
           (s (%get-cstring buf)))
      (unless (and (eql n 5) (string= s "1 2 3"))
        (error "snprintf ints: n=~s s=~s (expected 5 / \"1 2 3\")" n s))))
  (dotimes (i 64) (setf (%get-byte buf i) 0))
  (with-cstrs ((fmt "%d %.1f %ld"))
    (let* ((n (#_snprintf buf 64 fmt :int 1 :double-float 2.5d0 :long 3))
           (s (%get-cstring buf)))
      (unless (and (eql n 7) (string= s "1 2.5 3"))
        (error "snprintf mixed: n=~s s=~s (expected 7 / \"1 2.5 3\")" n s)))))
(format t "~&DARWIN-VARIADIC-SMOKE-OK~%")
(quit)
