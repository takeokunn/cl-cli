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

(defun normalize-deprecated (deprecated)
  "Normalize a :deprecated designator into NIL, T, or a non-empty reason string.

A string is kept as the human-readable reason; any other true value becomes a
bare T (deprecated without a stated reason)."
  (cond
    ((null deprecated) nil)
    ((stringp deprecated) (normalize-non-empty-string deprecated "Deprecation reasons"))
    (t t)))

(defun %register-table-entry (table key value kind display-name)
  (when (gethash key table)
    (signal-cli-error 'cli-invalid-specification
                      (format nil "Duplicate ~A: ~A" kind display-name)))
  (setf (gethash key table) value))

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

(defun %control-character-p (char)
  (let ((code (char-code char)))
    (or (< code 32)
        (= code 127)
        (and (>= code 128) (< code 160)))))

(defun validate-no-control-characters (values kind)
  "Signal CLI-INVALID-SPECIFICATION when VALUES contain terminal controls."
  (dolist (value values values)
    (when (find-if #'%control-character-p value)
      (signal-cli-error 'cli-invalid-specification
                        (format nil "~A must not contain control characters: ~S"
                                kind value)))))

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
             (member kind '(:flag :boolean :count :key-value)))
    (signal-cli-error 'cli-invalid-specification
                      (format nil "Option kind ~A cannot be combined with :multiple-p."
                              kind))))

