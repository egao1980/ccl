;;;-*-Mode: LISP; Package: CCL -*-
;;;
;;; Copyright 1994-2009 Clozure Associates
;;;
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;     http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

(in-package "CCL")

(require 'systems)

(defparameter *sysdef-modules*
  '(systems compile-ccl))

(defparameter *level-1-modules*
  '(level-1
    l1-cl-package
    l1-boot-1 l1-boot-2 l1-boot-3
    l1-utils l1-init l1-symhash l1-numbers l1-aprims 
    l1-sort l1-dcode l1-clos-boot l1-clos
    l1-unicode l1-streams l1-files l1-io 
    l1-format l1-readloop l1-reader
    l1-sysio l1-pathnames l1-events
    l1-boot-lds  l1-readloop-lds 
    l1-lisp-threads  l1-application l1-processes
    l1-typesys sysutils l1-error-system
    l1-error-signal version l1-callbacks
    l1-sockets linux-files
    ))

(defparameter *compiler-modules*
  '(nx optimizers dll-node arch vreg vinsn 
    reg subprims  backend nx2 acode-rewrite))


(defparameter *ppc-compiler-modules*
  '(ppc32-arch
    ppc64-arch
    ppc-arch
    ppcenv
    ppc-asm
    risc-lap
    ppc-lap
    ppc-backend
))

(defparameter *x86-compiler-modules*
  '(x8632-arch
    x8664-arch
    x86-arch
    x8632env
    x8664env
    x86-asm
    x86-lap
    x86-backend
))

(defparameter *arm-compiler-modules*
  '(arm-arch
    armenv
    arm-asm
    arm-lap
    ))

(defparameter *arm64-compiler-modules*
  '(arm64-arch
    arm64env
    arm64-asm
    arm64-lap))

