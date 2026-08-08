;;;; objc-bridge smoke — NSObject/NSString message send (darwinarm64).
;;;; Requires regenerated cocoa CDB + working FFI + objc-bridge load.
(in-package :ccl)

(require "OBJC-SUPPORT")

(let* ((s (%make-nsstring "darwinarm64"))
       (len (#/length s)))
  (unless (and (integerp len) (eql len 11))
    (error "NSString length => ~s" len))
  (format t "~&DARWIN-OBJC-BRIDGE-SMOKE-OK len=~d~%" len))
(quit 0)
