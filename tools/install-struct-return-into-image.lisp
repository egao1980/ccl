;;;; Install tip AAPCS64 composite-return into the image (FFI only).
;;;; Does NOT redef objc macros into CCL (that breaks OBJC-SUPPORT import).
;;;; HFA/NSRect pick objc_msgSend via updated FTD implicit-arg predicate.
;;;;
;;;;   cp -p darm64cl.image darm64cl.image.pre-struct-return
;;;;   ./darm64cl --no-init < tools/install-struct-return-into-image.lisp
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil
      *outstanding-deferred-warnings* nil)

(format t "~&;; install-struct-return-into-image (ffi-only)~%")
(finish-output)

(flet ((load-defuns (path names)
         (let ((forms ()))
           (with-open-file (s path)
             (loop for f = (read s nil s)
                   until (eq f s)
                   when (and (consp f) (eq (car f) 'defun)
                             (member (cadr f) names :test #'eq))
                   do (push f forms)))
           (dolist (f (nreverse forms)) (eval f))
           (length forms))))
  (format t "~&;; backend ~d~%"
          (load-defuns
           (merge-pathnames "compiler/ARM64/arm64-backend.lisp" (ccl-directory))
           '(arm64::hfa-leaf-reps arm64::record-hfa-info
             arm64::classify-record-return
             arm64::record-type-returns-structure-as-first-arg
             arm64::struct-from-regbuf-values
             arm64::expand-ff-call)))
  (setf (ftd-ff-call-expand-function *target-ftd*) #'arm64-darwin::expand-ff-call)
  (setf (ftd-ff-call-struct-return-by-implicit-arg-function *target-ftd*)
        #'arm64-darwin::record-type-returns-structure-as-first-arg)

  (let ((n 0))
    (with-open-file (s (merge-pathnames "compiler/ARM64/arm64-vinsns.lisp"
                                        (ccl-directory)))
      (loop for f = (read s nil s)
            until (eq f s)
            when (and (consp f) (eq (car f) 'define-arm64-vinsn)
                      (let ((name (cadr f)))
                        (or (member name '(ff-call-return-registers
                                           macptr-to-structure-return-reg))
                            (and (consp name)
                                 (member (car name)
                                         '(ff-call-return-registers
                                           macptr-to-structure-return-reg))))))
            do (eval f) (incf n)))
    (format t "~&;; vinsns ~d~%" n))

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
    (format t "~&;; aapcs64-ff-call ok~%"))

  (load-defuns (merge-pathnames "compiler/nx1.lisp" (ccl-directory))
               '(nx1-ff-call-internal))
  (format t "~&;; nx1 ok~%")

  (let ((n 0))
    (with-open-file (s (merge-pathnames "level-0/ARM64/arm64-def.lisp"
                                        (ccl-directory)))
      (loop for f = (read s nil s)
            until (eq f s)
            when (and (consp f) (eq (car f) 'defarm64lapfunction)
                      (member (cadr f)
                              '(%do-ff-call-return-registers
                                %do-ff-call-structure-return)
                              :test #'eq))
            do (eval f) (incf n)))
    (format t "~&;; laps ~d~%" n))
  (load-defuns (merge-pathnames "level-0/ARM64/arm64-def.lisp" (ccl-directory))
               '(%ff-call))
  (format t "~&;; %ff-call ok~%")

  (load-defuns (merge-pathnames "level-0/l0-def.lisp" (ccl-directory))
               '(%throwing-through-cleanup-p))
  (format t "~&;; throwing-cleanup ok~%"))

(when (fboundp '%darwinarm64-register-code-heap)
  (%darwinarm64-register-code-heap))

(format t "~&;; save-application darm64cl.image :purify t~%")
(finish-output)
(save-application "darm64cl.image" :purify t)
