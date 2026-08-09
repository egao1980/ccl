;;;; Dump full darm64cl.image from arm64-boot.image (darwinarm64).
;;;;
;;;;   ./darm64cl --image-name arm64-boot.image --no-init --batch \
;;;;     < tools/save-darwinarm64-image.lisp
;;;;
;;;; Production save uses :purify t — copies MAP_JIT AREA_CODE into
;;;; AREA_READONLY (RX at canonical VA).  Dual-map is retired.
;;;;
;;;; Clear *outstanding-deferred-warnings* before dump: saving from inside
;;;; with-compilation-unit (compile-ccl) otherwise leaves a parent unit in
;;;; the image and compile-file deferred warnings never signal.

(in-package "CCL")

(setq *outstanding-deferred-warnings* nil)
;; Register MAP_JIT bounds for purify; lisp macptrs are cleared in
;; save-application (dumplisp) so the image does not dump dead pointers.
(when (fboundp '%darwinarm64-register-code-heap)
  (%darwinarm64-register-code-heap))
(format t "~&;; save-application darm64cl.image :purify t (AREA_CODE)~%")
(save-application "darm64cl.image" :purify t)
