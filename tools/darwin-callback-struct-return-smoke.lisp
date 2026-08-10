;;;; Darwin/arm64 inbound callback composite returns (blanket ABI fix).
;;;;
;;;; Bug class: generate-callback-bindings treated EVERY foreign-record
;;;; return as a hidden stret pointer in x0.  For :gpr (NSRange) / :hfa
;;;; (NSRect) that stole `self` on ObjC IMPs → memmove into the object →
;;;; object_getClass EXC_BREAKPOINT (mouse select /
;;;; #/selectionRangeForProposedRange:granularity:).
;;;;
;;;;   ./darm64cl --no-init --batch < tools/darwin-callback-struct-return-smoke.lisp
(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)

(format t "~&;; darwin-callback-struct-return-smoke~%")
(finish-output)

(use-interface-dir :cocoa)

;; Tip generators (image may still have the all-stret version).
(load (merge-pathnames "lib/ffi-linuxarm64.lisp" (ccl-directory)))
(load (merge-pathnames "lib/ffi-darwinarm64.lisp" (ccl-directory)))
(setf (ftd-callback-bindings-function *target-ftd*)
      #'arm64-darwin::generate-callback-bindings)
(setf (ftd-callback-return-value-function *target-ftd*)
      #'arm64-darwin::generate-callback-return-value)

(assert (eq (arm64::classify-record-return (parse-foreign-type :<NSR>ange)) :gpr))
(assert (eq (arm64::classify-record-return (parse-foreign-type :<NSR>ect)) :hfa))

;; :gpr must NOT prepend a hidden :address (would bind x0 = first real arg).
(multiple-value-bind (rlets lets dx inits rtype fp lr)
    (arm64-darwin::generate-callback-bindings
     'sp 'fp '(loc len) '(:unsigned-long :unsigned-long) :<NSR>ange 'out)
  (declare (ignore lets dx inits fp lr))
  (assert (assoc 'out rlets) () "NSRange callback missing local out rlet: ~s" rlets)
  (assert (typep rtype 'foreign-record-type) () "NSRange return collapsed to ~s" rtype)
  (format t "~&;; NSRange bindings: local out, record rtype ok~%")
  (finish-output))

(multiple-value-bind (rlets lets dx inits rtype fp lr)
    (arm64-darwin::generate-callback-bindings
     'sp 'fp '() '() :<NSR>ect 'out)
  (declare (ignore lets dx inits lr))
  (assert (assoc 'out rlets) () "NSRect callback missing local out rlet: ~s" rlets)
  (assert fp () "NSRect HFA return must bind fp-args-ptr")
  (assert (typep rtype 'foreign-record-type) () "NSRect return collapsed to ~s" rtype)
  (format t "~&;; NSRect bindings: local out + fp-save ok~%")
  (finish-output))

;; Live round-trip: Lisp→C ABI→callback→registers→Lisp.
(defcallback %smoke-make-nsrange
    (out :unsigned-long loc :unsigned-long len :<NSR>ange)
  (setf (pref out :<NSR>ange.location) loc
        (pref out :<NSR>ange.length) len)
  out)

(rlet ((got :<NSR>ange))
  (ff-call %smoke-make-nsrange
           :unsigned-long 42
           :unsigned-long 7
           :<NSR>ange got)
  (assert (= (pref got :<NSR>ange.location) 42))
  (assert (= (pref got :<NSR>ange.length) 7))
  (format t "~&;; NSRange callback round-trip ok (~d,~d)~%"
          (pref got :<NSR>ange.location)
          (pref got :<NSR>ange.length))
  (finish-output))

(defcallback %smoke-make-nsrect
    (out :double x :double y :double w :double h :<NSR>ect)
  (setf (pref out :<NSR>ect.origin.x) x
        (pref out :<NSR>ect.origin.y) y
        (pref out :<NSR>ect.size.width) w
        (pref out :<NSR>ect.size.height) h)
  out)

(rlet ((got :<NSR>ect))
  (ff-call %smoke-make-nsrect
           :double 1.0d0 :double 2.0d0
           :double 3.0d0 :double 4.0d0
           :<NSR>ect got)
  (assert (= (pref got :<NSR>ect.origin.x) 1.0d0))
  (assert (= (pref got :<NSR>ect.origin.y) 2.0d0))
  (assert (= (pref got :<NSR>ect.size.width) 3.0d0))
  (assert (= (pref got :<NSR>ect.size.height) 4.0d0))
  (format t "~&;; NSRect HFA callback round-trip ok~%")
  (finish-output))

(format t "~&;; PASS darwin-callback-struct-return-smoke~%")
(quit 0)
)
