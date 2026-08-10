(in-package :ccl)
(setq *warn-if-redefine-kernel* nil)
(defmacro objc:defmethod (name (self-arg &rest other-args) &body body &environment env)
  (collect ((arglist)
            (arg-names)
            (arg-types)
            (bool-args)
            (type-assertions))
    (let* ((result-type nil)
           (struct-return-var nil)
           (struct-return-size nil)
           (selector nil)
           (class-p nil)
           (objc-class-name nil))
      (if (atom name)
        (setq selector (string name) result-type :id)
        (setq selector (string (car name)) result-type (concise-foreign-type (or (cadr name) :id))))
      (destructuring-bind (self-name lisp-class-name) self-arg
        (arg-names self-name)
        (arg-types :id)
        ;; Hack-o-rama
        (let* ((lisp-class-name (string lisp-class-name)))
          (if (eq (schar lisp-class-name 0) #\+)
            (setq class-p t lisp-class-name (subseq lisp-class-name 1)))
          (setq objc-class-name (lisp-to-objc-classname lisp-class-name)))
        (let* ((rtype (parse-foreign-type result-type)))
          (when (typep rtype 'foreign-record-type)
            (setq struct-return-var (gensym))
            (setq struct-return-size (ceiling (foreign-type-bits rtype) 8))
            (arglist struct-return-var)))
        (arg-types :<SEL>)
        (arg-names nil)                 ;newfangled
        (dolist (arg other-args)
          (if (atom arg)
            (progn
              (arg-types :id)
              (arg-names arg))
            (destructuring-bind (arg-name arg-type) arg
              (let* ((concise-type (concise-foreign-type arg-type)))
                (unless (eq concise-type :id)
                  (let* ((ftype (parse-foreign-type concise-type)))
                    (if (typep ftype 'foreign-pointer-type)
                      (setq ftype (foreign-pointer-type-to ftype)))
                    (if (and (typep ftype 'foreign-record-type)
                             (foreign-record-type-name ftype))
                      (type-assertions `(%set-macptr-type ,arg-name
                                         (foreign-type-ordinal (load-time-value (%foreign-type-or-record ,(foreign-record-type-name ftype)))))))))
                (arg-types concise-type)
                (arg-names arg-name)))))
        (let* ((arg-names (arg-names))
               (arg-types (arg-types)))
          (do* ((names arg-names)
                (types arg-types))
               ((null types) (arglist result-type))
            (let* ((name (pop names))
                   (type (pop types)))
              (arglist type)
              (arglist name)
              (if (eq type :<BOOL>)
                (bool-args `(setq ,name (not (eql ,name 0)))))))
          (let* ((impname (intern (format nil "~c[~a ~a]"
                                          (if class-p #\+ #\-)
                                          objc-class-name
                                          selector)))
                 (typestring (encode-objc-method-arglist arg-types result-type))
                 (signature (cons result-type (cddr arg-types))))
            (multiple-value-bind (body decls) (parse-body body env)
              
              (setq body `((progn ,@(bool-args) ,@(type-assertions) ,@body)))
              (if (eq result-type :<BOOL>)
                (setq body `((%coerce-to-bool ,@body))))
              (when struct-return-var
                (setq body `((%objc-struct-return ,struct-return-var ,struct-return-size ,@body)))
                (setq body `((flet ((struct-return-var-function ()
                                      ,struct-return-var))
                               (declaim (inline struct-return-var-function))
                               ,@body)))
                (setq body `((macrolet ((objc:returning-foreign-struct ((var) &body body)
                                          `(let* ((,var (struct-return-var-function)))
                                            ,@body)))
                               ,@body))))
              (setq body `((flet ((call-next-method (&rest args)
                                  (declare (dynamic-extent args))
                                  ;; Arm64: do not APPLY into %call-next-*;
                                  ;; pass the &rest list as one argument.
                                  (,(if class-p
                                      '%call-next-objc-class-method-apply
                                      '%call-next-objc-method-apply)
                                   ,self-name
                                   (@class ,objc-class-name)
                                   (@selector ,selector)
                                   ',signature
                                   args)))
                                 (declare (inline call-next-method))
                                 ,@body)))
              `(progn
                (%declare-objc-method
                 ',selector
                 ',objc-class-name
                 ,class-p
                 ',result-type
                 ',(cddr arg-types))
                (defcallback ,impname ( :propagate-throw objc-propagate-throw ,@(arglist))
                  (declare (ignorable ,self-name)
                           (unsettable ,self-name)
                           ,@(unless class-p `((type ,lisp-class-name ,self-name))))
                  ,@decls
                  ,@body)
                (%define-lisp-objc-method
                 ',impname
                 ,objc-class-name
                 ,selector
                 ,typestring
                 ,impname
                 ,class-p)))))))))
