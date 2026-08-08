;;;; Dump full darm64cl.image from arm64-boot.image (darwinarm64).
;;;;
;;;;   ./darm64cl --image-name arm64-boot.image --no-init --batch \
;;;;     < tools/save-darwinarm64-image.lisp
;;;;
;;;; Production save uses :purify t — pure code is RX at the canonical
;;;; VA; fasl/runtime compile uses MAP_JIT.  Dual-map is off
;;;; (DARWIN_ARM64_DUAL_MAP=0).
;;;;
;;;; Clear *outstanding-deferred-warnings* before dump: saving from inside
;;;; with-compilation-unit (compile-ccl) otherwise leaves a parent unit in
;;;; the image and compile-file deferred warnings never signal.

(in-package "CCL")

(setq *outstanding-deferred-warnings* nil)
(format t "~&;; save-application darm64cl.image :purify t~%")
(save-application "darm64cl.image" :purify t)
