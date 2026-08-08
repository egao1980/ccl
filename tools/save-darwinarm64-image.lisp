;;;; Dump full darm64cl.image from arm64-boot.image (darwinarm64).
;;;;
;;;;   ./darm64cl --image-name arm64-boot.image --no-init --batch \
;;;;     < tools/save-darwinarm64-image.lisp
;;;;
;;;; Purify RX on pure is fixed, but save still uses :purify nil until
;;;; dual-map is dropped for a fully purified + MAP_JIT-only runtime.

(in-package "CCL")

(format t "~&;; save-application darm64cl.image :purify nil~%")
(save-application "darm64cl.image" :purify nil)
