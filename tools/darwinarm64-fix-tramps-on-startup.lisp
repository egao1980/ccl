;;; Loaded early to repair x8-index callback trampolines in older IDE heaps.
(in-package :ccl)
(when (fboundp 'fix-arm64-callback-trampolines-for-x9)
  (let ((n (fix-arm64-callback-trampolines-for-x9)))
    (when (and n (> n 0))
      (format t "~&;; darwinarm64: patched ~s callback trampoline(s) x8→x9~%" n)
      (force-output))))
