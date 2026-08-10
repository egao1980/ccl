;;;; Stepped Listener frame create — isolate makeWindowControllers death.
;;;;   ./tools/run-darwin-ide-smoke.sh 120 tools/listener-frame-steps.lisp FRAME-STEPS-DONE
(in-package :ccl)

(defun %lfs-log (fmt &rest args)
  (apply #'format t fmt args) (terpri) (force-output)
  (with-open-file (s "/tmp/listener-frame-steps-detail.log" :direction :output
                     :if-exists :append :if-does-not-exist :create)
    (apply #'format s fmt args) (terpri s) (force-output s)))

(ignore-errors (delete-file "/tmp/listener-frame-steps-detail.log"))

(defun %lfs-rect (label r)
  (%lfs-log "~a => x=~s y=~s w=~s h=~s typed=~s"
            label
            (ignore-errors (ns:ns-rect-x r))
            (ignore-errors (ns:ns-rect-y r))
            (ignore-errors (ns:ns-rect-width r))
            (ignore-errors (ns:ns-rect-height r))
            (ignore-errors (typep r 'ns:ns-rect))))

(unless (fboundp '%invoke-objc-send-function)
  (error "missing tip CNM"))

(%lfs-log "require COCOA…")
(require "COCOA")
(let ((ok (timed-wait-on-semaphore gui::*cocoa-ide-finished-launching* 45)))
  (%lfs-log "finished-launching => ~s" ok)
  (unless ok (error "IDE did not finish launching")))

(dolist (sig '((:<NSR>ect)
               (:<CGR>ect)
               (:<NSP>oint)
               (:<NSS>ize)
               (:<NSR>ange :<NSR>ect (:* (:struct :<NST>ext<C>ontainer)))
               (:<NSR>ange :<NSR>ange (:* :<NSR>ange))
               (:void :<NSUI>nteger (:struct :<NSR>ange) :<NSI>nteger)
               (:void :<NSI>nteger :<NSI>nteger :<NSI>nteger)))
  (handler-case
      (let ((f (compile-send-function-for-signature sig)))
        (setf (objc-method-signature-info-function
               (objc-method-signature-info sig))
              f)
        (%lfs-log "precompile ~s ok" sig))
    (error (c) (%lfs-log "precompile fail ~s: ~a" sig c))))

(defun %lfs-probe ()
  (objc:with-autorelease-pool
    (#/setActivationPolicy: *nsapp* 0)
    (#/activateIgnoringOtherApps: *nsapp* #$YES)
    (let* ((dc (#/sharedDocumentController ns:ns-document-controller))
           (doc (#/makeUntitledDocumentOfType:error: dc #@"Listener" +null-ptr+)))
      (%lfs-log "doc null=~s" (%null-ptr-p doc))
      (#/addDocument: dc doc)
      (let* ((ts (slot-value doc 'gui::textstorage))
             (buf (gui::hemlock-buffer ts)))
        (%lfs-log "ts null=~s buf=~s" (%null-ptr-p ts) buf)

        (%lfs-log "A1 new-cocoa-window…")
        (let ((w (gui::new-cocoa-window :class gui::hemlock-listener-frame :activate nil)))
          (%lfs-log "A1 ok")
          (%lfs-rect "A1 frame" (#/frame w))
          (%lfs-rect "A1 content bounds" (#/bounds (#/contentView w)))

          (%lfs-log "A2 add-pane-to-window…")
          (let* ((echo-h (+ 1 (gui::size-of-char-in-font gui::*editor-font*)))
                 (pane (gui::add-pane-to-window w :reserve-below echo-h)))
            (%lfs-log "A2 ok")
            (%lfs-rect "A2 pane frame" (#/frame pane))
            (%lfs-rect "A2 contentView frame" (#/frame (#/contentView pane)))

            (%lfs-log "A3 make-scrolling-textview-for-pane…")
            (handler-case
                (progn
                  (gui::make-scrolling-textview-for-pane
                   pane ts t
                   (gui::textview-background-color doc)
                   (gui::user-input-style doc))
                  (%lfs-log "A3 ok tv=~s" (gui::text-pane-text-view pane)))
              (error (c)
                (%lfs-log "A3 ERROR: ~a" c)
                (ignore-errors
                  (with-open-file (s "/tmp/listener-frame-steps-bt.log"
                                     :direction :output :if-exists :supersede)
                    (let ((*standard-output* s))
                      (print-call-history :count 50 :detailed-p nil))))
                (error c)))

            (%lfs-log "A4 size-text-pane…")
            (multiple-value-bind (height width)
                (gui::size-of-char-in-font (gui::default-font))
              (gui::size-text-pane pane height width
                                   gui::*listener-rows*
                                   gui::*listener-columns*)
              (%lfs-log "A4 ok"))

            (%lfs-log "A5 make-echo-area-for-window…")
            (handler-case
                (let ((echo (gui::make-echo-area-for-window
                             w buf (gui::textview-background-color doc))))
                  (setf (slot-value w 'gui::echo-area-view) echo)
                  (%lfs-log "A5 ok"))
              (error (c) (%lfs-log "A5 ERROR: ~a" c) (error c)))

            (%lfs-log "A6 hemlock-view (no activate; peer may be null)…")
            (handler-case
                (let* ((tv (gui::text-pane-text-view pane))
                       (echo (slot-value w 'gui::echo-area-view))
                       (echo-buf (gui::hemlock-buffer (#/textStorage echo)))
                       (hview (make-instance 'hi:hemlock-view
                                             :buffer buf
                                             :pane pane
                                             :echo-area-buffer echo-buf)))
                  (setf (slot-value pane 'gui::hemlock-view) hview
                        (slot-value tv 'gui::hemlock-view) hview
                        (slot-value echo 'gui::hemlock-view) hview
                        (slot-value w 'gui::pane) pane)
                  (%lfs-log "A6 ok hview-buf=~s" (hi:hemlock-view-buffer hview)))
              (error (c) (%lfs-log "A6 ERROR: ~a" c) (error c)))))

        (%lfs-log "B full %hemlock-frame-for-textstorage…")
        (handler-case
            (let ((window
                   (gui::%hemlock-frame-for-textstorage
                    gui::hemlock-listener-frame
                    ts
                    gui::*listener-columns*
                    gui::*listener-rows*
                    t
                    (gui::textview-background-color doc)
                    (gui::user-input-style doc))))
              (%lfs-log "B ok window=~s" window))
          (error (c) (%lfs-log "B ERROR: ~a" c) (error c)))

        (%lfs-log "C makeWindowControllers fresh doc…")
        (let ((doc2 (#/makeUntitledDocumentOfType:error: dc #@"Listener" +null-ptr+)))
          (#/addDocument: dc doc2)
          (handler-case
              (progn
                (#/makeWindowControllers doc2)
                (%lfs-log "C ok n=~s" (#/count (#/windowControllers doc2))))
            (error (c) (%lfs-log "C ERROR: ~a" c) (error c))))))
    t))

(call-in-initial-process #'%lfs-probe)
(format t "~&FRAME-STEPS-DONE~%")
(force-output)
(#_exit 0)
