;;;; Smoke: fixed-arity ff-call with >8 GPR args (SPffcall stack bump).
;;;;
;;;;   cc -arch arm64 -shared -o /tmp/libsum9.dylib /tmp/sum9.c
;;;;   # sum9.c: long sum9(long a,b,c,d,e,f,g,h,i){return a+b+c+d+e+f+g+h+i;}
;;;;   ./darm64cl --no-init --batch < tools/ffcall-stack-smoke.lisp
;;;;
;;;; Reloads arm642-aapcs64-ff-call from source when the image predates
;;;; the stack-arg lift (frozen kernel defs).
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)
(let* ((src (merge-pathnames "compiler/ARM64/arm642.lisp" (ccl-directory)))
       (form (with-open-file (s src)
               (loop for f = (read s nil s)
                     until (eq f s)
                     when (and (consp f)
                               (eq (car f) 'defarm642)
                               (eq (cadr f) 'arm642-aapcs64-ff-call))
                       return f
                     finally (error "aapcs64-ff-call def not found in ~s" src)))))
  (eval form))
(unless (probe-file "/tmp/libsum9.dylib")
  (error "missing /tmp/libsum9.dylib — build sum9 first"))
(open-shared-library "/tmp/libsum9.dylib")
(defun call-sum9 ()
  (ff-call (foreign-symbol-address "sum9")
           :signed-doubleword 1 :signed-doubleword 2 :signed-doubleword 3
           :signed-doubleword 4 :signed-doubleword 5 :signed-doubleword 6
           :signed-doubleword 7 :signed-doubleword 8 :signed-doubleword 9
           :signed-doubleword))
(let ((n (call-sum9)))
  (unless (eql n 45)
    (error "sum9 => ~s, expected 45" n)))
(format t "~&FFCALL-STACK-SMOKE-OK~%")
(quit)
