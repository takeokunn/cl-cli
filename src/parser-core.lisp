(in-package :cl-cli)

(defun signal-missing-positional (spec)
  (signal-cli-error 'cli-missing-positional
                    (format nil "Missing positional argument: ~A"
                            (positional-spec-key spec))
                    :name (positional-spec-key spec)))

(defun signal-unexpected-positionals (rest)
  (signal-cli-error 'cli-unexpected-argument
                    (format nil "Unexpected positional argument~P: ~{~A~^ ~}"
                            (length rest)
                            rest)
                    :argument (first rest)))

(defun parse-positional-rest-values (spec tokens)
  (if tokens
      (mapcar (lambda (value)
                (parse-positional-value spec value))
              tokens)
      (let ((default (positional-spec-default spec)))
        (cond
          ((null default) nil)
          ((listp default)
           (mapcar (lambda (value)
                     (coerce-positional-default-value spec value))
                   default))
          (t
           (list (coerce-positional-default-value spec default)))))))

(defun %validate-rest-arity (spec token-count)
  "Enforce a rest positional's :min-count / :max-count against TOKEN-COUNT."
  (let ((min (positional-spec-min-count spec))
        (max (positional-spec-max-count spec)))
    (when (and min (< token-count min))
      (signal-cli-error 'cli-missing-positional
                        (format nil "Positional ~A requires at least ~A value~:P (got ~A)."
                                (positional-spec-key spec) min token-count)
                        :name (positional-spec-key spec)))
    (when (and max (> token-count max))
      (signal-cli-error 'cli-unexpected-argument
                        (format nil "Positional ~A accepts at most ~A value~:P (got ~A)."
                                (positional-spec-key spec) max token-count)
                        :argument (positional-spec-key spec)))))

(defun apply-positional-spec (spec values tokens)
  (cond
    ((positional-spec-rest-p spec)
     (cond
       (tokens
        (%validate-rest-arity spec (length tokens))
        (setf values (store-option-value values spec
                                         (parse-positional-rest-values spec tokens))))
       ((positional-spec-default-present-p spec)
        (setf values (store-option-value values spec
                                         (parse-positional-rest-values spec nil))))
       (t
        ;; No tokens and no default: still enforce a positive :min-count.
        (%validate-rest-arity spec 0)))
     (values values nil))
    ((null tokens)
     (if (positional-spec-required-p spec)
         (signal-missing-positional spec)
         (when (positional-spec-default-present-p spec)
           (setf values (store-option-value values spec
                                            (coerce-positional-default-value
                                             spec
                                             (positional-spec-default spec))))))
     (values values nil))
    (t
     (setf values (store-option-value values spec
                                      (parse-positional-value spec
                                                              (first tokens))))
     (values values (rest tokens)))))

(defun finalize-pending-positionals (pending positional-values)
  (dolist (spec pending positional-values)
    (multiple-value-bind (new-values remaining)
        (apply-positional-spec spec positional-values nil)
      (declare (ignore remaining))
      (setf positional-values new-values))))

(defun parse-positionals (specs tokens)
  (let ((remaining tokens)
        (values nil))
    (dolist (spec specs)
      (multiple-value-setq (values remaining)
        (apply-positional-spec spec values remaining)))
    (values values remaining)))

(defun parse-literal-positionals (specs tokens)
  (multiple-value-bind (values remaining) (parse-positionals specs tokens)
    (when remaining
      (signal-unexpected-positionals remaining))
    values))

(defun resolve-default-command (app command-table)
  (or (getf (resolve-command-spec command-table (app-default-command app))
            :command)
      (signal-cli-error 'cli-invalid-specification
                        (format nil "Unknown :default-command for ~A: ~A"
                                (app-name app)
                                (app-default-command app)))))

(defun resolve-command-selection (app command-table token)
  (let ((candidate-entry (resolve-command-spec command-table token)))
    (cond
      (candidate-entry
       (values (getf candidate-entry :command) t))
      ((app-default-command app)
       (values (resolve-default-command app command-table) nil))
      ((and (app-commands app)
            (null (app-positionals app)))
       (signal-cli-error 'cli-unknown-command
                         (unknown-command-message app token)
                         :command token))
      (t
       (values nil nil)))))
