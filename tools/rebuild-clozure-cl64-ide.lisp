;;;; Rebuild Clozure CL64.app IDE heap from tip fasls (no event loop).
;;;;   ./darm64cl --no-init --batch < tools/rebuild-clozure-cl64-ide.lisp
;;;; Or: ./tools/with-timeout 300 ./darm64cl --no-init --batch --eval '(load "tools/rebuild-clozure-cl64-ide.lisp")'
(in-package :ccl)

;; Match cocoa-application.lisp, but keep headers/altconsole flags conservative
;; for a workspace rebuild (avoid copying interfaces into the bundle).
(defvar *cocoa-ide-path* "ccl:Clozure CL64.app;")
(defvar *cocoa-ide-copy-headers-p* nil)
(defvar *cocoa-ide-install-altconsole* nil)
(defvar *cocoa-ide-bundle-suffix*
  (multiple-value-bind (os bits cpu) (host-platform)
    (declare (ignore os))
    (format nil "Clozure CL-~a~a" (string-downcase cpu) bits)))
(defvar *cocoa-ide-force-compile* nil)
(defvar *cocoa-ide-frameworks* nil)
(defvar *cocoa-ide-libraries* nil)

(format t "~&;; rebuild IDE → ~s~%" *cocoa-ide-path*)
(force-output)

(assert (probe-file *cocoa-ide-path*) ()
        "Bundle missing: ~s" *cocoa-ide-path*)

;; Backup current heap before overwrite
(let* ((img (merge-pathnames
             (make-pathname :name (standard-kernel-name) :type "image")
             (merge-pathnames ";Contents;Resources;ccl;" *cocoa-ide-path*)))
       (bak (make-pathname :defaults img :type "image.pre-tip-rebuild")))
  (when (probe-file img)
    (copy-file img bak :if-exists :supersede)
    (format t "~&;; backed up ~s → ~s~%" img bak)
    (force-output)))

(load "ccl:cocoa-ide;defsystem.lisp")
(load-ide *cocoa-ide-force-compile*)

;; Ensure tip Listener/modeline fixes are what we bake (fasls already tip).
(format t "~&;; building (save-application cocoa-ide)~%")
(force-output)
(gui::build-ide *cocoa-ide-path*)
;; build-ide save-application does not return
