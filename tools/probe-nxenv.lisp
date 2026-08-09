(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)
(handler-bind ((error
                (lambda (c)
                  (format t "~&;; continue on: ~a~%" c)
                  (let ((r (or (find-restart 'continue c)
                               (find-restart 'never-complain c))))
                    (when r (invoke-restart r))))))
  (in-development-mode
    (load "ccl:compiler;nxenv.lisp")))
(format t "~&has aapcs64=~S~%" (assq 'aapcs64-ff-call *next-nx-operators*))
(format t "~&last ops=~S~%" (mapcar #'car (last *next-nx-operators* 5)))
(format t "~&expand=~S~%" (ignore-errors (macroexpand-1 '(%nx1-operator aapcs64-ff-call))))
(quit 0)
