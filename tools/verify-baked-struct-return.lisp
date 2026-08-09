;;;; Verify struct-return ABI is baked into the image (no source reload).
(in-package :ccl)
(use-interface-dir :cocoa)
(assert (fboundp 'arm64::classify-record-return))
(assert (eq (arm64::classify-record-return (parse-foreign-type :<NSS>ize)) :hfa))
(assert (eq (arm64::classify-record-return (parse-foreign-type :<NSR>ect)) :hfa))
(assert (eq (arm64::classify-record-return (parse-foreign-type :<NSR>ange)) :gpr))
(require "OBJC-SUPPORT")
(objc:with-autorelease-pool
  (let* ((font (#/systemFontOfSize: ns:ns-font 12.0d0))
         (g (#/glyphWithName: font #@"i"))
         (adv (#/advancementForGlyph: font g))
         (bb (#/boundingRectForGlyph: font g)))
    (format t "~&;; adv=~s bbox-w=~s~%"
            (ns:ns-size-width adv) (ns:ns-rect-width bb))
    (assert (plusp (ns:ns-size-width adv)))))
(format t "~&BAKED-STRUCT-RETURN-OK~%")
(quit)
