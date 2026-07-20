(in-package :cl-cli)

(defparameter *environment-variable-reader* #'uiop:getenv)

(defvar *option-value-sources* nil
  "Accumulates the provenance of every option value NOT taken from the argv.

A plist of option-key -> one of :ENV, :CONFIG, or :DEFAULT, populated by
APPLY-OPTION-DEFAULTS as it fills absent keys. It is bound fresh per PARSE-ARGV
and read into the resulting invocation. A key that carries a value but is absent
from this map necessarily came from the command line, which is how
OPTION-VALUE-SOURCE derives :COMMAND-LINE without threading state through the
whole parser.")

(defun %record-option-source (spec source)
  "Note that SPEC's value was supplied by SOURCE (:env / :config / :default)."
  (setf (getf *option-value-sources* (option-key spec)) source))

(defvar *option-config-values* nil
  "A plist of option-key -> value consulted for option defaults.

Bound by PARSE-ARGV / RUN-APP from their :CONFIG argument, this lets a caller
supply values from a loaded configuration file. It sits below CLI arguments and
environment variables but above literal :default in the precedence chain, so an
explicit CLI value or environment variable still wins. Values are coerced the
same way literal defaults are (a string is run through the option parser, a list
is spread, a delimited option splits a string value).")

(defparameter *config-absent-sentinel* (list :config-absent)
  "A unique object returned by GETF when a config key is truly absent.

A fresh list is EQ only to itself, so this distinguishes \"no config entry\"
from a legitimate config value of NIL (or any keyword).")

(defun option-config-value (spec)
  "Return (VALUES config-value present-p) for SPEC from *OPTION-CONFIG-VALUES*."
  (let ((value (getf *option-config-values* (option-key spec) *config-absent-sentinel*)))
    (if (eq value *config-absent-sentinel*)
        (values nil nil)
        (values value t))))

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
                        (format nil "Invalid value for ~A: ~A (expected one of: ~{~A~^, ~})~A"
                                (%option-display-name spec)
                                raw-value
                                choices
                                (format-suggestion-suffix raw-value choices))
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

(defun validate-positional-choice (spec raw-value)
  (let ((choices (positional-spec-choices spec)))
    (when (and choices
               (stringp raw-value)
               (not (member raw-value choices :test #'string=)))
      (signal-cli-error 'cli-invalid-positional-value
                        (format nil "Invalid value for positional ~A: ~A (expected one of: ~{~A~^, ~})~A"
                                (positional-spec-key spec)
                                raw-value
                                choices
                                (format-suggestion-suffix raw-value choices))
                        :name (positional-spec-key spec)
                        :value raw-value))))

(defun parse-positional-value (spec raw-value)
  (validate-positional-choice spec raw-value)
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

(defun store-count-option (values spec action)
  "Increment the integer counter stored under SPEC's key.

Each occurrence of a :count option adds one, so `-vvv` or a repeated
`--verbose` accumulates. A count option is never a built-in, so ACTION passes
through unchanged."
  (let ((key (option-key spec)))
    (setf (getf values key) (1+ (or (getf values key) 0))))
  (values values (built-in-option-action spec action)))

(defun store-boolean-option-value (values spec action negated-p)
  (values (store-boolean-option values spec negated-p)
          (built-in-option-action spec action)))

(defun %append-option-value (values spec value)
  "Append VALUE to SPEC's accumulating list value, regardless of :multiple-p.

Used by delimited options, whose value is always a list: one occurrence such as
`--tags a,b` appends every split piece, and a later occurrence keeps appending."
  (let ((key (option->plist-key spec)))
    (setf (getf values key) (append (getf values key) (list value))))
  values)

(defun store-delimited-option-value (values spec raw-value)
  "Split RAW-VALUE on SPEC's delimiter, parse each piece, and append them all."
  (dolist (piece (split-delimited-value raw-value (option-value-delimiter spec))
                 values)
    (setf values (%append-option-value values spec
                                       (parse-option-value spec piece)))))

(defun store-key-value-pair (values spec raw-value)
  "Parse RAW-VALUE as key=value and append the pair to SPEC's accumulating alist.

A bare `key` (no `=`) records (key . T), so a flag-like define such as `-DNDEBUG`
still records the key. Values stay strings; only the split is interpreted."
  (multiple-value-bind (key value) (split-string-once raw-value #\=)
    (%append-option-value values spec (cons key (if value value t)))))

(defun store-parsed-option-value (values spec action raw-value)
  (values (cond
            ((eq (option-kind spec) :key-value)
             (store-key-value-pair values spec raw-value))
            ((and (typep spec 'option-spec)
                  (option-value-delimiter spec))
             (store-delimited-option-value values spec raw-value))
            (t
             (store-option-value values spec (parse-option-value spec raw-value))))
          (built-in-option-action spec action)))

(defun signal-option-does-not-take-value (token-name)
  (signal-cli-error 'cli-usage-error
                    (format nil "Option ~A does not take a value." token-name)))

(defun prepare-option-parser-state (app option-specs)
  ;; The declared option-relationship graph is validated once, at spec
  ;; construction time, by MAKE-APP -> %VALIDATE-APP-SPEC (which checks the
  ;; identical built-in + global (+ command) spec sets). Specs are immutable
  ;; after construction, so re-running VALIDATE-OPTION-RELATIONSHIPS-DECLARED on
  ;; every PARSE-ARGV is pure waste -- it rebuilt a cl-prolog rulebase and ran
  ;; the :invalid-closure proof search twice per parse (~82% of parse time).
  (let* ((specs (option-specs-with-built-ins app option-specs))
         (table (option-table-from-specs specs)))
    (values specs table)))

(defun map-option-values (specs parsed-values fn)
  (dolist (spec specs)
    (let ((key (option-key spec)))
      (when (plist-has-key-p parsed-values key)
        (funcall fn spec key (getf parsed-values key))))))

(defun %option-delimited-p (spec)
  (and (typep spec 'option-spec)
       (option-value-delimiter spec)))

(defun %resolved-default-pieces (spec raw)
  "Split a resolved default/config value RAW into the pieces to store for SPEC.

Delimited: a list stays, a string splits on the delimiter, NIL is empty.
Repeatable: a list stays, else a one-element list. Otherwise a one-element list
(so a scalar -- including NIL -- is stored once)."
  (cond
    ((%option-delimited-p spec)
     (cond
       ((null raw) nil)
       ((listp raw) raw)
       ((stringp raw) (split-delimited-value raw (option-value-delimiter spec)))
       (t (list raw))))
    ((option-multiple-p spec)
     (if (listp raw) raw (list raw)))
    (t (list raw))))

(defun apply-resolved-default (values spec raw)
  "Store RAW as SPEC's value using default coercion semantics.

A string piece is run through the option parser; a non-string is stored as-is.
A delimited option always accumulates its pieces into a list; a repeatable
option accumulates too; otherwise the single value is stored directly. This is
shared by both literal :default and :config resolution so they behave alike."
  (let ((append-p (%option-delimited-p spec)))
    (dolist (piece (%resolved-default-pieces spec raw) values)
      (let ((coerced (coerce-default-value piece (option-parser spec))))
        (setf values (if append-p
                         (%append-option-value values spec coerced)
                         (store-option-value values spec coerced)))))))

(defun apply-option-defaults (values specs)
  (dolist (spec specs values)
    (unless (plist-has-key-p values (option-key spec))
      (multiple-value-bind (raw-env-value env-present-p)
          (option-environment-value spec)
        (multiple-value-bind (config-value config-present-p)
            (option-config-value spec)
          (cond
            ;; Precedence below an explicit CLI value: env var, then :config,
            ;; then literal :default. A delimited env value is split the same way
            ;; a CLI value would be, so `TAGS=a,b,c` matches `--tags a,b,c`.
            ((and env-present-p (%option-delimited-p spec))
             (%record-option-source spec :env)
             (setf values (store-delimited-option-value values spec raw-env-value)))
            (env-present-p
             (%record-option-source spec :env)
             (setf values (store-option-value values spec
                                              (parse-option-value spec raw-env-value))))
            (config-present-p
             (%record-option-source spec :config)
             (setf values (apply-resolved-default values spec config-value)))
            ((option-default-present-p spec)
             (%record-option-source spec :default)
             (setf values (apply-resolved-default values spec (option-default spec))))))))))

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
