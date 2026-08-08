;;;; Dump full darm64cl.image from arm64-boot.image (darwinarm64).
;;;;
;;;;   ./darm64cl --image-name arm64-boot.image --no-init --batch \
;;;;     < tools/save-darwinarm64-image.lisp
;;;;
;;;; Purify currently faults (EFAULT) on Darwin/arm64 with the dual-map
;;;; RX heap alias — save with :purify nil until AREA_CODE/MAP_JIT lands.

(in-package "CCL")

(format t "~&;; save-application darm64cl.image :purify nil~%")
(save-application "darm64cl.image" :purify nil)
