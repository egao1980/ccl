;;;; Uncompiled #_ / interpreted %ff-call smoke (darwinarm64).
(in-package :ccl)
(use-interface-dir :libc)
(let* ((e (foreign-symbol-address "getpid"))
       (pid (%ff-call e :signed-fullword)))
  (unless (and (integerp pid) (> pid 0))
    (error "interp %ff-call getpid => ~s" pid))
  (format t "~&DARWIN-INTERP-FF-CALL-SMOKE-OK pid=~d~%" pid))
(quit 0)
