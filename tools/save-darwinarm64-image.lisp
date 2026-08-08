;;;; Dump full darm64cl.image from arm64-boot.image (darwinarm64).
;;;;
;;;;   ./darm64cl --image-name arm64-boot.image --no-init --batch \
;;;;     < tools/save-darwinarm64-image.lisp
;;;;
;;;; Purify RX on pure is fixed; experimental `:purify t` smoke is green
;;;; (tools/run-darwin-purify-smoke.sh).  Production save still uses
;;;; :purify nil until dual-map is dropped for a fully purified +
;;;; MAP_JIT-only runtime (fasl cold-load still dual-maps IMAGE_BASE).
;;;;
;;;; Clear *outstanding-deferred-warnings* before dump: saving from inside
;;;; with-compilation-unit (compile-ccl) otherwise leaves a parent unit in
;;;; the image and compile-file deferred warnings never signal.

(in-package "CCL")

(setq *outstanding-deferred-warnings* nil)
(format t "~&;; save-application darm64cl.image :purify nil~%")
(save-application "darm64cl.image" :purify nil)
