;;;; -*- Mode: Lisp; Package: CCL -*-
;;;;
;;;; SPDX-License-Identifier: Apache-2.0

(in-package "CCL")

(next-nx-defops)
(defvar *arm642-specials* nil)
(let* ((newsize (%i+ (next-nx-num-ops) 10))
       (old *arm642-specials*)
       (oldsize (length old)))
  (declare (fixnum newsize oldsize))
  (unless (>= oldsize newsize)
    (let* ((v (make-array newsize :initial-element nil)))
      (dotimes (i oldsize (setq *arm642-specials* v))
        (setf (svref v i) (svref old i))))))

(defvar *arm64-vinsn-templates* (make-hash-table :test #'eq))
(defvar *known-arm64-backends* ())

;;; This defines a template.  All expressions in the body must be
;;; evaluable at macroexpansion time.
(defun %define-arm64-vinsn (backend vinsn-name results args temps body)
  (let* ((arch-name (backend-target-arch-name backend))
         (template-hash (backend-p2-template-hash-name backend))
         (name-list ())
         (attrs 0)
         (nhybrids 0)
         (local-labels ())
         (referenced-labels ())
         (source-indicator (form-symbol arch-name "-VINSN"))
         (opcode-alist ()))
    (flet ((valid-spec-name (x)
             (or (and (consp x)
                      (consp (cdr x))
                      (endp (cddr x))
                      (atom (car x))
                      (or (assoc (cadr x) *vreg-specifier-constant-constraints*
                                 :test #'eq)
                          (assoc (cadr x) *spec-class-storage-class-alist*
                                 :test #'eq)
                          (eq (cadr x) :label)
                          (and (consp (cadr x))
                               (or (assoc (caadr x)
                                          *vreg-specifier-constant-constraints*
                                          :test #'eq)
                                   (assoc (caadr x)
                                          *spec-class-storage-class-alist*
                                          :test #'eq))))
                      (car x))
                 (error "Invalid vreg spec: ~s" x)))
           (add-spec-name (vname)
             (if (member vname name-list :test #'eq)
               (error "Duplicate name ~s in vinsn ~s" vname vinsn-name)
               (push vname name-list))))
      (declare (dynamic-extent #'valid-spec-name #'add-spec-name))
      (when (consp vinsn-name)
        (setq attrs (encode-vinsn-attributes (cdr vinsn-name))
              vinsn-name (car vinsn-name)))
      (unless (and (symbolp vinsn-name)
                   (eq *ccl-package* (symbol-package vinsn-name)))
        (setq vinsn-name (intern (string vinsn-name) *ccl-package*)))
      (dolist (n (append args temps))
        (add-spec-name (valid-spec-name n)))
      (setq name-list (nreverse name-list))
      ;; We now know that "args" is an alist; we don't know if
      ;; "results" is.  First, make sure that there are no duplicate
      ;; result names (and validate "results".)
      (do* ((res results tail)
            (tail (cdr res) (cdr tail)))
           ((null res))
        (let ((name (valid-spec-name (car res))))
          (if (assoc name tail :test #'eq)
            (error "Duplicate result name ~s in ~s." name results))))
      (let ((non-hybrid-results ())
            (match-args args))
        (dolist (res results)
          (let ((res-name (car res)))
            (if (not (assoc res-name args :test #'eq))
              (if (not (= nhybrids 0))
                (error "result ~s should also name an argument." res-name)
                (push res-name non-hybrid-results))
              (if (eq res-name (caar match-args))
                (setf nhybrids (1+ nhybrids)
                      match-args (cdr match-args))
                (error "~S - hybrid results should appear in same ~
                        order as arguments." res-name)))))
        (dolist (name non-hybrid-results)
          (add-spec-name name)))
      (let* ((k -1))
        (declare (fixnum k))
        (let* ((name-alist (mapcar #'(lambda (n) (cons n (list (incf k))))
                                   name-list))
               ;; Map each parameter name to its storage-class keyword, so
               ;; VINSN-SIMPLIFY-INSTRUCTION can tell an X operand from a W,
               ;; D, or S when selecting a template.  A wired spec is
               ;; (class value) (e.g. (:u64 imm0) or (:crf 0)); we want just
               ;; the class keyword, not the whole list.
               (param-types (mapcar #'(lambda (s)
                                        (let ((class (cadr s)))
                                          (cons (car s)
                                                (if (consp class)
                                                  (car class)
                                                  class))))
                                    (append results args temps))))
          (labels ((find-name (n)
                   (let* ((pair (assoc n name-alist :test #'eq)))
                     (declare (list pair))
                     (if pair
                       (cdr pair)
                       (or (subprim-name->offset n backend)
                           (error "Unknown name ~s" n)))))
                   (simplify-operand (op)
                     (if (atom op)
                       (if (typep op 'fixnum)
                         op
                         (if (constantp op)
                           (progn
                             (if (keywordp op)
                               (pushnew op referenced-labels))
                             (eval op))
                           (find-name op)))
                       (if (eq (car op) :apply)
                         `(,(cadr op) ,@(mapcar #'simplify-operand (cddr op)))
                         (simplify-operand (eval op))))) ; Handler-case this?
                   (simplify-constraint (guard)
                     ;; A constraint is one of
                     ;;
                     ;; (:eq|:lt|:gt vreg-name constant)
                     ;;
                     ;; value" of vreg relop constant
                     ;;
                     ;; (:pred <function-name> <operand>* ;
                     ;; <function-name> unquoted, each <operand>
                     ;; is a vreg-name or constant expression.
                     ;;
                     ;; (:type vreg-name typeval) ; vreg is of
                     ;; "type" typeval
                     ;;
                     ;;(:not <constraint>) ; constraint is false
                     ;; (:and <constraint> ...)        ;  conjuntion
                     ;; (:or <constraint> ...)         ;  disjunction
                     ;; There's no "else"; we'll see how ugly it
                     ;; is without one.
                     (destructuring-bind (guardname &rest others) guard
                       (ecase guardname
                         (:not
                          (destructuring-bind (negation) others
                            `(:not ,(simplify-constraint negation))))
                         (:pred
                          (destructuring-bind (predicate &rest operands) others
                            `(:pred ,predicate ,@(mapcar #'simplify-operand
                                                         operands))))
                         ((:eq :lt :gt :type)
                          (destructuring-bind (vreg constant) others
                            (unless (constantp constant)
                              (error "~s: not constant in constraint ~s."
                                     constant guard))
                            `(,guardname ,(find-name vreg) ,(eval constant))))
                         ((:or :and)
                          (unless others
                            (error "Missing constraint list in ~s ." guard))
                          `(,guardname ,(mapcar
                                         #'simplify-constraint others))))))
                   (simplify-form (form)
                     (if (atom form)
                       (progn
                         (if (keywordp form) (push form local-labels))
                         form)
                       (destructuring-bind (&whole w opname &rest opvals) form
                         (if (consp opname) ; A constraint, we presume ...
                           (cons (simplify-constraint opname)
                                 (mapcar #'simplify-form opvals))
                           (if (keywordp opname)
                             form
                             (multiple-value-bind (simplified entry)
                                 (arm64::vinsn-simplify-instruction
                                  form name-list param-types)
                               ;; Record (ordinal name . specs) so the
                               ;; ordinal can be re-resolved at load time.
                               (when entry
                                 (pushnew entry opcode-alist
                                          :key #'car :test #'eql))
                               simplified)))))))
            (let* ((template (make-vinsn-template
                              :name vinsn-name
                              :result-vreg-specs results
                              :argument-vreg-specs args
                              :temp-vreg-specs temps
                              :nhybrids nhybrids
                              :results&args (append results
                                                    (nthcdr nhybrids args))
                              :nvp (- (+ (length results) (length args)
                                         (length temps))
                                      nhybrids)
                              :body (prog1
                                        (mapcar #'simplify-form body)
                                      (dolist (ref referenced-labels)
                                        (unless (memq ref local-labels)
                                          (error
                                           "local label ~S was referenced but ~
                                            never defined in VINSN-TEMPLATE ~
                                            definition for ~s" ref
                                            vinsn-name))))
                              :local-labels local-labels
                              :attributes attrs
                              :opcode-alist opcode-alist)))
              `(progn
                 (set-vinsn-template ',vinsn-name ,template ,template-hash)
                 (record-source-file ',vinsn-name ',source-indicator)
                 ',vinsn-name))))))))

#+(or linuxarm64-target (not arm64-target))
(defvar *linuxarm64-backend*
  (make-backend :lookup-opcode #'false
                :lookup-macro #'false
                :lap-opcodes #()
                :define-vinsn '%define-arm64-vinsn
                :platform-syscall-mask (logior platform-os-linux platform-cpu-arm64)
                :p2-dispatch *arm642-specials*
                :p2-vinsn-templates *arm64-vinsn-templates*
                :p2-template-hash-name '*arm64-vinsn-templates*
                :p2-compile 'arm642-compile
                :target-specific-features
                '(:arm64 :arm64-target :linux-target :linuxarm64-target
                  :64-bit-target :little-endian-target)
                :target-fasl-pathname (make-pathname :type "la64fsl")
                :target-platform (logior platform-word-size-64
                                         platform-cpu-arm64
                                         platform-os-linux)
                :target-os :linuxarm64
                :name :linuxarm64
                :target-arch-name :arm64
                :target-foreign-type-data nil
                :target-arch arm64::*arm64-target-arch*))

;;; Darwin cannot MAP_FIXED the linux/x8664 static page (#x12000); static
;;; space lives at #x200000000 (platform-darwinarm64.h).  nil = static+4K+tag.
;;; Must NOT share *arm64-target-arch* with linux — native xload otherwise
;;; embeds #x1300b and cold-load faults in %FIND-PKG (read @ #x13010).
(defconstant +darwinarm64-nil-value+ #x20000100b)

(defvar *darwinarm64-target-arch* nil)

(defun ensure-darwinarm64-target-arch ()
  "Fresh arch copy with Darwin nil-value; install on *darwinarm64-backend*."
  (let ((a (copy-structure arm64::*arm64-target-arch*)))
    (setf (arch::target-nil-value a) +darwinarm64-nil-value+)
    (setq *darwinarm64-target-arch* a)
    (when (and (boundp '*darwinarm64-backend*) *darwinarm64-backend*)
      (setf (backend-target-arch *darwinarm64-backend*) a))
    a))

#+(or darwinarm64-target (not arm64-target))
(defvar *darwinarm64-backend*
  (make-backend :lookup-opcode #'false
                :lookup-macro #'false
                :lap-opcodes #()
                :define-vinsn '%define-arm64-vinsn
                :platform-syscall-mask (logior platform-os-darwin platform-cpu-arm64)
                :p2-dispatch *arm642-specials*
                :p2-vinsn-templates *arm64-vinsn-templates*
                :p2-template-hash-name '*arm64-vinsn-templates*
                :p2-compile 'arm642-compile
                :target-specific-features
                '(:arm64 :arm64-target :darwin-target :darwinarm64-target
                  :64-bit-target :little-endian-target)
                :target-fasl-pathname (make-pathname :type "da64fsl")
                :target-platform (logior platform-word-size-64
                                         platform-cpu-arm64
                                         platform-os-darwin)
                :target-os :darwinarm64
                :name :darwinarm64
                :target-arch-name :arm64
                :target-foreign-type-data nil
                :target-arch (or *darwinarm64-target-arch*
                                 (ensure-darwinarm64-target-arch))))

#+(or linuxarm64-target (not arm64-target))
(pushnew *linuxarm64-backend* *known-arm64-backends*)

#+(or darwinarm64-target (not arm64-target))
(pushnew *darwinarm64-backend* *known-arm64-backends*)

(defvar *arm64-backend* (car *known-arm64-backends*))

(defun fixup-arm64-backend ()
  (dolist (b *known-arm64-backends*)
    (setf (backend-lap-opcodes b) #()
          (backend-p2-dispatch b) *arm642-specials*
          (backend-p2-vinsn-templates b)  *arm64-vinsn-templates*)
    (or (backend-lap-macros b) (setf (backend-lap-macros b)
                                     (make-hash-table :test #'equalp))))
  ;; Keep Darwin nil-value correct even after arm64-arch reload resets
  ;; the shared linux-shaped *arm64-target-arch*.
  #+(or darwinarm64-target (not arm64-target))
  (ensure-darwinarm64-target-arch))

(fixup-arm64-backend)

;;; A vinsn template body bakes in, for each instruction, the ordinal of
;;; the assembler template it was matched against at vinsn-definition
;;; time.  If the assembler's template vector is reordered after the
;;; vinsns were compiled, those ordinals go stale.  Re-resolve them: for
;;; each recorded (ordinal name . operand-specs) entry, find the template
;;; of that name whose operand-specs match and read its current ordinal,
;;; rewriting the body where the ordinal changed.  Mirrors the x86 port's
;;; FIXUP-OPCODE-ORDINALS; the ARM64 assembler is name-indexed and
;;; templates carry their operand-specs, so we key on name + specs.
(defun fixup-arm64-vinsn-ordinals (vinsn-template)
  (let ((changed '()))
    (dolist (entry (vinsn-template-opcode-alist vinsn-template))
      (destructuring-bind (old-ordinal name . specs) entry
        (let ((candidates (gethash name arm64::*instruction-template-lists*)))
          (unless candidates
            (error "Unknown ARM64 instruction ~a in vinsn fixup; ~
                    it was a known instruction when the vinsn was defined."
                   name))
          (let ((new-ordinal
                 (dolist (template candidates
                                   (error "No ARM64 template matches ~a ~s ~
                                           in vinsn fixup." name specs))
                   (when (equal (arm64::instruction-template-operand-specs
                                 template)
                                specs)
                     (return (arm64::instruction-template-ordinal template))))))
            (unless (eql old-ordinal new-ordinal)
              (setf (car entry) new-ordinal)
              (push (cons old-ordinal new-ordinal) changed))))))
    (when changed
      (labels ((update-instruction (form)
                 (let ((pair (and (typep (car form) 'fixnum)
                                  (assoc (car form) changed :test #'eql))))
                   (when pair (setf (car form) (cdr pair)))))
               (fixup-form (form)
                 (unless (atom form)
                   (if (atom (car form))
                     (update-instruction form)
                     (dolist (f (cdr form)) (fixup-form f))))))
        (dolist (form (vinsn-template-body vinsn-template))
          (fixup-form form))))))

;;; Re-resolve template ordinals in every defined vinsn.  Idempotent.
;;; TEMPLATE-HASH maps vinsn names to (name . vinsn-template) cells.
(defun fixup-arm64-vinsn-templates (&optional (template-hash
                                               *arm64-vinsn-templates*))
  (maphash #'(lambda (name cell)
               (declare (ignore name))
               (when (cdr cell)         ;defined (not merely referenced)
                 (fixup-arm64-vinsn-ordinals (cdr cell))))
           template-hash))

#+arm64-target
(setq *host-backend* *arm64-backend* *target-backend* *arm64-backend*)

(defun setup-arm64-ftd (backend)
  (or (backend-target-foreign-type-data backend)
      (let* ((name (backend-name backend))
             (ftd
               (case name
                 (:darwinarm64
                  (make-ftd
                   :interface-db-directory "ccl:darwin-arm64-headers;"
		   :interface-package-name "ARM64-DARWIN"
                   :attributes '(:bits-per-word 64
                                 :signed-char t
                                 :struct-by-value t
                                 :natural-alignment t
                                 :prepend-underscore nil)
                   :ff-call-expand-function
                   (intern "EXPAND-FF-CALL" "ARM64-DARWIN")
		   :ff-call-struct-return-by-implicit-arg-function
                   (intern "RECORD-TYPE-RETURNS-STRUCTURE-AS-FIRST-ARG"
                           "ARM64-DARWIN")
                   :callback-bindings-function
                   (intern "GENERATE-CALLBACK-BINDINGS" "ARM64-DARWIN")
                   :callback-return-value-function
                   (intern "GENERATE-CALLBACK-RETURN-VALUE" "ARM64-DARWIN")))
                 (:linuxarm64
                  (make-ftd
                   :interface-db-directory "ccl:arm64-headers;"
                   :interface-package-name "ARM64-LINUX"
                   :attributes '(:bits-per-word 64
                                 ;; `char' is UNSIGNED by the
                                 ;; aarch64-linux-gnu psABI; AAPCS64 leaves
                                 ;; the signedness to the platform and Darwin
                                 ;; chose the other way.
                                 :signed-char nil
                                 :struct-by-value t
                                 :natural-alignment t
                                 :prepend-underscore nil)
                   :ff-call-expand-function
                   (intern "EXPAND-FF-CALL" "ARM64-LINUX")
                   :ff-call-struct-return-by-implicit-arg-function
                   (intern "RECORD-TYPE-RETURNS-STRUCTURE-AS-FIRST-ARG"
                           "ARM64-LINUX")
                   :callback-bindings-function
                   (intern "GENERATE-CALLBACK-BINDINGS" "ARM64-LINUX")
                   :callback-return-value-function
                   (intern "GENERATE-CALLBACK-RETURN-VALUE" "ARM64-LINUX")))
                 )))
        (install-standard-foreign-types ftd)
        (use-interface-dir :libc ftd)
        (setf (backend-target-foreign-type-data backend) ftd))))

;;; ARM32 shape (compiler/ARM/arm-backend.lisp:361-366): the resident
;;; backend goes on *known-backends* UNCONDITIONALLY -- otherwise
;;; find-backend of the running target's own name returns NIL on a native
;;; lisp, and every (target-*-modules) call fails -- and the per-OS
;;; backends are added only on a cross host, where all of them exist.
(pushnew *arm64-backend* *known-backends* :key #'backend-name)
#-arm64-target
(progn
  (pushnew *darwinarm64-backend* *known-backends* :key #'backend-name)
  (pushnew *linuxarm64-backend* *known-backends* :key #'backend-name))


;;; FFI stuff

;;; If the type, T, of the result of a function is such that
;;;
;;;   void func(T arg)
;;;
;;; would require that arg be passed as a value in a register (or set
;;; of registers) according to the rules in Parameter passing, then
;;; the result is returned in the same registers as would be used for
;;; such an argument.
;;;
;;; Otherwise, the caller shall reserve a block of memory of
;;; sufficient size and alignment to hold the result. The address of
;;; the memory block shall be passed as an additional argument to the
;;; function in x8. The callee may modify the result memory block at
;;; any point during the execution of the subroutine (there is no
;;; requirement for the callee to preserve the value stored in x8).
;;;
;;;                                - Procedure Call Standard, § 6.9

;;; AAPCS64 composite return / argument classification (IHI 0055 section 6.8-6.9):
;;;   HFA  = 1..4 leaves of the same float/double (nested records flatten)
;;;   GPR  = non-HFA composite <= 16 bytes -> x0/x1 (args: consecutive GPRs)
;;;   MEM  = otherwise -> caller buffer via x8 (args: by reference)
;;;
;;; Apple ObjC on arm64 never uses objc_msgSend*_stret; register and
;;; memory returns both go through objc_msgSend with the standard ABI.
;;; The legacy FTD predicate name still means "memory / x8", not "first GP arg".

(defun arm64::hfa-leaf-reps (ftype &optional (base-bits 0))
  "Flatten FTYPE into ((:single-float|:double-float|:other) . byte-offset) leaves."
  (ensure-foreign-type-bits ftype)
  (collect ((leaves))
    (labels ((walk (ty base)
               (cond ((typep ty 'foreign-record-type)
                      (ensure-foreign-type-bits ty)
                      ;; Union members alias the same storage; walking them
                      ;; all would double-count leaves.  Classify unions as
                      ;; non-HFA (:other -> GPR/memory by size).
                      (if (eq (foreign-record-type-kind ty) :struct)
                        (dolist (f (foreign-record-type-fields ty))
                          (walk (foreign-record-field-type f)
                                (+ base (foreign-record-field-offset f))))
                        (leaves (cons :other (ash base -3)))))
                     ((typep ty 'foreign-array-type)
                      (let* ((el (foreign-array-type-element-type ty))
                             (dims (foreign-array-type-dimensions ty))
                             (n (if (and (consp dims) (integerp (car dims)))
                                  (car dims)
                                  0))
                             (eb (ensure-foreign-type-bits el)))
                        (dotimes (i n)
                          (walk el (+ base (* i eb))))))
                     ((typep ty 'foreign-single-float-type)
                      (leaves (cons :single-float (ash base -3))))
                     ((typep ty 'foreign-double-float-type)
                      (leaves (cons :double-float (ash base -3))))
                     (t
                      (leaves (cons :other (ash base -3)))))))
      (walk ftype base-bits)
      (leaves))))

(defun arm64::record-hfa-info (rtype)
  "Return (values :single-float|:double-float count) if RTYPE is an HFA, else NIL."
  (let* ((ftype (if (typep rtype 'foreign-type)
                  rtype
                  (parse-foreign-type rtype)))
         (leaves (and (typep ftype 'foreign-record-type)
                      (arm64::hfa-leaf-reps ftype)))
         (n (length leaves))
         (rep (car (car leaves))))
    (when (and leaves
               (<= 1 n 4)
               (not (eq rep :other))
               (every (lambda (leaf) (eq (car leaf) rep)) leaves))
      (values rep n))))

(defun arm64::classify-record-return (rtype)
  (let* ((ftype (if (typep rtype 'foreign-type)
                  rtype
                  (parse-foreign-type rtype))))
    (ensure-foreign-type-bits ftype)
    (cond ((arm64::record-hfa-info ftype) :hfa)
          ((<= (foreign-type-bits ftype) 128) :gpr)
          (t :memory))))

;;; T => composite returned via the indirect result location (x8).
;;; Despite the historical name this is NOT a hidden first GP argument.
(defun arm64::record-type-returns-structure-as-first-arg (rtype)
  (when (and rtype
             (not (typep rtype 'unsigned-byte))
             (not (member rtype *foreign-representation-type-keywords*
                          :test #'eq)))
    ;; Parse errors propagate: silently classifying an unparseable type
    ;; as "not memory" would miscompile the call.
    (let* ((ftype (if (typep rtype 'foreign-type)
                    rtype
                    (parse-foreign-type rtype))))
      (and (typep ftype 'foreign-record-type)
           (eq (arm64::classify-record-return ftype) :memory)))))

(defun arm64::struct-from-regbuf-values (r rtype regbuf)
  "Copy AAPCS64 register-returned composite from REGBUF into R.
REGBUF layout matches ffcall_return_registers: x0-x7 @0..56, d0-d7 @64..120."
  (let* ((ftype (if (typep rtype 'foreign-type)
                  rtype
                  (parse-foreign-type rtype)))
         (class (arm64::classify-record-return ftype)))
    (collect ((forms))
      (ecase class
        (:hfa
         (multiple-value-bind (rep count)
             (arm64::record-hfa-info ftype)
           (let* ((leaves (arm64::hfa-leaf-reps ftype))
                  (fpr0 64))
             (dotimes (i count)
               (let* ((byte-off (cdr (nth i leaves)))
                      (src (+ fpr0 (* i 8))))
                 (if (eq rep :double-float)
                   (forms `(setf (%get-double-float ,r ,byte-off)
                                 (%get-double-float ,regbuf ,src)))
                   (forms `(setf (%get-single-float ,r ,byte-off)
                                 (%get-single-float ,regbuf ,src)))))))))
        (:gpr
         (let* ((bits (ensure-foreign-type-bits ftype))
                (nbytes (ash (+ bits 7) -3)))
           ;; 32-bit chunks avoid consing bignums on the interpreted path.
           (do* ((b 0 (+ b 4)))
                ((>= b nbytes))
             (forms `(setf (%get-unsigned-long ,r ,b)
                           (%get-unsigned-long ,regbuf ,b)))))))
      `(progn ,@(forms) nil))))

(defun arm64::expand-ff-call (callform args
                              &key
                                (arg-coerce #'null-coerce-foreign-arg)
                                (result-coerce #'null-coerce-foreign-result))
  "Shared AAPCS64 ff-call expander (Linux + Darwin).
Darwin variadic-on-stack is enforced in aapcs64-ff-call when a
:variadic sentinel (from %external-call-expander at the CDB
:void boundary) appears in the arg list.

Composite returns:
  :hfa / :gpr -> :registers regbuf + unpack (never a fake x0 result pointer)
  :memory     -> :structure-return buffer (callee writes via x8)

Composite args (each one ATOMIC — AAPCS64 never splits a composite
between registers and stack):
  HFA         -> (rep . count) spec + the composite's address
  <=64 bits    -> one :unsigned-doubleword
  <=128 bits   -> numeric word-count spec + the composite's address
  larger      -> :address (by reference)"
  (let* ((result-type-spec (or (car (last args)) :void))
         (regbuf nil)
         (result-temp nil)
         (result-form nil)
         (struct-result-type nil))
    (multiple-value-bind (result-type error)
        (ignore-errors (parse-foreign-type result-type-spec))
      (if error
        (setq result-type-spec :void result-type *void-foreign-type*)
        (setq args (butlast args)))
      (collect ((argforms))
        (when (eq (car args) :monitor-exception-ports)
          (argforms (pop args)))
        (when (typep result-type 'foreign-record-type)
          (setq result-form (pop args)
                struct-result-type result-type
                result-type *void-foreign-type*
                result-type-spec :void)
          (ecase (arm64::classify-record-return struct-result-type)
            ((:hfa :gpr)
             (setq regbuf (gensym)
                   result-temp (gensym))
             (argforms :registers)
             (argforms regbuf))
            (:memory
             (argforms :structure-return)
             (argforms result-form))))
        (unless (evenp (length args))
          (error "~s should be an even-length list of alternating foreign types and values" args))
        (do* ((args args (cddr args)))
             ((null args))
          (let* ((arg-type-spec (car args))
                 (arg-value-form (cadr args)))
            (if (or (member arg-type-spec *foreign-representation-type-keywords*
                            :test #'eq)
                    (typep arg-type-spec 'unsigned-byte)
                    (eq arg-type-spec :registers)
                    (eq arg-type-spec :structure-return)
                    (eq arg-type-spec :variadic))
              (progn
                (argforms arg-type-spec)
                (argforms arg-value-form))
              (let* ((ftype (parse-foreign-type arg-type-spec)))
                (if (typep ftype 'foreign-record-type)
                  (multiple-value-bind (hfa-rep hfa-count)
                      (arm64::record-hfa-info ftype)
                    (cond (hfa-rep
                           ;; One atomic HFA argument: all fields in
                           ;; consecutive FPRs, or the whole aggregate in
                           ;; memory (AAPCS64 C.3) — decided at code-gen.
                           ;; QUOTED: a bare dotted pair would be walked as
                           ;; a call form by nx-transform-arglist.
                           (argforms (list 'quote (cons hfa-rep hfa-count)))
                           (argforms arg-value-form))
                          (t
                           (let* ((bits (ensure-foreign-type-bits ftype)))
                             (cond ((<= bits 64)
                                    (argforms :unsigned-doubleword)
                                    (argforms `(%%get-unsigned-longlong
                                                ,arg-value-form 0)))
                                   ((<= bits 128)
                                    ;; One atomic 2-word composite: both
                                    ;; words in GPRs or both on the stack
                                    ;; (AAPCS64 C.12) — decided at code-gen.
                                    (argforms (ceiling bits 64))
                                    (argforms arg-value-form))
                                   (t
                                    (argforms :address)
                                    (argforms arg-value-form)))))))
                  (progn
                    (argforms (foreign-type-to-representation-type ftype))
                    (argforms (funcall arg-coerce arg-type-spec arg-value-form))))))))
        (argforms (foreign-type-to-representation-type result-type))
        (let ((call (funcall result-coerce result-type-spec
                             `(,@callform ,@(argforms)))))
          (if regbuf
            `(let* ((,result-temp (%null-ptr)))
               (declare (dynamic-extent ,result-temp)
                        (type macptr ,result-temp))
               (%setf-macptr ,result-temp ,result-form)
               ;; 8 GPRs + 8 FPRs; matches ffcall_return_registers.
               (%stack-block ((,regbuf 128))
                 ,call
                 ,(arm64::struct-from-regbuf-values
                   result-temp struct-result-type regbuf)))
            call))))))

;;; A resident (native) arm64 compiler is DEMAND-LOADED module by module,
;;; not dumped into the image the way the ppc/x86 ones are, so nothing pulls
;;; NXENV before nx1 needs it and the first (defun ...) dies on an undefined
;;; CCL::NX-INIT-VAR.  ppc64-backend.lisp:21 and x8664-backend.lisp:21 have
;;; the same require, but inside (eval-when (:compile-toplevel :execute)) --
;;; compile-time only, which suffices for them and not for us.  Same reason
;;; the vinsns are required here rather than assumed present; compare
;;; ppc64-backend.lisp:305 (require "PPC64-VINSNS").
#+arm64-target
(require "NXENV")

#+arm64-target
(require "ARM64-VINSNS")

(provide "ARM64-BACKEND")
