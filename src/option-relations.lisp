(in-package :cl-cli)

(defparameter *option-relation-rules*
  (cl-prolog:make-rulebase
   :clauses
   (list
    (cl-prolog:make-clause '(:requires ?x ?y)
                           '((cl-prolog:fail)))
    (cl-prolog:make-clause '(:requires-any ?x ?y)
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
  (let ((rulebase (cl-prolog:copy-rulebase *option-relation-rules*)))
    (dolist (spec specs rulebase)
      (dolist (target (option-requires spec))
        (let ((dependency (resolve-related-option-spec specs target)))
          (cl-prolog:rulebase-insert-clause!
           rulebase
           (cl-prolog:make-clause
            (list :requires (option-key spec) (option-key dependency))))))
      (dolist (target (option-requires-any-of spec))
        (let ((alternative (resolve-related-option-spec specs target)))
          (cl-prolog:rulebase-insert-clause!
           rulebase
           (cl-prolog:make-clause
            (list :requires-any (option-key spec) (option-key alternative))))))
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

(defun %requires-any-of-unsatisfiable-p (spec specs rulebase)
  "True when every one of SPEC's :REQUIRES-ANY-OF alternatives conflicts with it.

If so, SPEC could never be validly supplied: alone it fails the any-of
requirement, and paired with any alternative it fails a :conflicts check."
  (let ((alternatives (option-requires-any-of spec)))
    (and alternatives
         (every (lambda (target)
                  (let ((other (resolve-related-option-spec specs target)))
                    (cl-prolog:prolog-succeeds-p
                     rulebase
                     (list :conflicts (option-key spec) (option-key other)))))
                alternatives))))

(defun validate-option-relation-graph (specs)
  "Validate SPECS' :requires/:conflicts graph and return (values specs rulebase).

The rulebase built here to check for conflicting closures is exactly the one
parse-time validation needs again for transitive :requires lookups. Returning
it lets callers cache it on the app/command spec instead of rebuilding an
equivalent rulebase from scratch on every PARSE-ARGV call."
  (when (option-requirement-cycle-p specs)
    (signal-cli-error 'cli-invalid-specification
                      "Option requirements must not contain a cycle."))
  (let ((rulebase (make-option-relation-rulebase specs)))
    (when (cl-prolog:prolog-succeeds-p
           rulebase '(:invalid-closure ?root ?left ?right))
      (signal-cli-error
       'cli-invalid-specification
       "An option requirement closure contains conflicting options."))
    (dolist (spec specs)
      (when (%requires-any-of-unsatisfiable-p spec specs rulebase)
        (signal-cli-error
         'cli-invalid-specification
         (format nil "Option ~A's :requires-any-of alternatives all conflict with it, so it could never be satisfied."
                 (%option-display-name spec)))))
    (values specs rulebase)))

(defun transitive-required-option-keys (rulebase option-key)
  (mapcar (lambda (solution)
            (cl-prolog:solution-binding '?dependency solution))
          (cl-prolog:query-prolog
           rulebase
           (list :requires-transitive option-key '?dependency))))

(defun any-of-required-option-keys (rulebase option-key)
  "Return OPTION-KEY's declared :REQUIRES-ANY-OF alternatives, or NIL.

Unlike :REQUIRES (an AND of individually-mandatory dependencies), satisfying
any single alternative here is sufficient -- callers check presence of at
least one of the returned keys, they do not walk a transitive closure."
  (mapcar (lambda (solution)
            (cl-prolog:solution-binding '?alternative solution))
          (cl-prolog:query-prolog
           rulebase
           (list :requires-any option-key '?alternative))))
