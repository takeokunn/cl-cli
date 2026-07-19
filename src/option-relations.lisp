(in-package :cl-cli)

(defparameter *option-relation-rules*
  (cl-prolog:make-rulebase
   :clauses
   (list
    (cl-prolog:make-clause '(:requires ?x ?y)
                           '((cl-prolog:fail)))
    (cl-prolog:make-clause '(:conflicts ?x ?y)
                           '((cl-prolog:fail)))
    (cl-prolog:make-clause '(:requires-transitive ?x ?y)
                           '((:requires ?x ?y)))
    (cl-prolog:make-clause '(:requires-transitive ?x ?y)
                           '((:requires ?x ?z)
                             (:requires-transitive ?z ?y)))
    (cl-prolog:make-clause '(:reachable ?x ?x))
    (cl-prolog:make-clause '(:reachable ?x ?y)
                           '((:requires-transitive ?x ?y)))
    (cl-prolog:make-clause '(:invalid-closure ?root ?left ?right)
                           '((:reachable ?root ?left)
                             (:reachable ?root ?right)
                             (:conflicts ?left ?right))))))

(defun make-option-relation-rulebase (specs)
  (let ((rulebase
          (cl-prolog:make-rulebase
           :clauses
           (cl-prolog:rulebase-visible-clauses *option-relation-rules*))))
    (dolist (spec specs rulebase)
      (dolist (target (option-requires spec))
        (let ((dependency (resolve-related-option-spec specs target)))
          (cl-prolog:rulebase-insert-clause!
           rulebase
           (cl-prolog:make-clause
            (list :requires (option-key spec) (option-key dependency))))))
      (dolist (target (option-conflicts-with spec))
        (let ((other (resolve-related-option-spec specs target)))
          (cl-prolog:rulebase-insert-clause!
           rulebase
           (cl-prolog:make-clause
            (list :conflicts (option-key spec) (option-key other))))
          (cl-prolog:rulebase-insert-clause!
           rulebase
           (cl-prolog:make-clause
            (list :conflicts (option-key other) (option-key spec)))))))))

(defun option-requirement-cycle-p (specs)
  (let ((visiting (make-hash-table :test #'equal))
        (visited (make-hash-table :test #'equal)))
    (labels ((visit (spec)
               (let ((key (option-key spec)))
                 (cond
                   ((gethash key visiting) t)
                   ((gethash key visited) nil)
                   (t
                    (setf (gethash key visiting) t)
                    (prog1
                        (some (lambda (target)
                                (visit (resolve-related-option-spec specs target)))
                              (option-requires spec))
                      (remhash key visiting)
                      (setf (gethash key visited) t)))))))
      (some #'visit specs))))

(defun validate-option-relation-graph (specs)
  (when (option-requirement-cycle-p specs)
    (signal-cli-error 'cli-invalid-specification
                      "Option requirements must not contain a cycle."))
  (let ((rulebase (make-option-relation-rulebase specs)))
    (when (cl-prolog:prolog-succeeds-p
           rulebase '(:invalid-closure ?root ?left ?right))
      (signal-cli-error
       'cli-invalid-specification
       "An option requirement closure contains conflicting options."))
    specs))

(defun transitive-required-option-keys (rulebase option-key)
  (mapcar (lambda (solution)
            (cl-prolog:solution-binding '?dependency solution))
          (cl-prolog:query-prolog
           rulebase
           (list :requires-transitive option-key '?dependency))))
