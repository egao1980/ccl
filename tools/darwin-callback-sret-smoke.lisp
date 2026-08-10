;;;; Smoke: AAPCS64 :memory (x8 sret) callback return + :gpr still works.
;;;; Needs tip kernel (x9 index trampoline + CBF-16 sret spill) and tip
;;;; inbound generators / frame constants.  No Cocoa.
;;;;   ./darm64cl --no-init --batch --eval '(load "tools/darwin-callback-sret-smoke.lisp")'
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil
      *cerror-on-constant-redefinition* nil)

(defun %sret-smoke-quit (code)
  (finish-output)
  (finish-output *error-output*)
  (ff-call (foreign-symbol-address "exit") :signed-fullword code :void))

(format t "~&;; darwin-callback-sret-smoke~%")
(finish-output)

;; Tip frame offsets (image may still have pre-sret values). No unintern.
(eval '(defconstant arm64::callback-frame.fp-save-offset -80))
(eval '(defconstant arm64::callback-frame.sret-offset -16))
(eval '(defconstant arm64::callback-frame.savelr-offset -168))
(eval '(defconstant arm64::callback-frame.stack-args-offset 64))
(assert (= arm64::callback-frame.fp-save-offset -80))
(assert (= arm64::callback-frame.sret-offset -16))
(format t "~&;; frame offsets ok (fp=~s sret=~s lr=~s)~%"
        arm64::callback-frame.fp-save-offset
        arm64::callback-frame.sret-offset
        arm64::callback-frame.savelr-offset)
(finish-output)

(load (merge-pathnames "lib/ffi-linuxarm64.lisp" (ccl-directory)))
(load (merge-pathnames "lib/ffi-darwinarm64.lisp" (ccl-directory)))
(load (merge-pathnames "level-1/arm64-callback-support.lisp" (ccl-directory)))
(setf (ftd-callback-bindings-function *target-ftd*)
      #'arm64-darwin::generate-callback-bindings)
(setf (ftd-callback-return-value-function *target-ftd*)
      #'arm64-darwin::generate-callback-return-value)
(assert (fboundp 'arm64::classify-record-return))
(assert (fboundp 'arm64::expand-ff-call))

;; Flat field list (CCL struct translator takes &rest fields).
(def-foreign-type :sret_triple
  (:struct :sret_triple
    (:a :unsigned-doubleword)
    (:b :unsigned-doubleword)
    (:c :unsigned-doubleword)))

(def-foreign-type :gpr_pair
  (:struct :gpr_pair
    (:a :unsigned-doubleword)
    (:b :unsigned-doubleword)))

(assert (eq (arm64::classify-record-return (parse-foreign-type :sret_triple))
            :memory))
(assert (eq (arm64::classify-record-return (parse-foreign-type :gpr_pair))
            :gpr))
(format t "~&;; classify ok~%")
(finish-output)

;; :memory bindings must NOT prepend a fake :address arg (x0 stays first real arg).
(multiple-value-bind (rlets lets dx inits rtype fp lr)
    (arm64-darwin::generate-callback-bindings
     'sp 'fp '(a b)
     '(:unsigned-doubleword :unsigned-doubleword)
     :sret_triple
     'out)
  (declare (ignore rlets dx inits fp lr))
  (assert (assoc 'out lets) () "missing sret let: ~s" lets)
  (assert (eq rtype *void-foreign-type*))
  (assert (equal (cadr (assoc 'a lets))
                 '(%%get-unsigned-longlong sp (+ 0 0)))
          () "first real arg not in x0: ~s" lets)
  (format t "~&;; :memory bindings ok (sret @ CBF~s)~%"
          arm64::callback-frame.sret-offset)
  (finish-output))

(defcallback %smoke-make-triple
    (out :unsigned-doubleword a :unsigned-doubleword b :sret_triple)
  (progn
    (setf (pref out :sret_triple.a) a
          (pref out :sret_triple.b) b
          (pref out :sret_triple.c) (+ a b))
    out))

(rlet ((got :sret_triple))
  (ff-call %smoke-make-triple
           got
           :unsigned-doubleword 10
           :unsigned-doubleword 20
           :sret_triple)
  (assert (= (pref got :sret_triple.a) 10))
  (assert (= (pref got :sret_triple.b) 20))
  (assert (= (pref got :sret_triple.c) 30))
  (format t "~&;; :memory callback round-trip ok (~d,~d,~d)~%"
          (pref got :sret_triple.a)
          (pref got :sret_triple.b)
          (pref got :sret_triple.c))
  (finish-output))

(defcallback %smoke-make-pair
    (out :unsigned-doubleword a :unsigned-doubleword b :gpr_pair)
  (progn
    (setf (pref out :gpr_pair.a) a
          (pref out :gpr_pair.b) b)
    out))

(rlet ((got :gpr_pair))
  (ff-call %smoke-make-pair
           got
           :unsigned-doubleword 42
           :unsigned-doubleword 7
           :gpr_pair)
  (assert (= (pref got :gpr_pair.a) 42))
  (assert (= (pref got :gpr_pair.b) 7))
  (format t "~&;; :gpr pair still ok (~d,~d)~%"
          (pref got :gpr_pair.a) (pref got :gpr_pair.b))
  (finish-output))

(format t "~&;; PASS darwin-callback-sret-smoke~%")
(%sret-smoke-quit 0)
)
