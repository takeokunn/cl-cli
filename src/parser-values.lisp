(in-package :cl-cli)

(defparameter *environment-variable-reader* #'uiop:getenv)

(defun option->plist-key (spec)
  (if (typep spec 'option-spec)
      (option-key spec)
      (positional-spec-key spec)))

(defun store-option-value (values spec value)
  (let ((key (option->plist-key spec)))
    (if (and (typep spec 'option-spec)
             (option-multiple-p spec))
        (let ((current (getf values key)))
          (setf (getf values key) (append current (list value))))
        (setf (getf values key) value)))
  values)

(defun option-environment-value (spec)
  (loop for env-var in (option-env-vars spec)
        for raw-value = (funcall *environment-variable-reader* env-var)
        when raw-value
          do (return (values raw-value t))
        finally (return (values nil nil))))

(defun option-default-values (spec)
  (let ((default (option-default spec)))
    (if (option-multiple-p spec)
        (if (listp default)
            default
            (list default))
        (list default))))

(defun coerce-default-value (raw-value parser)
  (if (stringp raw-value)
      (funcall parser raw-value)
      raw-value))

(defun validate-option-choice (spec raw-value)
  (let ((choices (option-choices spec)))
    (when (and choices
               (stringp raw-value)
               (not (member raw-value choices :test #'string=)))
      (signal-cli-error 'cli-invalid-option-value
                        (format nil "Invalid value for ~A: ~A (expected one of: ~{~A~^, ~})"
                                (%option-display-name spec)
                                raw-value
                                choices)
                        :option (option-key spec)
                        :value raw-value))))

(defun parse-option-value (spec raw-value)
  (validate-option-choice spec raw-value)
  (with-value-parse-errors ('cli-invalid-option-value
                            (format nil "Invalid value for ~A: ~A"
                                    (%option-display-name spec)
                                    raw-value)
                            :option (option-key spec)
                            :value raw-value)
    (funcall (option-parser spec) raw-value)))

(defun parse-positional-value (spec raw-value)
  (with-value-parse-errors ('cli-invalid-positional-value
                            (format nil "Invalid value for positional ~A: ~A"
                                    (positional-spec-key spec)
                                    raw-value)
                            :name (positional-spec-key spec)
                            :value raw-value)
    (funcall (positional-spec-parser spec) raw-value)))

(defun store-boolean-option (values spec negated-p)
  (store-option-value values spec
                      (parse-option-value spec (not negated-p))))

(defun built-in-option-action (spec action)
  (if (built-in-option-p spec)
      (if (eq (option-key spec) :help) :help :version)
      action))

(defun store-flag-option (values spec action)
  (values (store-option-value values spec t)
          (built-in-option-action spec action)))

(defun store-boolean-option-value (values spec action negated-p)
  (values (store-boolean-option values spec negated-p)
          (built-in-option-action spec action)))

(defun store-parsed-option-value (values spec action raw-value)
  (values (store-option-value values spec (parse-option-value spec raw-value))
          (built-in-option-action spec action)))

(defun signal-option-does-not-take-value (token-name)
  (signal-cli-error 'cli-usage-error
                    (format nil "Option ~A does not take a value." token-name)))

(defun prepare-option-parser-state (app option-specs)
  (let* ((specs (option-specs-with-built-ins app option-specs))
         (validated-specs (validate-option-relationships-declared specs))
         (table (option-table-from-specs validated-specs)))
    (values validated-specs table)))

(defun map-option-values (specs parsed-values fn)
  (dolist (spec specs)
    (let ((key (option-key spec)))
      (when (plist-has-key-p parsed-values key)
        (funcall fn spec key (getf parsed-values key))))))

(defun apply-option-defaults (values specs)
  (dolist (spec specs values)
    (unless (plist-has-key-p values (option-key spec))
      (multiple-value-bind (raw-env-value env-present-p)
          (option-environment-value spec)
        (cond
          (env-present-p
           (setf values (store-option-value values spec
                                            (parse-option-value spec raw-env-value))))
          ((option-default-present-p spec)
           (dolist (default-value (option-default-values spec))
             (setf values
                   (store-option-value values
                                       spec
                                       (coerce-default-value default-value
                                                             (option-parser spec)))))))))))

(defun validate-required-options (values specs)
  (dolist (spec specs values)
    (when (and (option-required-p spec)
               (not (plist-has-key-p values (option-key spec))))
      (signal-cli-error 'cli-missing-option-value
                        (format nil "Missing required option: ~A"
                                (%option-display-name spec))
                        :option (option-key spec)))))

(defun merge-option-values (base-values specs parsed-values)
  (let ((values base-values))
    (map-option-values specs parsed-values
                       (lambda (spec key value)
                         (declare (ignore spec))
                         (setf (getf values key) value)))
    values))

(defun collect-option-values (specs parsed-values)
  (let ((values nil))
    (map-option-values specs parsed-values
                       (lambda (spec key value)
                         (declare (ignore spec))
                         (push key values)
                         (push value values)))
    (nreverse values)))
