;;;; Inject YES/NO into cocoa constants.cdb (Darwin/arm64).
;;;;
;;;; Modern objc.h maps YES/NO to __objc_yes/__objc_no (not numeric), so
;;;; regenerated CDBs lack the historical YES=1 NO=0 entries objc-bridge
;;;; needs.  Full cocoa reparse is fine after populate installs the shim
;;;; ffi; this script is a fast surgical fix for an already-parsed tree.
;;;;
;;;;   ./darm64cl --no-init --batch < tools/darwin-arm64-cdb/inject-objc-bool-constants.lisp
(in-package :ccl)

(defun %inject-objc-bool-constants (&optional (dirname "cocoa"))
  (use-interface-dir (intern (string-upcase dirname) :keyword))
  (let* ((d (require-interface-dir (intern (string-upcase dirname) :keyword)))
         (old (db-constants d))
         (dir (merge-pathnames (interface-dir-subdir d)
                               (ftd-interface-db-directory *target-ftd*)))
         (newpath (merge-pathnames "new-constants.cdb" dir))
         (pkg (find-package (ftd-interface-package-name *target-ftd*)))
         (n 0)
         (had-yes (db-lookup-constant old (intern "YES" pkg)))
         (had-no (db-lookup-constant old (intern "NO" pkg))))
    (format t "~&;; cocoa constants: YES=~s NO=~s~%" had-yes had-no)
    (when (and had-yes had-no)
      (format t "~&;; already present; nothing to do~%")
      (return-from %inject-objc-bool-constants nil))
    (format t "~&;; rewriting constants.cdb with YES=1 NO=0 ...~%")
    (with-new-db-file (cdbm newpath)
      (dolist (k (cdb-enumerate-keys old))
        (let* ((sym (intern k pkg))
               (v (db-lookup-constant old sym)))
          (when v
            (db-define-constant cdbm k v)
            (incf n))))
      (unless had-yes (db-define-constant cdbm "YES" 1))
      (unless had-no (db-define-constant cdbm "NO" 0)))
    (cdb-close old)
    (setf (interface-dir-constants-interface-db-file d) nil)
    (let* ((path (merge-pathnames "constants.cdb" dir)))
      (when (probe-file path)
        (rename-file path
                     (concatenate 'string (namestring (truename path)) "-pre-yesno")
                     :if-exists :supersede))
      (rename-file newpath path))
    (format t "~&;; INJECT-OBJC-BOOL-OK copied=~d added YES/NO~%" n)
    t))

(%inject-objc-bool-constants)
(quit 0)
