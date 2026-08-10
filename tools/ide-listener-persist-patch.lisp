;;;; Tip Listener persistence patches (load after COCOA).
;;;; Avoids full cocoa-listener reload (class_addIvar).
(in-package :gui)

(defmethod ccl::exit-interactive-process ((p cocoa-listener-process))
  (let ((in (ignore-errors (cocoa-listener-process-input-stream p))))
    (when in
      (ignore-errors (stream-clear-input in))))
  nil)

(defun new-cocoa-listener-process (procname window &key (class 'cocoa-listener-process)
                                                        (initial-function 'ccl::listener-function)
                                                        initargs)
  (declare (special *standalone-cocoa-ide*))
  (let* ((input-stream (make-instance 'cocoa-listener-input-stream))
         (output-stream (make-instance 'cocoa-listener-output-stream
                          :hemlock-view (hemlock-view window))))
    (ccl::make-mcl-listener-process
     procname
     input-stream
     output-stream
     #'(lambda ()
         (mapcar #'(lambda (buf)
                     (when (eq (buffer-process buf) *current-process*)
                       (let ((doc (hi::buffer-document buf)))
                         (when doc
                           (setf (hemlock-document-process doc) nil)
                           (cocoa-close doc nil)))))
                 hi:*buffer-list*))
     :initial-function
     #'(lambda ()
         (setq ccl::*listener-autorelease-pool* (create-autorelease-pool))
         (when (and *standalone-cocoa-ide*
                    (prog1 *first-listener* (setq *first-listener* nil)))
           (ccl::startup-ccl (ccl::application-init-file ccl::*application*))
           (ui-object-note-package *nsapp* *package*))
         ;; Must be CCL::*BATCH-FLAG* — not exported; GUI::*BATCH-FLAG* is a trap.
         (let ((ccl::*batch-flag* nil)
               (ccl::*quit-on-eof* nil))
           (funcall initial-function)))
     :echoing nil
     :class class
     :initargs `(:listener-input-stream ,input-stream
                 :listener-output-stream ,output-stream
                 :listener-window ,window
                 ,@initargs))))

(defmethod ui-object-note-package ((app ns:ns-application) package)
  (let ((proc *current-process*))
    (queue-for-gui #'(lambda ()
                       (dolist (buf hi::*buffer-list*)
                         (when (eq proc (buffer-process buf))
                           (let ((hi::*current-buffer* buf))
                             (hemlock:update-current-package package))))))))
