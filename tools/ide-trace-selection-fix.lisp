;;;; Live patch: Trace on a selected form like (+ 1 2) must not enqueue
;;;; (TRACE (+ 1 2)).  Load into a running Cocoa IDE (or via home:ccl-init).
;;;;
;;;;   (load "ccl:tools;ide-trace-selection-fix.lisp")
(in-package :gui)

(defun find-symbol-in-buffer-packages (string buffer)
  (let ((package-name (ignore-errors
                        (hi::variable-value 'hemlock::current-package :buffer buffer)))
        (packages nil))
    (unless (find #\: string)
      (let* ((pkg (and package-name (find-package package-name)))
             (preferred (and pkg (cons package-name (package-use-list pkg)))))
        (setf packages (if preferred
                         (append preferred
                                 (set-difference (list-all-packages) preferred))
                         (list-all-packages)))))
    (find-symbol-in-packages string packages)))

(defun traceable-selection (raw)
  (cond ((and (symbolp raw) (not (null raw))) raw)
        ((and (consp raw) (symbolp (car raw))) (car raw))
        (t nil)))

(objc:defmethod (#/traceSelection: :void) ((self hemlock-text-view) sender)
  (declare (ignore sender))
  (with-string-under-cursor (self symbol-name buffer)
    (let* ((raw (find-symbol-in-buffer-packages symbol-name buffer))
           (sym (traceable-selection raw)))
      (if sym
        (eval-in-listener (format nil "(trace ~S)" sym))
        (#_NSBeep)))))

(format t "~&;; ide-trace-selection-fix loaded~%")
(force-output)