(defparameter *ppc32-compiler-backend-modules*
  '(ppc32-backend ppc32-vinsns))

(defparameter *ppc64-compiler-backend-modules*
  '(ppc64-backend ppc64-vinsns))


(defparameter *ppc-compiler-backend-modules*
  '(ppc2))


(defparameter *x8632-compiler-backend-modules*
  '(x8632-backend x8632-vinsns))

(defparameter *x8664-compiler-backend-modules*
  '(x8664-backend x8664-vinsns))

(defparameter *x86-compiler-backend-modules*
  '(x862))

(defparameter *arm-compiler-backend-modules*
  '(arm-backend arm-vinsns arm2))

(defparameter *arm64-compiler-backend-modules*
  '(arm64-backend arm64-vinsns arm642))

(defparameter *ppc-xload-modules* '(xppcfasload xfasload heap-image ))
(defparameter *x8632-xload-modules* '(xx8632fasload xfasload heap-image ))
(defparameter *x8664-xload-modules* '(xx8664fasload xfasload heap-image ))
(defparameter *arm-xload-modules* '(xarmfasload xfasload heap-image ))
(defparameter *arm64-xload-modules* '(xarm64fasload xfasload heap-image))

;;; Not too OS-specific.
(defparameter *ppc-xdev-modules* '(ppc-lapmacros ))
(defparameter *x86-xdev-modules* '(x86-lapmacros ))
(defparameter *arm-xdev-modules* '(arm-lapmacros ))
(defparameter *arm64-xdev-modules* '(arm64-lapmacros))

(defmacro with-global-optimization-settings ((&key speed
                                                   space
                                                   safety
                                                   debug
                                                   compilation-speed)
                                             &body body
                                             &environment env)
  (flet ((check-quantity (val default)
           (if val
             (require-type val '(mod 4))
             default)))
    (multiple-value-bind (body decls) (parse-body body env)
      `(let* ((*nx-speed* ,(check-quantity speed '*nx-speed*))
              (*nx-space* ,(check-quantity space '*nx-space*))
              (*nx-safety* ,(check-quantity safety '*nx-safety*))
              (*nx-debug* ,(check-quantity debug '*nx-debug*))
              (*nx-cspeed* ,(check-quantity compilation-speed '*nx-cspeed*)))
        ,@decls
        ,@body))))
  
(defun target-xdev-modules (&optional (target
				       (backend-target-arch-name
					*host-backend*)))
  (case target
    ((:ppc32 :ppc64) *ppc-xdev-modules*)
    ((:x8632 :x8664) *x86-xdev-modules*)
    (:arm *arm-xdev-modules*)
    (:arm64 *arm64-xdev-modules*)))

(defun target-xload-modules (&optional (target
					(backend-target-arch-name
                                         *host-backend*)))
  (case target
    ((:ppc32 :ppc64) *ppc-xload-modules*)
    (:x8632 *x8632-xload-modules*)
    (:x8664 *x8664-xload-modules*)
    (:arm *arm-xload-modules*)
    (:arm64 *arm64-xload-modules*)))






(defparameter *env-modules*
  '(lispequ hash backquote   level-2 macros
    defstruct-macros lists chars setf setf-runtime
    defstruct defstruct-lds 
    foreign-types
    db-io
    nfcomp
    hashenv))

(defun target-env-modules (&optional (target
				      (backend-name *host-backend*)))
  (append *env-modules*
          (let* ((ffi (ecase target
                        (:linuxppc32 'ffi-linuxppc32)
                        (:darwinppc32 'ffi-darwinppc32)
                        (:darwinppc64 'ffi-darwinppc64)
                        (:linuxppc64 'ffi-linuxppc64)
                        (:darwinx8632 'ffi-darwinx8632)
                        (:linuxx8664 'ffi-linuxx8664)
                        (:darwinx8664 'ffi-darwinx8664)
                        (:freebsdx8664 'ffi-freebsdx8664)
                        (:solarisx8664 'ffi-solarisx8664)
                        (:win64 'ffi-win64)
                        (:linuxx8632 'ffi-linuxx8632)
                        (:win32 'ffi-win32)
                        (:solarisx8632 'ffi-solarisx8632)
                        (:freebsdx8632 'ffi-freebsdx8632)
                        (:linuxarm 'ffi-linuxarm)
                        (:androidarm 'ffi-androidarm)
                        (:darwinarm 'ffi-darwinarm)
                        (:darwinarm64 'ffi-darwinarm64)
                        (:linuxarm64 'ffi-linuxarm64))))
            ;; Darwin arm64 reuses AAPCS64 callback generators from the
            ;; Linux module; cold-load must have that fasl (not .lisp).
            (if (eq target :darwinarm64)
              (list 'ffi-linuxarm64 ffi)
              (list ffi)))))


(defun target-compiler-modules (&optional (target
					   (backend-target-arch-name
					    *host-backend*)))
  (case target
    (:ppc32 (append *ppc-compiler-modules*
                    *ppc32-compiler-backend-modules*
                    *ppc-compiler-backend-modules*))
    (:ppc64 (append *ppc-compiler-modules*
                    *ppc64-compiler-backend-modules*
                    *ppc-compiler-backend-modules*))
    (:x8632 (append *x86-compiler-modules*
                    *x8632-compiler-backend-modules*
                    *x86-compiler-backend-modules*))
    (:x8664 (append *x86-compiler-modules*
                    *x8664-compiler-backend-modules*
                    *x86-compiler-backend-modules*))
    (:arm (append *arm-compiler-modules*
                  *arm-compiler-backend-modules*))
    (:arm64 (append *arm64-compiler-modules*
                    *arm64-compiler-backend-modules*))))

(defparameter *other-lib-modules*
  '(streams pathnames backtrace
    apropos
    numbers 
    dumplisp
    source-files
    swink))

(defun target-other-lib-modules (&optional (target
					    (backend-target-arch-name
					     *host-backend*)))
  (append *other-lib-modules*
	  (case target
	    ((:ppc32 :ppc64) '(ppc-backtrace ppc-disassemble))
            ((:x8632 :x8664) '(x86-backtrace x86-disassemble x86-watch))
            (:arm '(arm-backtrace arm-disassemble))
            (:arm64 '(arm64-backtrace arm64-disassemble)))))
	  

(defun target-lib-modules (&optional (backend-name
                                      (backend-name *host-backend*)))
  (let* ((backend (or (find-backend backend-name) *host-backend*))
         (arch-name (backend-target-arch-name backend)))
    (append (target-env-modules backend-name) (target-other-lib-modules arch-name))))


(defparameter *code-modules*
  '(encapsulate
    read misc  arrays-fry
    sequences sort 
    method-combination
    case-error pprint 
    format time 
;        eval step
    backtrace-lds  ccl-export-syms prepare-mcl-environment))



(defparameter *aux-modules*
  '(number-macros number-case-macro
    loop
    runtime
    mcl-compat
    arglist
    edit-callers
    describe
    cover
    leaks
    core-files
    dominance
    swank-loader
    remote-lisp
    asdf
    sockets
    defsystem
    jp-encode
    cn-encode
    prefixed-stream
    timestamped-stream
    ))







(defun target-level-1-modules (&optional (target (backend-name *host-backend*)))
  (append *level-1-modules*
	  (case target
	    ((:linuxppc32 :darwinppc32 :linuxppc64 :darwinppc64)
	     '(ppc-error-signal ppc-trap-support
	       ppc-threads-utils ppc-callback-support))            
            ((:linuxx8664 :freebsdx8664 :darwinx8664 :solarisx8664
                          :darwinx8632 :win64  :linuxx8632 :win32 :solarisx8632
                          :freebsdx8632)
             '(x86-error-signal x86-trap-support
               x86-threads-utils x86-callback-support))
            ((:linuxarm :darwinarm :androidarm)
             '(arm-error-signal arm-trap-support
               arm-threads-utils arm-callback-support))
            ((:darwinarm64 :linuxarm64)
             '(arm64-error-signal arm64-trap-support
               arm64-threads-utils arm64-callback-support)))))


;;; Needed to cross-dump an image


(unless (fboundp 'xload-level-0)
  (%fhave 'xload-level-0
          #'(lambda (&rest rest)
	      (in-development-mode
	       (require-modules (target-xload-modules)))
              (apply 'xload-level-0 rest))))

(defun find-module (module &optional (target (backend-name *host-backend*))  &aux data fasl sources)
  (if (setq data (assoc module *ccl-system*))
    (let* ((backend (or (find-backend target) *host-backend*)))
      (setq fasl (cadr data) sources (caddr data))      
      (setq fasl (merge-pathnames (backend-target-fasl-pathname
				   backend) fasl))
      (values fasl (if (listp sources) sources (list sources))))
    (error "Module ~S not defined" module)))

;compile if needed.
(defun target-compile-modules (modules target force-compile)
  (if (not (listp modules)) (setq modules (list modules)))
  (in-development-mode
   (dolist (module modules t)
     (multiple-value-bind (fasl sources) (find-module module target)
      (if (needs-compile-p fasl sources force-compile)
        (progn
          (require'nfcomp)
          (compile-file (car sources)
			:output-file fasl
			:verbose t
			:target target)))))))


(defun needs-compile-p (fasl sources force-compile)
  (if fasl
    (if (eq force-compile t)
      t
      (if (not (probe-file fasl))
        t
        (let ((fasldate (file-write-date fasl)))
          (if (if (integerp force-compile) (> force-compile fasldate))
            t
            (dolist (source sources nil)
              (if (> (file-write-date source) fasldate)
                (return t)))))))))



;;;compile if needed, load if recompiled.

(defun update-modules (modules &optional force-compile)
  (if (not (listp modules)) (setq modules (list modules)))
  (in-development-mode
   (dolist (module modules t)
     (multiple-value-bind (fasl sources) (find-module module)
       (if (needs-compile-p fasl sources force-compile)
	 (progn
	   (require'nfcomp)
	   (let* ((*warn-if-redefine* nil))
	     (compile-file (car sources) :output-file fasl :verbose t :load t))
	   (provide module)))))))

(defun compile-modules (modules &optional force-compile)
  (target-compile-modules modules (backend-name *host-backend*) force-compile)
)



(defun compile-ccl (&optional force-compile)
  (with-compilation-unit ()
    (update-modules *sysdef-modules* force-compile)
    (update-modules 'nxenv force-compile)
    (update-modules *compiler-modules* force-compile)
    (update-modules (target-compiler-modules) force-compile)
    (update-modules (target-xdev-modules) force-compile)
    (update-modules (target-xload-modules)  force-compile)
    (let* ((env-modules (target-env-modules))
           (other-lib (target-other-lib-modules)))
      (require-modules env-modules)
      (update-modules env-modules force-compile)
      (compile-modules (target-level-1-modules)  force-compile)
      (update-modules other-lib force-compile)
      (require-modules other-lib)
      (require-update-modules *code-modules* force-compile))
    (compile-modules *aux-modules* force-compile)))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun require-env (&optional force-load)
  (require-modules  (target-env-modules)
                   force-load))

(defun compile-level-1 (&optional force-compile)
  (require-env)
  (compile-modules (target-level-1-modules (backend-name *host-backend*))
                   force-compile))





(defun compile-lib (&optional force-compile)
  (compile-modules (target-lib-modules)
                   force-compile))

(defun compile-code (&optional force-compile)
  (compile-modules *code-modules* force-compile))


;Compile but don't load

(defun xcompile-ccl (&optional force)
  (with-compilation-unit ()
    (compile-modules *sysdef-modules* force)
    (compile-modules 'nxenv force)
    (compile-modules *compiler-modules* force)
    (compile-modules (target-compiler-modules) force)
    (compile-modules (target-xdev-modules) force)
    (compile-modules (target-xload-modules)  force)
    (compile-modules (target-env-modules) force)
    (compile-modules (target-level-1-modules) force)
    (compile-modules (target-other-lib-modules) force)
    (compile-modules *code-modules* force)
    (compile-modules *aux-modules* force)))

(defun require-update-modules (modules &optional force-compile)
  (if (not (listp modules)) (setq modules (list modules)))
  (in-development-mode
    (dolist (module modules)
    (require-modules module)
    (update-modules module force-compile))))


(defun target-xcompile-ccl (target &optional force)
  (let* ((*target-backend* *host-backend*))
    (require-update-modules *sysdef-modules* force)) ;in the host
  (let* ((backend (or (find-backend target) *target-backend*))
	 (arch (backend-target-arch-name backend)))
    (target-compile-modules 'nxenv target force)
    (target-compile-modules *compiler-modules* target force)
    (target-compile-modules (target-compiler-modules arch) target force)
    (target-compile-modules (target-level-1-modules target) target force)
    (target-compile-modules (target-lib-modules target) target force)
    (target-compile-modules *sysdef-modules* target force)
    (target-compile-modules *aux-modules* target force)
    (target-compile-modules *code-modules* target force)
    (target-compile-modules (target-xdev-modules arch) target force)))

(defun cross-compile-ccl (target &optional force)
  (with-cross-compilation-target (target)
    (let* ((*target-backend* (find-backend target)))
      (target-xcompile-ccl target force))))


(defun require-module (module force-load)
  (multiple-value-bind (fasl source) (find-module module)
      (setq source (car source))
      (if (if fasl (probe-file fasl))
        (if force-load
          (progn
            (load fasl)
            (provide module))
          (require module fasl))
        (if (probe-file source)
          (progn
            (if fasl (format t "~&Can't find ~S so requiring ~S instead"
                             fasl source))
            (if force-load
              (progn
                (load source)
                (provide module))
              (require module source)))
          (error "Can't find ~S or ~S" fasl source)))))

(defun require-modules (modules &optional force-load)
  (if (not (listp modules)) (setq modules (list modules)))
  (let ((*package* (find-package :ccl)))
    (dolist (m modules t)
      (require-module m force-load))))


(defun target-xcompile-level-1 (target &optional force)
  (target-compile-modules (target-level-1-modules target) target force))

(defun standard-boot-image-name (&optional (target (backend-name *host-backend*)))
  (ecase target
    (:darwinppc32 "ppc-boot.image")
    (:linuxppc32 "ppc-boot")
    (:darwinppc64 "ppc-boot64.image")
    (:linuxppc64 "ppc-boot64")
    (:darwinx8632 "x86-boot32.image")
    (:linuxx8664 "x86-boot64")
    (:freebsdx8664 "fx86-boot64")
    (:darwinx8664 "x86-boot64.image")
    (:solarisx8664 "sx86-boot64")
    (:win64 "wx86-boot64.image")
    (:linuxx8632 "x86-boot32")
    (:win32 "wx86-boot32.image")
    (:solarisx8632 "sx86-boot32")
    (:freebsdx8632 "fx86-boot32")
    (:linuxarm "arm-boot")
    (:androidarm "aarm-boot")
    (:darwinarm64 "arm64-boot.image")
    (:linuxarm64 "arm64-boot")))

(defun standard-kernel-name (&optional (target (backend-name *host-backend*)))
  (ecase target
    (:darwinppc32 "dppccl")
    (:linuxppc32 "ppccl")
    (:darwinppc64 "dppccl64")
    (:darwinx8632 "dx86cl")
    (:linuxppc64 "ppccl64")
    (:linuxx8664 "lx86cl64")
    (:freebsdx8664 "fx86cl64")
    (:darwinx8664 "dx86cl64")
    (:solarisx8664 "sx86cl64")
    (:win64 "wx86cl64.exe")
    (:linuxx8632 "lx86cl")
    (:win32 "wx86cl.exe")
    (:solarisx8632 "sx86cl")
    (:freebsdx8632 "fx86cl")
    (:linuxarm "armcl")
    (:darwinarm "darmcl")
    (:androidarm "aarmcl")
    (:darwinarm64 "darm64cl")
    (:linuxarm64 "arm64cl")))

(defun standard-image-name (&optional (target (backend-name *host-backend*)))
  (concatenate 'string (pathname-name (standard-kernel-name target)) ".image"))

(defun kernel-build-directory (&optional (target (backend-name *host-backend*)))
  (ecase target
    (:darwinppc32 "darwinppc")
    (:linuxppc32 "linuxppc")
    (:darwinppc64 "darwinppc64")
    (:linuxppc64 "linuxppc64")
    (:darwinx8632 "darwinx8632")
    (:linuxx8664 "linuxx8664")
    (:freebsdx8664 "freebsdx8664")
    (:darwinx8664 "darwinx8664")
    (:solarisx8664 "solarisx64")
    (:win64 "win64")
    (:linuxx8632 "linuxx8632")
    (:win32 "win32")
    (:solarisx8632 "solarisx86")
    (:freebsdx8632 "freebsdx8632")
    (:linuxarm "linuxarm")
    (:darwinarm "darwinarm")
    (:androidarm "androidarm")
    (:darwinarm64 "darwinarm64")
    (:linuxarm64 "linuxarm64")))

;;; If we distribute (e.g.) 32- and 64-bit versions for the same
;;; machine and OS in the same svn directory, return the name of the
;;; peer backend, or NIL. For example., the peer of :linuxppc64 is
;;; :linuxppc32.  Note that this may change over time.
;;; Return NIL if the concept doesn't apply.
(defun peer-platform (&optional (target (backend-name *host-backend*)))
  (let* ((pairs '((:darwinppc32 . :darwinppc64)
                  (:linuxppc32 . :linuxppc64)
                  (:darwinx8632 . :darwinx8664)
                  (:linuxx8632 . :linuxx8664)
                  (:win32 . :win64)
                  (:solarisx8632 . :solarisx8664)
                  (:freebsdx8632 . :freebsdx8664))))
    (or (cdr (assoc target pairs))
        (car (rassoc target pairs)))))

(defun make-program (&optional (target (backend-name *host-backend*)))
  ;; The Solaris "make" program is too clever to understand -C, so
  ;; use GNU make (installed as "gmake").
  (case target
    ((:solarisx8664 :solarisx8632) "gmake")
    (t "make")))


(defun describe-external-process-failure (proc reminder)
  "If it appears that the external-process PROC failed in some way,
try to return a string that describes that failure.  If it seems
to have succeeded or if we can't tell why it failed, return NIL.
This is mostly intended to describe process-creation/fork/exec failures,
not runtime errors reported by a successfully created process."
  (multiple-value-bind (status exit-code)
      (external-process-status proc)
    (let* ((procname (car (external-process-args proc)))
           (string
            (case status
              (:error
               (%strerror exit-code))
              #-windows-target
              (:exited
               (when(= exit-code #-android-target #$EX_OSERR #+android-target 71)
                 "generic OS error in fork/exec")))))
      (when string
        (format nil "Error executing ~a: ~a~&~a" procname string reminder)))))

(defparameter *known-optional-features* '(:count-gf-calls :monitor-futex-wait :unique-dcode :qres-ccl :eq-hash-monitor))
(defvar *build-time-optional-features* nil)
(defvar *ccl-save-source-locations* :no-text)

(defun report-build-environment (stream)
  (format stream "~&Rebuilding ~a using ~a"
          (lisp-implementation-type)
          (lisp-implementation-version))
  (format stream "~&Path to source code: ~s" (truename "ccl:")))

#+darwinarm64-target
(defun %ensure-darwinarm64-map-jit-host-loader ()
  "Install tip LAP into the live host, then enable MAP_JIT fasl loads.
compile-file keeps heap code-vectors (tip LAP honors *compiling-file*);
loaded fasls go to MAP_JIT so compile-ccl is not NX-taxed under DUAL_MAP=0."
  (let ((*load-verbose* t)
        (*compile-verbose* nil)
        (*save-source-locations* nil)
        (*warn-if-redefine-kernel* nil))
    (format t "~&;Installing Darwin/arm64 tip LAP + MAP_JIT faslop into host~%")
    (load "ccl:lib;arm64env.lisp")
    (let ((old-alloc (fdefinition '%allocate-code-vector))
          (old-install (and (fboundp '%darwinarm64-jit-install-code)
                            (fdefinition '%darwinarm64-jit-install-code)))
          (old-faslop (svref *fasl-dispatch-table* 2)))
      ;; Heap-only while compiling/loading tip arm64-lap.lisp (MAP_JIT
      ;; uvectors do not fasl-dump; a MAP_JIT-resident tip lap UDF'd).
      (setq *darwinarm64-map-jit-fasls* nil)
      (setf (fdefinition '%allocate-code-vector)
            (nfunction %allocate-code-vector
              (lambda (element-count)
                (allocate-typed-vector :code-vector element-count))))
      (setf (fdefinition '%darwinarm64-jit-install-code)
            (nfunction %darwinarm64-jit-install-code
              (lambda (code-vector src-ivector nbytes)
                (declare (fixnum nbytes))
                (with-macptrs ((d) (s))
                  (%vect-data-to-macptr code-vector d)
                  (%vect-data-to-macptr src-ivector s)
                  (ff-call (foreign-symbol-address "memcpy")
                           :address d :address s
                           :unsigned-fullword nbytes :address))
                (%make-code-executable code-vector)
                code-vector)))
      (setf (svref *fasl-dispatch-table* 2)
            (nfunction $fasl-code-vector
              (lambda (s)
                (let* ((element-count (%fasl-read-count s))
                       (size-in-bytes (* 4 element-count))
                       (vector (allocate-typed-vector :code-vector element-count)))
                  (declare (fixnum element-count size-in-bytes))
                  (%epushval s vector)
                  (%fasl-read-n-bytes s vector 0 size-in-bytes)
                  (%make-code-executable vector)
                  vector))))
      (dolist (f (list "ccl:bin;arm64-lap.da64fsl"
                       "ccl:bin;arm64-lap.dx64fsl"))
        (let ((p (probe-file f)))
          (when p (delete-file p))))
      (load "ccl:compiler;ARM64;arm64-lap.lisp")
      ;; Restore level-0 MAP_JIT helpers, then install MAP_JIT faslop.
      (setf (fdefinition '%allocate-code-vector) old-alloc)
      (when old-install
        (setf (fdefinition '%darwinarm64-jit-install-code) old-install))
      (setf (svref *fasl-dispatch-table* 2) old-faslop))
    (%enable-darwinarm64-map-jit-fasls)
    (format t "~&;MAP_JIT host faslop enabled (tip LAP on heap)~%")))

#+darwinarm64-target
(defun %darwinarm64-shell-quote (string)
  (with-output-to-string (out)
    (write-char #\' out)
    (loop for c across string
          do (if (char= c #\')
               (write-string "'\\''" out)
               (write-char c out)))
    (write-char #\' out)))

#+darwinarm64-target
(defun %darwinarm64-cross-xload-boot-image ()
  "Optional Rosetta fallback.  Prefer native xload-level-0 (Darwin nil-value
is fixed in arm64-backend); kept for hosts that lack a working native
xload toolchain."
  (let* ((dx86 (probe-file "ccl:ccl;dx86cl64"))
         (script (probe-file "ccl:tools;bootstrap-darwinarm64-boot.lisp")))
    (unless dx86
      (error "darwinarm64 cross-xload needs ./dx86cl64"))
    (unless script
      (error "missing ~s" "ccl:tools;bootstrap-darwinarm64-boot.lisp"))
    (format t "~&;Cross-xloading arm64-boot.image via Rosetta dx86cl64 ...")
    (force-output)
    (let* ((dir (native-translated-namestring (truename "ccl:")))
           (dx86n (native-translated-namestring dx86))
           (scriptn (native-translated-namestring script))
           (cmd (format nil
                        "export CCL_DEFAULT_DIRECTORY=~a; exec arch -x86_64 ~a --no-init --batch < ~a"
                        (%darwinarm64-shell-quote dir)
                        (%darwinarm64-shell-quote dx86n)
                        (%darwinarm64-shell-quote scriptn))))
      (with-output-to-string (s)
        (let* ((proc (run-program "/bin/sh" (list "-c" cmd)
                                  :output s :error :output)))
          (multiple-value-bind (status exit-code)
              (external-process-status proc)
            (unless (and (eq :exited status) (eql exit-code 0))
              (error "darwinarm64 cross-xload failed (~s ~s):~%~a"
                     status exit-code (get-output-stream-string s)))
            (unless (probe-file (standard-boot-image-name))
              (error "cross-xload did not write ~s"
                     (standard-boot-image-name)))
            (format t "~&;Wrote bootstrapping image: ~s"
                    (truename (standard-boot-image-name)))))))))

(defun %build-lisp-kernel (&key clean (extra-make-args nil) verbose)
  "Run make in lisp-kernel/<platform>.  EXTRA-MAKE-ARGS is a list of
additional make arguments (e.g. \"DUAL_MAP=1\")."
  (let* ((kdir (format nil "lisp-kernel/~a" (kernel-build-directory)))
         (j (format nil "~d" (1+ (cpu-count)))))
    (when clean
      (run-program "make" (list "-C" kdir "clean")))
    (format t "~&;Building lisp-kernel~@[ (~{~a~^ ~})~] ..." extra-make-args)
    (force-output)
    (with-output-to-string (s)
      (let* ((args (append (list "-C" kdir "-j" j) extra-make-args))
             (proc (run-program (make-program) args
                                :output s :error :output)))
        (multiple-value-bind (status exit-code)
            (external-process-status proc)
          (if (and (eq :exited status) (zerop exit-code))
            (progn
              (format t "~&;Kernel built successfully.")
              (when verbose
                (format t "~&;kernel build output:~%~a"
                        (get-output-stream-string s)))
              (sleep 1))
            (error "Error(s) during kernel compilation.~%~a"
                   (or
                    (describe-external-process-failure
                     proc
                     "Developer tools may not be installed correctly.")
                    (get-output-stream-string s)))))))))

(defun rebuild-ccl (&key update full clean kernel force (reload t) exit
                         reload-arguments verbose optional-features
                         (save-source-locations *ccl-save-source-locations*)
                         (allow-constant-redefinition nil allow-constant-redefinition-p))
  (let* ((*build-time-optional-features* (intersection *known-optional-features* optional-features))
         (*features* (append *build-time-optional-features* *features*))
	 (*save-source-locations* save-source-locations))
    (when *build-time-optional-features*
      (setq full t))
    (when full
      (setq clean t kernel t reload t))
    (when update
      (multiple-value-bind (changed conflicts new-binaries)
	  (update-ccl :verbose (not (eq update :quiet)))
	(declare (ignore changed conflicts))
	(when new-binaries
	  (format t "~&There are new bootstrapping binaries.  Please restart
the lisp and run REBUILD-CCL again.")
	  (return-from rebuild-ccl nil))))
    (when (or clean force)
      ;; for better bug reports...
      (report-build-environment t)
      (unless allow-constant-redefinition-p
        (when (or force clean update)
          (setq allow-constant-redefinition t))))
    (let* ((cd (current-directory))
           (*cerror-on-constant-redefinition* (not allow-constant-redefinition ))
	   (*warn-if-redefine-kernel* nil))
      (unwind-protect
           (progn
             (setf (current-directory) "ccl:")
             (when clean
               (dolist (f (directory
                           (merge-pathnames
                            (make-pathname :name :wild
                                           :type (pathname-type *.fasl-pathname*))
                            "ccl:**;")))
                 (delete-file f)))
             ;; Host still has level-0 faslops until xload; install MAP_JIT
             ;; loader before compile-ccl so the first rebuild is fast.
             #+darwinarm64-target
             (%ensure-darwinarm64-map-jit-host-loader)
             (with-global-optimization-settings ()
               (compile-ccl (not (null force)))
               ;; Native xload: Darwin nil-value is owned by
               ;; *darwinarm64-target-arch* (not the shared linux #x1300b).
               #+darwinarm64-target
               (progn
                 (ensure-darwinarm64-target-arch)
                 ;; Keep host/target pointers on the Darwin backend object.
                 (setq *arm64-backend* *darwinarm64-backend*
                       *host-backend* *darwinarm64-backend*
                       *target-backend* *darwinarm64-backend*)
                 (format t "~&;Native xload-level-0 (nil=#x~x) ...~%"
                         (arch::target-nil-value
                          (backend-target-arch *host-backend*)))
                 (force-output)
                 (if force (xload-level-0 :force) (xload-level-0)))
               #-darwinarm64-target
               (if force (xload-level-0 :force) (xload-level-0)))
             (when kernel
               ;; Darwin/arm64: cold-load of arm64-boot.image still has impure
               ;; heap code-vectors, so it needs DUAL_MAP=1.  After
               ;; save-application :purify t, rebuild production DUAL_MAP=0.
               ;; Object files are not CDEFINES-aware — always make clean when
               ;; flipping DUAL_MAP (and between the two builds below).
               #+darwinarm64-target
               (%build-lisp-kernel :clean t
                                   :extra-make-args '("DUAL_MAP=1")
                                   :verbose verbose)
               #-darwinarm64-target
               (%build-lisp-kernel :clean (or clean force) :verbose verbose))
             (when reload
               (let* ((old-write-date
                       (or (ignore-errors (file-write-date (standard-image-name)))
                           0))
                      #+darwinarm64-target
                      (save-script
                       (merge-pathnames "tools/save-darwinarm64-image.lisp"
                                        (current-directory))))
                 ;; Darwin/arm64: after a MAP_JIT-heavy compile-ccl, a single
                 ;; run-program/fork has occasionally returned with pid NIL
                 ;; and status still :running ("Bug: fork failed but status
                 ;; field not set?").  Retry; use the file driver so stdin
                 ;; is a real fd (matches tools/rebuild-darwinarm64-unbiased.sh).
                 #+darwinarm64-target
                 (progn
                   (gc)
                   (unless (probe-file save-script)
                     (error "missing ~s" save-script))
                   (let ((ok nil) (last-out "") (last-status nil) (last-code nil))
                     (dotimes (attempt 5)
                       (format t "~&;Cold-load/purify save attempt ~d ...~%"
                               (1+ attempt))
                       (force-output)
                       (handler-case
                           (with-open-file (cmd save-script :direction :input)
                             (with-output-to-string (output)
                               (let* ((proc (run-program
                                             (format nil "./~a"
                                                     (standard-kernel-name))
                                             (list* "--image-name"
                                                    (standard-boot-image-name)
                                                    "--no-init"
                                                    "--batch"
                                                    reload-arguments)
                                             :input cmd
                                             :output output
                                             :error output))
                                      (st (external-process-status proc))
                                      (code (external-process-%exit-code proc)))
                                 (setq last-status st last-code code
                                       last-out (get-output-stream-string output))
                                 (when (and (eq st :exited) (eql code 0))
                                   (setq ok t)))))
                         (error (e)
                           (setq last-out (format nil "~a" e)
                                 last-status :error
                                 last-code -1)))
                       (when ok (return))
                       (sleep 1))
                     (unless ok
                       (error "Errors (~s ~s) reloading boot image:~&~a"
                              last-status last-code last-out))
                     (let* ((write-date
                             (or (ignore-errors
                                   (file-write-date (standard-image-name)))
                                 0)))
                       (unless (and write-date (> write-date old-write-date))
                         (error "The heap image ~a does not appear to have been written correctly.  This may indicate a problem with the bootstapping image."
                                (standard-image-name)))
                       (format t "~&;Wrote heap image: ~s"
                               (truename (format nil "ccl:~a"
                                                 (standard-image-name))))
                       (when verbose
                         (format t "~&;Reload heap image output:~%~a"
                                 last-out)))))
                 #-darwinarm64-target
                 (with-input-from-string (cmd (format nil
                                                "(save-application ~s)"
                                                (standard-image-name)))
                   (with-output-to-string (output)
                     (multiple-value-bind (status exit-code)
                         (external-process-status
                          (run-program
                           (format nil "./~a" (standard-kernel-name))
                           (list* "--image-name" (standard-boot-image-name)
                                  "--no-init"
                                  "--batch"
                                  reload-arguments)
                           :input cmd
                           :output output
                           :error output))
                       (if (and (eq status :exited)
                                (eql exit-code 0))
                         (let* ((write-date (or (ignore-errors (file-write-date (standard-image-name))) 0)))
                           (unless (and write-date (> write-date old-write-date))
                             (error "The heap image ~a does not appear to have been written correctly.  This may indicate a problem with the bootstapping image." (standard-image-name)))
                           (format t "~&;Wrote heap image: ~s"
                                   (truename (format nil "ccl:~a"
                                                     (standard-image-name))))
                           (when verbose
                             (format t "~&;Reload heap image output:~%~a"
                                     (get-output-stream-string output))))
                         (error "Errors (~s ~s) reloading boot image:~&~a"
                                status exit-code
                                (get-output-stream-string output))))))))
             ;; Production kernel after purify (DUAL_MAP=0 default).
             #+darwinarm64-target
             (when (and kernel reload)
               (%build-lisp-kernel :clean t
                                   :extra-make-args '("DUAL_MAP=0")
                                   :verbose verbose))
             (when exit
               (quit)))
        (setf (current-directory) cd)))))
                                                  
               
(defun create-interfaces (dirname &key target populate-arg)
  (let* ((backend (if target (find-backend target) *target-backend*))
         (*default-pathname-defaults* nil)
         (ftd (backend-target-foreign-type-data backend))
         (d (use-interface-dir dirname ftd))
         (populate (merge-pathnames "C/populate.sh"
                                    (merge-pathnames
                                     (interface-dir-subdir d)
                                     (ftd-interface-db-directory ftd))))
         (cdir (make-pathname :directory (pathname-directory (translate-logical-pathname populate))))
         (args (list "-c"
                     (format nil "cd ~a && /bin/sh ~a ~@[~a~]"
                             (native-translated-namestring cdir)
                             (native-translated-namestring populate)
                             populate-arg))))
    (format t "~&;[Running interface translator via ~s to produce .ffi file(s) from headers]~&" populate)
    (force-output t)
    (multiple-value-bind (status exit-code)
        (external-process-status
         (run-program "/bin/sh" args :output t))
      (if (and (eq status :exited)
               (eql exit-code 0))
        (let* ((f 'parse-standard-ffi-files))
          (require "PARSE-FFI")
          (format t "~%~%;[Parsing .ffi files; may create new .cdb files for ~s]" dirname)
          (funcall f dirname target)
          (format t "~%~%;[Parsing .ffi files again to resolve forward-referenced constants]")
          (funcall f dirname target))))))

(defun update-ccl (&key (verbose t))
  (let* ((changed ())
	 (new-binaries ())
         (conflicts ()))
    (with-output-to-string (out)
      (with-preserved-working-directory ("ccl:")                     
        (when verbose (format t "~&;Running 'svn update'."))
        (multiple-value-bind (status exit-code)
            (external-process-status
             (run-program *svn-program* '("update" "--non-interactive") :output out :error t))
          (when verbose (format t "~&;'svn update' complete."))
          (if (not (and (eq status :exited)
                        (eql exit-code 0)))
            (error "Running \"svn update\" produced exit status ~s, code ~s." status exit-code)
            (let* ((sout (get-output-stream-string out))
                   (added ())
                   (deleted ())
                   (updated ())
                   (merged ())
                   (binaries (list (standard-kernel-name) (standard-image-name )))
                   (peer (peer-platform)))
              (when peer
                (push (standard-kernel-name peer) binaries)
                (push (standard-image-name peer) binaries))
              (flet ((svn-revert (string)
                       (multiple-value-bind (status exit-code)
                           (external-process-status (run-program *svn-program* `("revert" ,string)))
                         (when (and (eq status :exited) (eql exit-code 0))
                           (setq conflicts (delete string conflicts :test #'string=))
                           (push string updated)))))
                (with-input-from-string (in sout)
                  (do* ((line (read-line in nil nil) (read-line in nil nil)))
                       ((null line))
                    (when (and (> (length line) 2)
                               (eql #\space (schar line 1)))
                      (let* ((path (string-trim " " (subseq line 2))))
                        (case (schar line 0)
                          (#\A (push path added))
                          (#\D (push path deleted))
                          (#\U (push path updated))
                          (#\G (push path merged))
                          (#\C (push path conflicts)))))))
                ;; If the kernel and/or image conflict, use "svn revert"
                ;; to replace the working copies with the (just updated)
                ;; repository versions.
                (setq changed (if (or added deleted updated merged conflicts) t))
                (dolist (f binaries)
		  (cond ((member f conflicts :test #'string=)
			 (svn-revert f)
			 (setq new-binaries t))
			((or (member f updated :test #'string=)
			     (member f merged :test #'string=))
			 (setq new-binaries t))))

                ;; If there are any remaining conflicts, offer
                ;; to revert them.
                (when conflicts
                  (with-preserved-working-directory ()
                    (cerror "Discard local changes to these files (using 'svn revert')."
                            "'svn update' was unable to merge local changes to the following file~p with the updated versions:~{~&~s~}" (length conflicts) conflicts)
                    (dolist (c (copy-list conflicts))
                      (svn-revert c))))
                ;; Report other changes, if verbose.
                (when (and verbose
                           (or added deleted updated merged conflicts))
                  (format t "~&;Changes from svn update:")
                  (flet ((show-changes (herald files)
                           (when files
                             (format t "~&; ~a:~{~&;  ~a~}"
                                     herald files))))
                    (show-changes "Conflicting files" conflicts)
                    (show-changes "New files/directories" added)
                    (show-changes "Deleted files/directories" deleted)
                    (show-changes "Updated files" updated)
                    (show-changes "Files with local changes, successfully merged" merged)))))))))
    (values changed conflicts new-binaries)))

(defmacro with-preserved-working-directory ((&optional dir) &body body)
  (let ((wd (gensym)))
    `(let ((,wd (mac-default-directory)))
       (unwind-protect
	    (progn 
	      ,@(when dir `((cwd ,dir)))
	      ,@body)
	 (cwd ,wd)))))

(defparameter *ccl-tests-directory* (make-pathname :directory
                                                   (append (pathname-directory
                                                            (translate-logical-pathname #P"ccl:"))
                                                           '(:up "ccl-tests"))))

(defparameter *ansi-tests-directory* (merge-pathnames  "ansi-tests/" *ccl-tests-directory*))

(defun ensure-tests-loaded (&key force update ansi ccl (load t))
  (unless (and (find-package "REGRESSION-TEST") (not force))
    (if (probe-file *ansi-tests-directory*)
        (when update
          (cwd *ccl-tests-directory*)
          (run-program "git" '("pull") :output t))
        (let* ((giturl "git@github.com:Clozure/ccl-tests.git")
               (s (make-string-output-stream)))
	  (progn
	    (format t "~&Using ~a to check out test suite from ~a ~
        into ~A~%" "git" giturl *ccl-tests-directory*)
	    (cwd (make-pathname :directory (append (pathname-directory
                                                    (translate-logical-pathname *ccl-tests-directory*))
                                                   '(:up))))
	    (multiple-value-bind (status exit-code)
                                 (external-process-status
                                  (run-program "git" (list "clone" giturl)
                                               :output s :error s))
	      (unless (and (eq status :exited)
			   (eql exit-code 0))
		(error "Failed to check out test suite: ~%~a"
		       (get-output-stream-string s)))))))
    (cwd *ansi-tests-directory*)
    (run-program "make" '("-k" "clean") :output t)
    (map nil 'delete-file (directory "*.*fsl"))
    (when load
      ;; Muffle the typecase "clause ignored" warnings, since there is really nothing we can do about
      ;; it without making the test suite non-portable across platforms...
      (handler-bind ((warning (lambda (c)
                                (if (typep c 'shadowed-typecase-clause)
                                    (muffle-warning c)
                                    (when (let ((w (or (and (typep c 'compiler-warning)
                                                            (eq (compiler-warning-warning-type c) :program-error)
                                                            (car (compiler-warning-args c)))
                                                       c)))
                                            (or (and (typep c 'compiler-warning)
                                                     (typep (car (compiler-warning-args c))
                                                       'shadowed-typecase-clause))
                                                (and (typep w 'simple-warning)
                                                     (or 
                                                      (string-equal
                                                       (simple-condition-format-control w)
                                                       "Clause ~S ignored in ~S form - shadowed by ~S .")
                                                      ;; Might as well ignore these as well, they're intentional.
                                                      (string-equal
                                                       (simple-condition-format-control w)
                                                       "Duplicate keyform ~s in ~s statement.")))))
                                      (muffle-warning c))))))
        ;; This loads the infrastructure
        (load (merge-pathnames *ansi-tests-directory* "gclload1.lsp"))
        ;; This loads the actual tests
        (let ((redef-var (find-symbol "*WARN-IF-REDEFINE-TEST*" :REGRESSION-TEST)))
          (progv (list redef-var) (list (if force nil (symbol-value redef-var)))
            (when ansi
              (load (merge-pathnames *ansi-tests-directory* "gclload2.lsp")))
            ;; And our own tests
            (when ccl
              (load (merge-pathnames *ansi-tests-directory* "ccl.lsp")))))))))


(defun test-ccl (&key force (update t) verbose (catch-errors t) (ansi t) (ccl t)
                      optimization-settings exit exhaustive)
  (if exhaustive
    (let* ((total-failures ()))
      (ensure-tests-loaded :update update :force nil :load nil)
      (dotimes (speed 4)
        (dotimes (space 4)
          (dotimes (safety 4)
            (dotimes (debug 4)
              (dotimes (compilation-speed 4)
                (let* ((optimization-settings `((speed ,speed)
                                                (space ,space)
                                                (safety ,safety)
                                                (debug ,debug)
                                                (compilation-speed ,compilation-speed))))
                  (format t "~&;Testing ~a at optimization settings~&;~s~&"
                          (lisp-implementation-version) optimization-settings)
                  (let* ((failures (test-ccl :force t
                                             :update nil
                                             :verbose verbose
                                             :catch-errors catch-errors
                                             :ansi ansi
                                             :ccl ccl
                                             :optimization-settings optimization-settings
                                             :exit nil)))
                    (when failures
                      (push (cons optimization-settings failures) total-failures)))))))))
      (if exit
        (quit (if total-failures 1 0))
        total-failures))
    (with-preserved-working-directory ()
      (let* ((*package* (find-package "CL-USER"))
             (*load-preserves-optimization-settings* t))
        (with-global-optimization-settings ()
          (proclaim `(optimize ,@optimization-settings))
          (ensure-tests-loaded :force force :update update :ansi ansi :ccl ccl)
          (cwd *ansi-tests-directory*)
          (let ((do-tests (find-symbol "DO-TESTS" "REGRESSION-TEST"))
                (failed (find-symbol "*FAILED-TESTS*" "REGRESSION-TEST"))
                (*print-catch-errors* nil))
            (prog1
                (time (funcall do-tests :verbose verbose :compile t
                               :catch-errors catch-errors
                               :optimization-settings (or optimization-settings '((speed 1) (space 1) (safety 1) (debug 1) (compilation-speed 1)))))
              ;; Clean up a little
              (map nil #'delete-file
                   (directory (merge-pathnames *.fasl-pathname* (merge-pathnames *ansi-tests-directory*
                                                                                 "temp*")))))
            (let ((failed-tests (symbol-value failed)))
              (when exit
                (quit (if failed-tests 1 0)))
              failed-tests)))))))

