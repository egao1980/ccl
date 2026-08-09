;;;; Bootstrap arm64-boot.image on a stock Darwin/x8664 host (e.g. CCL 1.13).
;;;;
;;;; Usage (Rosetta host kernel + writable image):
;;;;   CCL_DEFAULT_DIRECTORY=$PWD arch -x86_64 ./dx86cl64 --no-init --batch \\
;;;;     < tools/bootstrap-darwinarm64-boot.lisp
;;;;
;;;; Requires: provisional ccl:darwin-arm64-headers; (see doc/porting/darwin.md),
;;;; and a built ./darm64cl from lisp-kernel/darwinarm64.

(in-package "CCL")

(setq *warn-if-redefine-kernel* nil
      *cerror-on-constant-redefinition* nil
      *save-source-locations* nil
      *load-verbose* t
      *compile-verbose* t)

(format t "~&;; host=~a~%" (lisp-implementation-version))

;; Stock host images lack arm64 nx operators / arm64-lap-function nx1 hook.
(load "ccl:compiler;nxenv.lisp")
(load "ccl:compiler;backend.lisp")
(load "ccl:compiler;nx1.lisp")

(unless (assq 'aapcs64-ff-call *next-nx-operators*)
  (error "nxenv load did not install aapcs64-ff-call"))

;; Loading nxenv reassigns operator IDs.  Host fasls (acode-rewrite, etc.)
;; registered rewrite handlers under the OLD IDs, so aapcs64-ff-call had
;; no rewrite entry — cross-compile then emitted `mov xN,rnil` for
;; (ff-call (%kernel-import …) :address) inside %setf-macptr.  Reload.
(load "ccl:compiler;acode-rewrite.lisp")
(let* ((id (logand operator-id-mask (%nx1-operator aapcs64-ff-call)))
       (fn (svref *acode-rewrite-functions* id)))
  (unless fn
    (error "aapcs64-ff-call rewrite not registered after acode-rewrite reload (id=~s)"
           id))
  (format t "~&;; aapcs64-ff-call rewrite id=~s => ~s~%" id fn))

(load "ccl:tools;xdarwinarm64.lisp")

(unless (find-backend :darwinarm64)
  (error "darwinarm64 backend missing after xdarwinarm64 load"))
(unless (find-xload-backend :darwinarm64)
  (error "darwinarm64 xload backend missing"))

(format t "~&;; cross-compile-ccl :darwinarm64~%")
(cross-compile-ccl :darwinarm64 t)

(format t "~&;; cross-xload-level-0 :darwinarm64~%")
(cross-xload-level-0 :darwinarm64 :force)

(let ((img (probe-file "ccl:ccl;arm64-boot.image")))
  (format t "~&;; boot image => ~s~%" img)
  (unless img (quit 1)))

(quit 0)
