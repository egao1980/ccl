;;;; Rebuild callback fasls after MAP_JIT fix (darwinarm64).
;;;;
;;;;   CCL_DEFAULT_DIRECTORY=$PWD arch -x86_64 ./dx86cl64 --no-init --batch \
;;;;     < tools/rebuild-darwinarm64-callback-fasls.lisp

(in-package "CCL")

(setq *warn-if-redefine-kernel* nil
      *cerror-on-constant-redefinition* nil
      *save-source-locations* nil
      *load-verbose* t
      *compile-verbose* t)

(load "ccl:compiler;nxenv.lisp")
(load "ccl:compiler;backend.lisp")
(load "ccl:compiler;nx1.lisp")
(load "ccl:compiler;acode-rewrite.lisp")
(load "ccl:tools;xdarwinarm64.lisp")

(unless (find-backend :darwinarm64)
  (error "darwinarm64 backend missing"))

;; compile-file only swaps *features* when *target-backend* ≠ *host-backend*.
;; Without this binding, #+arm64-target / #+darwin-target strips MAP_JIT.
(with-cross-compilation-target (:darwinarm64)
  (let ((*target-backend* (find-backend :darwinarm64)))
    (target-compile-modules '(l1-callbacks arm64-callback-support) :darwinarm64 t)))

(format t "~&;; rebuilt l1-callbacks + arm64-callback-support for darwinarm64~%")

(quit)
)