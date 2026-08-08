;;;; Interpreted %ff-call smoke (darwinarm64).
;;;; Image must already contain %ff-call from bootstrap. Do NOT reload
;;;; vinsns/LAP mid-session then save — that corrupts W^X images.
(in-package :ccl)
(use-interface-dir :libc)
(let* ((e (foreign-symbol-address "getpid"))
       (pid (%ff-call e :signed-fullword))
       (pid2 (funcall #'%ff-call e :signed-fullword)))
  (unless (and (integerp pid) (> pid 0) (eql pid pid2))
    (error "interp %ff-call getpid => ~s / ~s" pid pid2))
  (format t "~&DARWIN-INTERP-FF-CALL-SMOKE-OK pid=~d~%" pid))
(quit 0)
