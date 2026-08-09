;;;; Stock-like (rebuild-ccl :full t) — native xload, no Rosetta.
(in-package "CCL")
(setq *warn-if-redefine-kernel* nil
      *cerror-on-constant-redefinition* nil
      *load-verbose* t
      *compile-verbose* t)
(load "ccl:compiler;ARM64;arm64-backend.lisp")
(load "ccl:lib;misc.lisp")
(load "ccl:lib;compile-ccl.lisp")
(ensure-darwinarm64-target-arch)
(setq *arm64-backend* *darwinarm64-backend*
      *host-backend* *darwinarm64-backend*
      *target-backend* *darwinarm64-backend*)
(format t "~&;; (rebuild-ccl :full t) nil=#x~x~%"
        (arch::target-nil-value (backend-target-arch *host-backend*)))
(force-output)
(rebuild-ccl :full t)
(format t "~&;; REBUILD-CCL-FULL-NATIVE-OK~%")
(force-output)
(quit 0)
