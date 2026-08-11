;;; Frame-only no-class-error logger + safer %show-stack-frame-label.
;;; Avoid loading full cocoa-utils.lisp into a live IDE (too many redefs).
(in-package :cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (unless (find-package :gui)
    (error "ide-noclass-bt-patch: GUI package missing (not a cocoa image?)")))

;;; --- lib/backtrace.lisp: never ~s stack args when detailed-p is NIL ---
(in-package :ccl)
(defun %show-stack-frame-label (frame-number p context lfun pc detailed-p)
  (flet ((frame-label ()
           (cond ((null lfun) "<non-function frame>")
                 (detailed-p
                  (let ((call (backtrace-call-arguments context p lfun pc)))
                    (if (eq *backtrace-format* :direct) (car call) call)))
                 (t (or (ignore-errors (function-name lfun))
                        (ignore-errors (%lfun-name-string lfun))
                        lfun)))))
    (case *backtrace-format*
      (:direct
       (format t "~&~3D: ~a ~a~@d~:[~; [Exception]~]"
               frame-number (frame-label) "at pc " pc (exception-frame-p p)))
      (t
       (format t "~&~c(~x) : ~D ~a ~d"
               (if (exception-frame-p p) #\* #\space)
               (index->address p) frame-number (frame-label) pc)))))

;;; --- cocoa-utils logger bits ---
(in-package :gui)

(defun %safe-frame-name (lfun)
  (or (ignore-errors (function-name lfun))
      (ignore-errors (ccl::%lfun-name-string lfun))
      (ignore-errors (princ-to-string lfun))
      "<fn>"))

(defun %safe-call-history-lines (&optional (count 60))
  "Frame names only — never format stack slot values (BOGUS → CLASS-OF loop)."
  (let ((i 0) (lines '()))
    (ignore-errors
      (ccl:map-call-frames
       (lambda (p context)
         (declare (ignore context))
         (when (< i count)
           (multiple-value-bind (lfun pc) (ccl::cfp-lfun p)
             (push (format nil "  ~d ~a pc=~a"
                           i
                           (if lfun (%safe-frame-name lfun) "<non-function>")
                           pc)
                   lines))
           (incf i)))
       :count count
       :test nil))
    (nreverse lines)))

(defun %log-hemlock-condition (condition &optional (path "/tmp/ccl-hemlock-err.log"))
  "Append CONDITION summary + frame-only BT. Never walk stack arg slots."
  (ignore-errors
    (with-open-file (s path :direction :output
                       :if-exists :append :if-does-not-exist :create)
      (format s "~&==== ~a ====~%" (get-universal-time))
      (format s "condition-class=~s~%"
              (ignore-errors (class-name (class-of condition))))
      (format s "emsg=~a~%"
              (or (ignore-errors (princ-to-string condition)) "<unprintable>"))
      (when (typep condition 'type-error)
        (format s "datum=~a expected=~s~%"
                (%safe-object-id (type-error-datum condition))
                (ignore-errors (type-error-expected-type condition))))
      (dolist (line (%safe-call-history-lines 60))
        (write-line line s))
      (terpri s)
      (force-output s))))

(defun %install-no-class-error-logger (&key force)
  (when (and force *%original-no-class-error*)
    (setf (fdefinition 'ccl::no-class-error) *%original-no-class-error*)
    (setq *%original-no-class-error* nil))
  (unless *%original-no-class-error*
    (setq *%original-no-class-error* (fdefinition 'ccl::no-class-error))
    (setf (fdefinition 'ccl::no-class-error)
          (lambda (x)
            (unless *%logging-no-class-error*
              (let ((*%logging-no-class-error* t))
                (ignore-errors
                  (with-open-file (s "/tmp/ccl-no-class-error.log" :direction :output
                                     :if-exists :append :if-does-not-exist :create)
                    (format s "~&==== ~a id=~a proc=~s ====~%"
                            (get-universal-time)
                            (%safe-object-id x)
                            (ignore-errors (process-name *current-process*)))
                    (format s "whostate=~s~%"
                            (ignore-errors (process-whostate *current-process*)))
                    (dolist (line (%safe-call-history-lines 60))
                      (write-line line s))
                    (terpri s)
                    (force-output s)))))
            (error "Bug (probably): can't determine class of object ~a"
                   (%safe-object-id x))))))

(%install-no-class-error-logger :force t)

(in-package :cl-user)
(format t "~&;; ide-noclass-bt-patch loaded (log → /tmp/ccl-no-class-error.log)~%")
