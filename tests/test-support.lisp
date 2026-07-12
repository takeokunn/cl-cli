(in-package :cl-cli/tests)

(defparameter *tests* nil)

(defmacro deftest (name &body body)
  `(progn
     (push (list ',name (lambda () ,@body)) *tests*)
     ',name))

(defmacro deftest-with-fixture (name (binding fixture-form) &body body)
  `(deftest ,name
     (let ((,binding ,fixture-form))
       ,@body
       t)))

(defmacro is (form &optional (message "Assertion failed"))
  `(unless ,form
     (error "~A: ~S" ,message ',form)))

(defmacro signals (condition-type &body body)
  `(handler-case (progn ,@body
                     (error "Expected condition of type ~A" ',condition-type))
     (,condition-type () t)))

(defmacro signals-all (condition-type &body forms)
  `(progn
     ,@(loop for form in forms
             collect `(signals ,condition-type ,form))))

(defmacro signals-invalid-specification (&body forms)
  `(signals-all cli-invalid-specification ,@forms))

(defmacro catching-signal ((condition-type condition) form &body body)
  (let ((seen (gensym "SEEN")))
    `(let ((,seen nil))
       (handler-case
           ,form
         (,condition-type (,condition)
           (setf ,seen t)
           ,@body))
       (is ,seen ,(format nil "Expected ~A." condition-type)))))

(defun run-test-case (name thunk)
  (format t "~&[RUN] ~A~%" name)
  (funcall thunk)
  (format t "[OK]  ~A~%" name))

(defun app-help-text (app)
  (with-string-output (stream)
    (print-app-help app stream)))

(defun command-help-text (app command)
  (with-string-output (stream)
    (print-command-help app command stream)))

(defun optional-value-option (name &key short consume-optional-value-p)
  (make-option :name name
               :short short
               :kind :optional-value
               :consume-optional-value-p consume-optional-value-p))

(defun value-option (name &key short multiple-p default parser env-var env-vars
                             choices hidden-p required-p)
  (make-option :name name
               :short short
               :kind :value
               :multiple-p multiple-p
               :default default
               :parser parser
               :env-var env-var
               :env-vars env-vars
               :choices choices
               :hidden-p hidden-p
               :required-p required-p))

(defun flag-option (name &key short hidden-p)
  (make-option :name name
               :short short
               :kind :flag
               :hidden-p hidden-p))

(defun stop-parsing-option (name &key short)
  (make-option :name name
               :short short
               :kind :value
               :stop-parsing-p t))

(defmacro with-app-help-text ((text app) &body body)
  `(let ((,text (app-help-text ,app)))
     ,@body))

(defmacro with-command-help-text ((text app command) &body body)
  `(let ((,text (command-help-text ,app ,command)))
     ,@body))

(defun search-not-found-p (needle text)
  (null (search needle text)))

(defmacro assert-searches* (text predicate &rest needles)
  `(progn
     ,@(loop for needle in needles
             collect `(is (funcall ,predicate ,needle ,text)))))

(defmacro assert-searches (text &rest needles)
  `(assert-searches* ,text #'search ,@needles))

(defmacro assert-not-searches (text &rest needles)
  `(assert-searches* ,text #'search-not-found-p ,@needles))

(defmacro assert-search-order (text &rest needles)
  `(progn
     ,@(loop for (left right) on needles
             while right
             collect `(is (< (search ,left ,text)
                             (search ,right ,text))))))

(defmacro plist-values= (invocation accessor expected-label &rest pairs)
  (let ((normalized-pairs
          (if (and pairs (every #'consp pairs))
              pairs
              (loop for (key expected) on pairs by #'cddr
                    collect (list key expected)))))
    `(progn
       ,@(loop for pair in normalized-pairs
               for (key expected) = pair
               for message = (format nil "Expected ~A ~S to match"
                                     expected-label key)
               collect `(is (equal (,accessor ,invocation ,key) ,expected)
                            ,message)))))

(defmacro invocation-values= (invocation &rest clauses)
  `(progn
     ,@(loop for clause in clauses
             collect (destructuring-bind (kind key expected) clause
                       (ecase kind
                         (:option
                          (let ((message (format nil "Expected option ~S to match"
                                                 key)))
                            `(is (equal (option-value ,invocation ,key) ,expected)
                                 ,message)))
                         (:positional
                          (let ((message (format nil "Expected positional ~S to match"
                                                 key)))
                            `(is (equal (positional-value ,invocation ,key) ,expected)
                                 ,message))))))))

(defmacro option-values= (invocation &rest pairs)
  `(plist-values= ,invocation option-value "option" ,@pairs))

(defmacro positional-values= (invocation &rest pairs)
  `(plist-values= ,invocation positional-value "positional" ,@pairs))

(defmacro caught-signal= ((condition-type condition) form &body clauses)
  `(catching-signal (,condition-type ,condition)
     ,form
     ,@(loop for clause in clauses
             collect (destructuring-bind (kind accessor &rest args) clause
                       (ecase kind
                         (:eq
                          (let ((expected (first args))
                                (message (second args)))
                            `(is (eq (,accessor ,condition) ,expected)
                                 ,(or message
                                      `(format nil "Expected ~A to match"
                                               ',accessor)))))
                         (:equal
                          (let ((expected (first args))
                                (message (second args)))
                            `(is (equal (,accessor ,condition) ,expected)
                                 ,(or message
                                      `(format nil "Expected ~A to match"
                                               ',accessor)))))
                         (:searches
                          `(assert-searches (,accessor ,condition)
                             ,@args))
                         (:not-searches
                          `(assert-not-searches (,accessor ,condition)
                             ,@args)))))))

(defmacro with-environment-variable-reader ((reader) &body body)
  `(let ((cl-cli::*environment-variable-reader* ,reader))
     ,@body))

(defmacro with-parsed-argv ((invocation app-form argv-form) &body body)
  (let ((app (gensym "APP")))
    `(let* ((,app ,app-form)
            (,invocation (parse-argv ,app ,argv-form)))
       ,@body)))

(defmacro with-parsed-argv-with-environment-variable-reader
    ((invocation app-form argv-form reader-form) &body body)
  (let ((app (gensym "APP"))
        (reader (gensym "READER")))
    `(let* ((,app ,app-form)
            (,reader ,reader-form))
       (with-environment-variable-reader (,reader)
         (let ((,invocation (parse-argv ,app ,argv-form)))
           ,@body)))))

(defmacro with-caught-signal-from-argv (((condition-type condition)
                                         (app app-form argv-form))
                                        &body body)
  (let ((app-sym (gensym "APP")))
    `(let ((,app-sym ,app-form))
       (caught-signal= (,condition-type ,condition)
           (parse-argv ,app-sym ,argv-form)
         ,@body))))

(defmacro with-parsed-invocations ((app app-form &rest bindings) &body body)
  (let ((app-sym (gensym "APP")))
    `(let* ((,app-sym ,app-form)
            ,@(loop for (name argv-form) in bindings
                    collect `(,name (parse-argv ,app-sym ,argv-form))))
       (let ((,app ,app-sym))
         ,@body))))

(defun run-tests ()
  "Run every registered test case and signal an error on any failure."
  (let ((tests (reverse *tests*))
        (failures 0))
    (dolist (test tests)
      (handler-case
          (run-test-case (first test) (second test))
        (error (condition)
          (incf failures)
          (format t "[FAIL] ~A~%  ~A~%" (first test) condition))))
    (format t "~&~D test(s), ~D failure(s).~%" (length tests) failures)
    (when (plusp failures)
      (error "Test suite failed with ~D failure(s)." failures))
    t))
