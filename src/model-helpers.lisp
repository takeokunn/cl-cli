(in-package :cl-cli)

(defun normalize-option-names (name short aliases)
  (normalize-transformed-list (append (when name (list name))
                                      (when short (list short))
                                      aliases)
                              #'canonical-option-name))

(defun normalize-transformed-list (items transformer &key (test #'string=))
  (remove-duplicates
   (mapcar transformer (remove nil items))
   :test test))

(defun normalize-non-empty-string (value kind)
  (let ((normalized (princ-to-string value)))
    (validate-non-empty-strings (list normalized) kind)
    normalized))

(defun normalize-string-sequence (items transformer kind &key (test #'string=))
  (let ((normalized (normalize-transformed-list items transformer :test test)))
    (validate-non-empty-strings normalized kind)
    normalized))

(defun normalize-negated-option-names (kind names)
  (when (eq kind :boolean)
    (remove-duplicates
     (loop for name in names
           when (> (length name) 1)
             collect (format nil "no-~A" name))
     :test #'string=)))

(defun normalize-command-aliases (aliases)
  (normalize-transformed-list aliases #'canonical-name))

(defun normalize-positional-description (description)
  (and description (princ-to-string description)))

(defun normalize-example-strings (examples)
  (normalize-string-sequence examples #'princ-to-string "Examples"))

(defun normalize-command-group (group)
  (and group
       (normalize-non-empty-string group "Command groups")))

(defun %register-table-entry (table key value kind display-name)
  (when (gethash key table)
    (signal-cli-error 'cli-invalid-specification
                      (format nil "Duplicate ~A: ~A" kind display-name)))
  (setf (gethash key table) value))

(defun app-version-string (app)
  (let ((version (app-version app)))
    (when version
      (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) version)))
        (when (> (length trimmed) 0)
          trimmed)))))

(defun app-supports-version-p (app)
  (not (null (app-version-string app))))

(defun make-built-in-option (name short description key)
  (make-option :short short
               :aliases (list name)
               :kind :flag
               :description description
               :hidden-p t
               :key key))

(defun make-built-in-help-option ()
  (make-built-in-option "help" #\h
                        "Show help text for this command."
                        :help))

(defun make-built-in-version-option ()
  (make-built-in-option "version" #\V
                        "Show version information."
                        :version))

(defun built-in-option-p (spec)
  (member (option-key spec) '(:help :version)))

(defun built-in-option-specs (app)
  (let ((specs (list (make-built-in-help-option))))
    (when (app-supports-version-p app)
      (push (make-built-in-version-option) specs))
    (nreverse specs)))

(defun option-specs-with-built-ins (app option-specs)
  (append (built-in-option-specs app)
          option-specs))

(defun normalize-env-vars (env-var env-vars)
  (normalize-string-sequence (append (when env-var (list env-var))
                                      env-vars)
                             #'ensure-string
                             "Environment variable names"))

(defun normalize-option-choices (choices)
  (normalize-string-sequence choices #'ensure-string "Option choices"))

(defun normalize-option-completion-candidate (candidate)
  (cond
    ((or (stringp candidate)
         (symbolp candidate)
         (characterp candidate))
     (cons (ensure-string candidate) nil))
    ((consp candidate)
     (let* ((value (ensure-string (car candidate)))
            (tail (cdr candidate))
            (description
              (cond
                ((null tail) nil)
                ((consp tail)
                 (if (null (cdr tail))
                     (car tail)
                     (signal-cli-error
                      'cli-invalid-specification
                      (format nil "Completion candidate must be a string or a (value . description) pair: ~S"
                              candidate))))
                (t tail))))
       (cons value
             (and description
                  (normalize-non-empty-string description
                                              "Completion candidate descriptions")))))
    (t
     (signal-cli-error
      'cli-invalid-specification
      (format nil "Completion candidate must be a string or a (value . description) pair: ~S"
              candidate)))))

(defun normalize-option-completion-candidates (candidates)
  (let ((table (make-hash-table :test #'equal))
        (ordered '()))
    (dolist (candidate (remove nil candidates))
      (let* ((normalized (normalize-option-completion-candidate candidate))
             (value (car normalized)))
        (validate-non-empty-strings (list value) "Completion candidate values")
        (unless (gethash value table)
          (setf (gethash value table) t)
          (push normalized ordered))))
    (nreverse ordered)))

(defun validate-non-empty-strings (values kind)
  (dolist (value values values)
    (when (zerop (length value))
      (signal-cli-error 'cli-invalid-specification
                        (format nil "~A must be non-empty." kind)))))

(defparameter +safe-cli-name-characters+
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."
  "Characters permitted in a CLI identifier name (app / command / option / alias).

App, command and option names are interpolated into generated shell-completion
scripts, which the user later sources. Restricting identifiers to this set stops
an author- or config-supplied name (e.g. \"foo; rm -rf ~\") from injecting shell
syntax into that output. Free-form display text -- descriptions, value names,
choices, candidate labels -- is not restricted here; the renderers already pass
it through %completion-shell-quote.")

(defun %safe-cli-name-p (name)
  (and (plusp (length name))
       (every (lambda (char) (find char +safe-cli-name-characters+)) name)))

(defun validate-safe-identifier-names (values kind)
  "Signal CLI-INVALID-SPECIFICATION unless every name in VALUES is a safe identifier."
  (dolist (value values values)
    (unless (%safe-cli-name-p value)
      (signal-cli-error 'cli-invalid-specification
                        (format nil
                                "~A may contain only letters, digits, '-', '_' or '.': ~S"
                                kind value)))))

(defun normalize-option-relation-target (target)
  (etypecase target
    (string (canonical-option-name target))
    (symbol (option-keyword target))
    (character (canonical-option-name target))))

(defun normalize-option-relations (targets)
  (normalize-transformed-list targets #'normalize-option-relation-target
                              :test #'equal))

(defun parse-boolean-designator (value &optional display-name option-key)
  (flet ((signal-invalid-boolean ()
           (if (and display-name option-key)
               (signal-cli-error 'cli-invalid-option-value
                                 (format nil "Invalid value for ~A: ~A"
                                         display-name
                                         value)
                                 :option option-key
                                 :value value)
               (error "Unrecognized boolean value: ~A" value))))
    (cond
      ((typep value 'boolean) value)
      ((stringp value)
       (let ((normalized (string-downcase value)))
         (cond
           ((member normalized '("1" "t" "true" "yes" "on" "enable" "enabled")
                    :test #'string=)
            t)
           ((member normalized '("0" "nil" "false" "no" "off" "disable" "disabled")
                    :test #'string=)
            nil)
           (t
            (signal-invalid-boolean)))))
      (t
       (signal-invalid-boolean)))))

(defun validate-option-multiplicity (kind multiple-p)
  (when (and multiple-p
             (member kind '(:flag :boolean)))
    (signal-cli-error 'cli-invalid-specification
                      (format nil "Option kind ~A cannot be combined with :multiple-p."
                              kind))))