(defun normalize-value-delimiter (delimiter)
  "Normalize a :value-delimiter into a one-character string, or NIL.

Accepts a character or a one-character string. A single character keeps the
list semantics unambiguous (\"split on comma\") and lets UIOP:SPLIT-STRING use
it directly as its separator bag."
  (when delimiter
    (let ((string (etypecase delimiter
                    (character (string delimiter))
                    (string delimiter)
                    (symbol (string delimiter)))))
      (unless (= (length string) 1)
        (signal-cli-error 'cli-invalid-specification
                          (format nil "A :value-delimiter must be a single character, got: ~S"
                                  delimiter)))
      string)))

(defun split-delimited-value (raw delimiter)
  "Split RAW on the DELIMITER string, dropping empty pieces.

Empty pieces (from a leading, trailing, or doubled delimiter such as \"a,,b\")
are dropped so a typed parser is never handed an empty token."
  (remove-if (lambda (piece) (zerop (length piece)))
             (uiop:split-string raw :separator delimiter)))

(defun variadic-value-count-p (count)
  "True when COUNT is a variadic :value-count designator (:+ one-or-more, :* any)."
  (member count '(:+ :*)))

(defun multi-value-count-p (count)
  "True when COUNT means an option consumes more than one value (fixed or variadic)."
  (or (variadic-value-count-p count)
      (and (integerp count) (> count 1))))

(defparameter +value-hints+ '(:file :dir)
  "Shell-completion value hints: :file completes file paths, :dir directories.")

(defun normalize-value-hint (hint context)
  "Validate a :value-hint designator (NIL, :file, or :dir) at construction time."
  (when hint
    (unless (member hint +value-hints+)
      (signal-cli-error 'cli-invalid-specification
                        (format nil "~A :value-hint must be one of ~{~A~^, ~}, got: ~S"
                                context +value-hints+ hint)))
    hint))

(defparameter +typed-value-types+ '(:string :integer :number :float :boolean)
  "Value types MAKE-OPTION / MAKE-POSITIONAL accept as :type.

Each names a built-in value parser so common domain validation (positive
integers, bounded counts, numeric flags) needs no hand-written :parser lambda.
:string is the identity parser; the rest coerce and validate.")

(defparameter +numeric-value-types+ '(:integer :number :float)
  "Subset of +TYPED-VALUE-TYPES+ whose values :min / :max bounds may constrain.")

(defun %read-cli-real-number (raw)
  "Read RAW as a single Lisp real number without evaluation, or NIL.

*READ-EVAL* is bound off so a payload such as \"#.(delete-file ...)\" can never
execute code, and the whole string must be exactly one numeric token plus
optional surrounding whitespace: \"1 2\" and \"3x\" (which the reader would
otherwise read as 1 or a symbol and stop early) are rejected because the
non-whitespace input was not fully consumed."
  (handler-case
      (multiple-value-bind (value end)
          (let ((*read-eval* nil))
            (read-from-string raw nil nil))
        (when (and (realp value)
                   (loop for index from end below (length raw)
                         always (find (char raw index)
                                      '(#\Space #\Tab #\Newline #\Return #\Page))))
          value))
    (error () nil)))

(defun %parse-typed-integer (raw)
  ;; PARSE-INTEGER (no :junk-allowed) already rejects trailing/leading junk but
  ;; permits surrounding whitespace, which matches how a shell would pass "3".
  (let ((value (ignore-errors (parse-integer raw))))
    (if (integerp value)
        value
        (error "Expected an integer, got: ~A" raw))))

(defun %parse-typed-number (raw float-p)
  (let ((value (%read-cli-real-number raw)))
    (cond
      ((null value)
       (error "Expected a number, got: ~A" raw))
      (float-p (coerce value 'double-float))
      (t value))))

(defun %enforce-numeric-bounds (value min max)
  (when (and min (< value min))
    (error "Value ~A is below the allowed minimum ~A." value min))
  (when (and max (> value max))
    (error "Value ~A is above the allowed maximum ~A." value max))
  value)

(defun build-typed-value-parser (type min max)
  "Return a value-parser closure for TYPE enforcing inclusive MIN / MAX bounds.

Parse and bound failures signal plain ERRORs; the surrounding value-parse
machinery (WITH-VALUE-PARSE-ERRORS) rewraps them as CLI-INVALID-OPTION-VALUE /
CLI-INVALID-POSITIONAL-VALUE usage errors, so a bad typed value is reported the
same way a failing :parser lambda would be."
  (let ((base (ecase type
                (:string #'identity)
                (:integer #'%parse-typed-integer)
                (:number (lambda (raw) (%parse-typed-number raw nil)))
                (:float (lambda (raw) (%parse-typed-number raw t)))
                (:boolean (lambda (raw) (parse-boolean-designator raw))))))
    (if (or min max)
        (lambda (raw) (%enforce-numeric-bounds (funcall base raw) min max))
        base)))

(defun validate-rest-count-spec (key rest-p min-count max-count)
  "Validate :min-count / :max-count for a positional at construction time."
  (when (or min-count max-count)
    (unless rest-p
      (signal-cli-error 'cli-invalid-specification
                        (format nil "Positional ~S: :min-count / :max-count require :rest-p." key)))
    (dolist (bound (list min-count max-count))
      (when (and bound
                 (not (and (integerp bound) (>= bound 0))))
        (signal-cli-error 'cli-invalid-specification
                          (format nil "Positional ~S: :min-count / :max-count must be non-negative integers, got: ~S"
                                  key bound))))
    (when (and min-count max-count (> min-count max-count))
      (signal-cli-error 'cli-invalid-specification
                        (format nil "Positional ~S: :min-count ~A must not exceed :max-count ~A."
                                key min-count max-count)))))

(defun validate-typed-value-spec (type min max parser context)
  "Validate a :type / :min / :max / :parser combination at construction time.

CONTEXT is a human-readable owner label used in error messages. Returns no
useful value; signals CLI-INVALID-SPECIFICATION on any inconsistency."
  (when type
    (unless (member type +typed-value-types+)
      (signal-cli-error 'cli-invalid-specification
                        (format nil "~A :type must be one of ~{~A~^, ~}, got: ~S"
                                context +typed-value-types+ type)))
    (when parser
      ;; A :type already fully determines the parser; honoring both would make
      ;; it ambiguous which one runs (and in which order), so reject the combo.
      (signal-cli-error 'cli-invalid-specification
                        (format nil "~A cannot combine :type with an explicit :parser."
                                context))))
  (when (or min max)
    (dolist (bound (list min max))
      (when (and bound (not (realp bound)))
        (signal-cli-error 'cli-invalid-specification
                          (format nil "~A :min / :max must be real numbers, got: ~S"
                                  context bound))))
    (unless (member (or type :string) +numeric-value-types+)
      (signal-cli-error 'cli-invalid-specification
                        (format nil "~A :min / :max require a numeric :type (~{~A~^, ~})."
                                context +numeric-value-types+)))
    (when (and min max (> min max))
      (signal-cli-error 'cli-invalid-specification
                        (format nil "~A :min ~A must not exceed :max ~A."
                                context min max)))))
