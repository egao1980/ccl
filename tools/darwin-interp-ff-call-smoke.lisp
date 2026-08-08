;;;; Uncompiled #_ / interpreted %ff-call smoke (darwinarm64).
(in-package :ccl)
(use-interface-dir :libc)
;; Deliberately NOT compile — force %ff-call path.
(let ((pid (#_getpid)))
  (unless (and (integerp pid) (> pid 0))
    (error "interp getpid => ~s" pid))
  (format t "~&DARWIN-INTERP-FF-CALL-SMOKE-OK pid=~d~%" pid))
(quit 0)
