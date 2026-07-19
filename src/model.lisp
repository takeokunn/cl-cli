(in-package :cl-cli)

(defstruct (option-spec
            (:constructor %make-option-spec)
            (:conc-name "OPTION-"))
  key
  names
  negated-names
  kind
  description
  value-name
  default
  env-vars
  choices
  completion-candidates
  parser
  required-p
  requires
  requires-any-of
  conflicts-with
  multiple-p
  default-present-p
  consume-optional-value-p
  stop-parsing-p
  hidden-p
  group)

(defstruct (positional-spec
            (:constructor %make-positional-spec)
            (:conc-name "POSITIONAL-SPEC-"))
  key
  description
  parser
  default
  default-present-p
  required-p
  rest-p)

(defstruct (command-spec
            (:constructor %make-command-spec)
            (:conc-name "COMMAND-"))
  name
  aliases
  group
  description
  examples
  options
  positionals
  handler
  hidden-p)

(defstruct (app-spec
            (:constructor %make-app-spec)
            (:conc-name "APP-"))
  name
  version
  summary
  description
  global-options
  positionals
  commands
  default-command
  handler
  examples
  help-footer
  global-relation-rulebase
  ;; A COMMAND-SPEC is an explicitly reusable, composable object (README:
  ;; "reusable app, command, option, and positional specs") -- the same
  ;; instance can be spliced into :COMMANDS for more than one MAKE-APP call.
  ;; Caching a command's relation rulebase ON the shared command struct would
  ;; let a later MAKE-APP call silently overwrite the rulebase an earlier,
  ;; already-in-use app depends on. Keyed by command object (EQ) instead, this
  ;; table lives on the APP -- which is never itself shared as another app's
  ;; input -- so each app owns an independent cache even when commands are.
  (command-relation-rulebases (make-hash-table :test 'eq)))

(defstruct (invocation
            (:constructor %make-invocation)
            (:conc-name "INVOCATION-"))
  app
  command
  action
  argv0
  raw-argv
  global-options
  command-options
  positionals
  stdout
  stderr)

(defun %option-display-name (spec)
  (option-token-display-name (first (option-names spec))))

(defun resolve-related-option-spec (specs target)
  (or (when (keywordp target)
        (find target specs :key #'option-key :test #'eq))
      (when (stringp target)
        (find-if (lambda (spec)
                   (member target (option-names spec) :test #'string=))
                 specs))))

(defun %validate-related-option-target (specs spec target relation)
  (let ((resolved (resolve-related-option-spec specs target)))
    (unless resolved
      (signal-cli-error 'cli-invalid-specification
                        (format nil "Unknown option in ~A for ~A: ~A"
                                relation
                                (%option-display-name spec)
                                (option-relation-target-display-name target))))
    (when (eq (option-key resolved) (option-key spec))
      (signal-cli-error 'cli-invalid-specification
                        (format nil "Option ~A cannot declare ~A itself."
                                (%option-display-name spec)
                                relation)))
    resolved))

(defun %validate-related-option-targets (specs spec relation targets)
  (dolist (target targets)
    (%validate-related-option-target specs spec target relation)))

(defun validate-option-relationships-declared (specs)
  (dolist (spec specs)
    (%validate-related-option-targets specs spec "requires" (option-requires spec))
    (%validate-related-option-targets specs spec "requires-any-of"
                                      (option-requires-any-of spec))
    (%validate-related-option-targets specs spec "conflicts-with"
                                      (option-conflicts-with spec)))
  (validate-option-relation-graph specs))

(defun make-option (&key key name short aliases kind description value-name (default nil default-supplied-p)
                      env-var env-vars choices completion-candidates parser required-p requires
                      requires-any-of
                      conflicts-with multiple-p
                      consume-optional-value-p stop-parsing-p hidden-p)
  "Create a parsed option specification.

NAME is the long option name without leading dashes. SHORT may be a single
character or short-name string. ALIASES is a list of additional option names."
  (let* ((names (normalize-option-names name short aliases))
         (names-present-p (not (null names))))
    (unless names-present-p
      (signal-cli-error 'cli-invalid-specification
                        "An option needs at least one name."))
    (validate-non-empty-strings names "Option names")
    ;; Validate before OPTION-KEYWORD interns a symbol below: a spec that's
    ;; about to be rejected must not leak a permanent :KEYWORD-package symbol
    ;; for every rejected name an embedder tries (e.g. building specs from
    ;; untrusted plugin/config data and catching CLI-INVALID-SPECIFICATION).
    (validate-safe-identifier-names names "Option names")
    (let* ((resolved-key (or key
                             (option-keyword (or name (first names)))))
           (resolved-kind (or kind (if multiple-p :value :flag)))
           (resolved-value-name (and value-name (princ-to-string value-name)))
           (resolved-negated-names
             (normalize-negated-option-names resolved-kind names))
           (resolved-env-vars (normalize-env-vars env-var env-vars))
           (resolved-choices (normalize-option-choices choices))
           (resolved-completion-candidates
             (normalize-option-completion-candidates completion-candidates))
           (resolved-requires (normalize-option-relations requires))
           (resolved-requires-any-of (normalize-option-relations requires-any-of))
           (resolved-conflicts-with (normalize-option-relations conflicts-with))
           (resolved-parser (or parser
                                (ecase resolved-kind
                                  (:flag (lambda (value)
                                           (declare (ignore value))
                                           t))
                                  (:boolean (let ((display-name
                                                    (if (= (length (first names)) 1)
                                                        (format nil "-~A" (first names))
                                                        (format nil "--~A" (first names)))))
                                              (lambda (value)
                                                (parse-boolean-designator value
                                                                          display-name
                                                                          resolved-key))))
                                  (:value #'identity)
                                  (:optional-value #'identity))))
           (default-present-p default-supplied-p))
      (when resolved-value-name
        (validate-non-empty-strings (list resolved-value-name) "Option value names"))
      (validate-option-multiplicity resolved-kind multiple-p)
      (%make-option-spec :key resolved-key
                         :names names
                         :negated-names resolved-negated-names
                         :kind resolved-kind
                         :description (normalize-positional-description description)
                         :value-name resolved-value-name
                         :default default
                         :env-vars resolved-env-vars
                         :choices resolved-choices
                         :completion-candidates resolved-completion-candidates
                         :parser resolved-parser
                         :required-p required-p
                         :requires resolved-requires
                         :requires-any-of resolved-requires-any-of
                         :conflicts-with resolved-conflicts-with
                         :multiple-p multiple-p
                         :default-present-p default-present-p
                         :consume-optional-value-p consume-optional-value-p
                         :stop-parsing-p stop-parsing-p
                         :hidden-p hidden-p))))

(defstruct (option-group (:constructor %make-option-group))
  "A set of options that participate together in an exclusive-choice relationship."
  members
  required-p)

(defun %wire-exclusive-group (options required-p)
  "Give each option in OPTIONS the others as conflicts and a shared group marker.

Exclusivity is enforced by the same cl-prolog-backed conflict validation used
for :conflicts-with (including hidden-target-safe error messages). Conflicts an
option already declares are preserved. The shared OPTION-GROUP lets parsing add
the at-least-one obligation when REQUIRED-P, and lets help render the members as
a single choice instead of pairwise conflicts."
  (let ((keys (mapcar #'option-key options))
        (group (%make-option-group :members (mapcar #'option-key options)
                                   :required-p required-p)))
    (dolist (option options)
      (let ((others (remove (option-key option) keys)))
        (setf (option-conflicts-with option)
              (remove-duplicates (append (option-conflicts-with option) others))
              (option-group option) group)))
    (copy-list options)))

(defun exclusive-group (&rest options)
  "Wire OPTIONS as a mutually-exclusive group and return them as a fresh list.

At most one option in the group may be supplied on the command line. Splice the
result into :global-options or a command's :options, e.g.

  :global-options (exclusive-group (make-option :name \"json\" :kind :flag)
                                   (make-option :name \"yaml\" :kind :flag)
                                   (make-option :name \"table\" :kind :flag))"
  (%wire-exclusive-group options nil))

(defun required-exclusive-group (&rest options)
  "Wire OPTIONS as an exactly-one group and return them as a fresh list.

Mutual exclusion is enforced exactly as by EXCLUSIVE-GROUP (at most one member).
In addition, parsing signals CLI-MISSING-OPTION-VALUE when none of the members is
supplied, so callers must choose precisely one."
  (%wire-exclusive-group options t))

(defun make-positional (&key key name description parser (default nil default-supplied-p) required-p rest-p)
  "Create a positional argument specification."
  (when (and (null key)
             (null name))
    (signal-cli-error 'cli-invalid-specification
                      "A positional needs a key or name."))
  (when (and (null key)
             (zerop (length (ensure-string name))))
    (signal-cli-error 'cli-invalid-specification
                      "A positional name must be non-empty."))
  ;; Validate before OPTION-KEYWORD interns a symbol below: see the matching
  ;; comment in MAKE-OPTION. Only applies when NAME derives the key -- an
  ;; explicit KEY is already a keyword the caller chose directly in code, not
  ;; a string, so there is nothing to validate or intern here.
  (when (and (null key) name)
    (validate-safe-identifier-names (list (ensure-string name)) "Positional name"))
  (let ((resolved-key (or key
                          (option-keyword name)))
        (spec (%make-positional-spec)))
    (setf (positional-spec-key spec) resolved-key
          (positional-spec-description spec) (normalize-positional-description description)
          (positional-spec-parser spec) (or parser #'identity)
          (positional-spec-default spec) default
          (positional-spec-default-present-p spec) default-supplied-p
          (positional-spec-required-p spec) required-p
          (positional-spec-rest-p spec) rest-p)
    spec))

(defun make-command (&key name aliases group description examples options positionals handler hidden-p)
  "Create a command specification."
  (let* ((resolved-name (and name (canonical-name name)))
         (resolved-aliases (normalize-command-aliases aliases)))
    (when (or (null resolved-name)
              (zerop (length resolved-name)))
      (signal-cli-error 'cli-invalid-specification
                        "A command needs a non-empty name."))
    (validate-non-empty-strings resolved-aliases "Command aliases")
    (validate-safe-identifier-names (list resolved-name) "Command name")
    (validate-safe-identifier-names resolved-aliases "Command aliases")
    (%make-command-spec :name resolved-name
                        :aliases resolved-aliases
                        :group (normalize-command-group group)
                        :description (normalize-positional-description description)
                        :examples (normalize-example-strings examples)
                        :options options
                        :positionals positionals
                        :handler handler
                        :hidden-p hidden-p)))

(defun %option-table-entries (spec)
  (append (loop for name in (option-names spec)
                collect (list name nil))
          (loop for name in (option-negated-names spec)
                collect (list name t))))

(defun %validate-user-option-keys (specs owner-name)
  "Reject a user-declared option whose resolved key is :HELP or :VERSION.

BUILT-IN-OPTION-P and BUILT-IN-OPTION-ACTION (src/model-helpers.lisp,
src/parser-values.lisp) key off OPTION-KEY's value alone, not object identity
with the real built-in spec -- an ordinary option given :KEY :HELP or
:KEY :VERSION would silently force the :HELP/:VERSION dispatch action
whenever it is parsed, regardless of its own :KIND."
  (dolist (spec specs)
    (when (member (option-key spec) '(:help :version))
      (signal-cli-error 'cli-invalid-specification
                        (format nil "Option ~A for ~A cannot use the reserved key ~S."
                                (%option-display-name spec)
                                owner-name
                                (option-key spec))))))

(defun %validate-option-key-uniqueness (specs owner-name)
  "Reject two options in SPECS that resolve to the same OPTION-KEY.

Distinct declared names can still collide on key -- OPTION-KEYWORD downcases
its argument, so single-character names \"-a\" and \"-A\" (deliberately
case-sensitive as CLI tokens; see CANONICAL-OPTION-NAME) both resolve to
:A. A key collision means the two specs share one storage slot in the parsed
values plist, silently overwriting each other, and only the last spec with
that key survives :requires/:conflicts-with resolution."
  (let ((table (make-hash-table :test 'eq)))
    (dolist (spec specs)
      (%register-table-entry table
                             (option-key spec)
                             t
                             (format nil "option key for ~A" owner-name)
                             (format nil "~S" (option-key spec))))))

(defun %validate-option-table (specs)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (spec specs specs)
      (dolist (entry (%option-table-entries spec))
        (destructuring-bind (name negated-p) entry
          (declare (ignore negated-p))
          (let ((key (canonical-option-name name)))
            (%register-table-entry table
                                   key
                                   t
                                   "option name"
                                   (option-token-display-name key))))))))

(defun %validate-command-table (commands)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (command commands table)
      (%register-table-entry table
                             (command-name command)
                             t
                             "command name"
                             (command-name command))
      (dolist (alias (command-aliases command))
        (%register-table-entry table
                               alias
                               t
                               "command name"
                               alias)))))

(defun %validate-positional-sequence (positionals owner-name)
  (let ((seen-keys (make-hash-table :test 'eq))
        (rest-seen-p nil)
        (optional-seen-p nil))
    (dolist (spec positionals positionals)
      (let ((key (positional-spec-key spec)))
        (when (gethash key seen-keys)
          (signal-cli-error 'cli-invalid-specification
                            (format nil "Duplicate positional key for ~A: ~A"
                                    owner-name
                                    key)))
        (setf (gethash key seen-keys) t))
      (when rest-seen-p
        (signal-cli-error 'cli-invalid-specification
                          (format nil "Rest positional for ~A must be last."
                                  owner-name)))
      ;; Tokens are assigned to positionals greedily in declared order with no
      ;; backtracking (APPLY-POSITIONAL-SPEC), so a required positional after
      ;; an optional one can never receive a value: the optional one consumes
      ;; it first, then the required one fails as "missing" even though a
      ;; value was supplied.
      (if (positional-spec-required-p spec)
          (when optional-seen-p
            (signal-cli-error 'cli-invalid-specification
                              (format nil "Required positional for ~A must not follow an optional positional."
                                      owner-name)))
          (setf optional-seen-p t))
      (when (positional-spec-rest-p spec)
        (setf rest-seen-p t)))))

(defun %validate-app-spec (app)
  (let* ((built-ins (option-specs-with-built-ins app nil))
         (global-specs (append built-ins (app-global-options app)))
         (command-table (%validate-command-table (app-commands app))))
    (%validate-positional-sequence (app-positionals app)
                                   (app-name app))
    (%validate-user-option-keys (app-global-options app) (app-name app))
    (multiple-value-bind (validated-global-specs global-rulebase)
        (validate-option-relationships-declared global-specs)
      (declare (ignore validated-global-specs))
      (setf (app-global-relation-rulebase app) global-rulebase))
    (%validate-option-table global-specs)
    (%validate-option-key-uniqueness global-specs (app-name app))
    (dolist (command (app-commands app))
      (%validate-positional-sequence (command-positionals command)
                                     (command-name command))
      (%validate-user-option-keys (command-options command) (command-name command))
      (let ((command-specs (append built-ins
                                   (app-global-options app)
                                   (command-options command))))
        (multiple-value-bind (validated-command-specs command-rulebase)
            (validate-option-relationships-declared command-specs)
          (declare (ignore validated-command-specs))
          (setf (gethash command (app-command-relation-rulebases app))
                command-rulebase))
        (%validate-option-table command-specs)
        (%validate-option-key-uniqueness command-specs (command-name command))))
    (when (and (app-default-command app)
               (null (gethash (app-default-command app) command-table)))
      (signal-cli-error 'cli-invalid-specification
                        (format nil "Unknown :default-command for ~A: ~A"
                                (app-name app)
                                (app-default-command app)))))
  app)
