;;;; Rebuild fasls needed after ffi-linuxarm64 cold-load dependency fix.
;;;;
;;;;   CCL_DEFAULT_DIRECTORY=$PWD arch -x86_64 ./dx86cl64 --no-init --batch \
;;;;     < tools/rebuild-darwinarm64-ffi-fasls.lisp

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

(with-cross-compilation-target (:darwinarm64)
  (let ((*target-backend* (find-backend :darwinarm64)))
    (target-compile-modules '(ffi-linuxarm64 ffi-darwinarm64 l1-boot-2)
                            :darwinarm64 t)))

(format t "~&;; rebuilt ffi-linuxarm64 + ffi-darwinarm64 + l1-boot-2~%")
(quit)
)