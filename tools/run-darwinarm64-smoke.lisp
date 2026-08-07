;;;; Native Darwin/arm64 bring-up checks.
;;;;
;;;; What we can verify today without a boot image:
;;;;   1. darm64cl kernel binary exists and is arm64 Mach-O
;;;;   2. ARM64 assembler unit tests (encode/decode) on the host cross tools
;;;;
;;;; Full (test-ccl) on native needs arm64-boot.image via cross-xload-level-0.

(in-package :ccl)

(setq *warn-if-redefine-kernel* nil
      *break-on-errors* nil)

(defun %check-native-kernel ()
  (let* ((k (merge-pathnames "darm64cl" (ccl-directory)))
         (probe (probe-file k)))
    (format t "~&;; native kernel ~a => ~a~%" k probe)
    (unless probe
      (error "darm64cl missing — run: make -C lisp-kernel/darwinarm64"))
    ;; Spot-check it is arm64 Mach-O via `file`
    (let* ((s (make-string-output-stream))
           (p (run-program "file" (list (native-translated-namestring k))
                           :output s :error s))
           (out (get-output-stream-string s)))
      (unless (and (eq (external-process-status p) :exited)
                   (search "arm64" out))
        (error "darm64cl is not an arm64 Mach-O: ~a" out))
      (format t "~&;; file: ~a~%" (string-trim '(#\Newline #\Space) out)))
    probe))

(defun %load-arm64-asm-only ()
  "Load just enough to run assembler unit tests — avoid nxenv/arm642 skew
   against the stock 1.13 host image."
  (in-development-mode
    (load "ccl:lib;systems.lisp")
    (load "ccl:lib;compile-ccl.lisp")
    (load "ccl:compiler;backend.lisp"))
  (update-modules '(arm64-arch arm64-asm arm64-lap) t)
  (find-package "ARM64"))

(defun %run-arm64-asm-unit-tests ()
  (load "ccl:compiler;ARM64;tests.lisp")
  (let ((pkg (find-package "ARM64")))
    (unless pkg (error "ARM64 package missing"))
    (flet ((call (name)
             (let ((fn (find-symbol name pkg)))
               (unless (and fn (fboundp fn))
                 (error "missing test ~a" name))
               (format t "~&;; ~a~%" name)
               (finish-output)
               (funcall fn)
               (format t "~&;;   => ok~%"))))
      (call "TEST-LOGICAL-IMMEDIATE-ENCODE-DECODE")
      (call "TEST-FP-IMM8")))
  t)

(defun run-darwinarm64-smoke ()
  (format t "~&;; host=~a~%" (lisp-implementation-version))
  (finish-output)
  (%check-native-kernel)
  (%load-arm64-asm-only)
  (%run-arm64-asm-unit-tests)
  (format t "~&;; DARWINARM64 SMOKE OK (kernel + asm unit tests)~%")
  (format t "~&;; NOTE: full test-ccl on native needs cross-xload boot image~%")
  (quit 0))

(run-darwinarm64-smoke)
