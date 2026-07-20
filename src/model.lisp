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
  value-type
  value-min
  value-max
  value-delimiter
  value-count
  value-hint
  default
  env-vars
  choices
  completion-candidates
  complete
  parser
  required-p
  required-if
  required-unless
  requires
  requires-any-of
  conflicts-with
  multiple-p
  default-present-p
  consume-optional-value-p
  stop-parsing-p
  hidden-p
  deprecated
  help-group
  group)

(defstruct (positional-spec
            (:constructor %make-positional-spec)
            (:conc-name "POSITIONAL-SPEC-"))
  key
  description
  value-type
  value-min
  value-max
  choices
  completion-candidates
  value-hint
  complete
  parser
  default
  default-present-p
  required-p
  rest-p
  min-count
  max-count)

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
  subcommands
  default-command
  handler
  hidden-p
  deprecated
  help-footer)

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
  see-also
  authors
  manual-date
  allow-abbreviated-options
  expand-response-files
  allow-negative-numbers
  require-command
  (auto-help t)
  global-relation-rulebase
  dynamic-completion-index
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
  command-path
  action
  argv0
  raw-argv
  global-options
  command-options
  positionals
  option-sources
  stdout
  stderr)

(defun %option-display-name (spec)
  (option-token-display-name (first (option-names spec))))

(defun %option-key-table (specs)
  (let ((table (make-hash-table :test #'eq)))
    (dolist (spec specs table)
      (setf (gethash (option-key spec) table) spec))))

(defun %option-target-table (specs)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (spec specs table)
      (setf (gethash (option-key spec) table) spec)
      (dolist (name (option-names spec))
        (setf (gethash name table) spec)))))

(defun %lookup-option-target (table target)
  (gethash target table))

(defun resolve-related-option-spec (specs target)
  (%lookup-option-target (%option-target-table specs) target))

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
    (%validate-related-option-targets specs spec "required-if"
                                      (option-required-if spec))
    (%validate-related-option-targets specs spec "required-unless"
                                      (option-required-unless spec))
    (%validate-related-option-targets specs spec "conflicts-with"
                                      (option-conflicts-with spec)))
  (validate-option-relation-graph specs))

(defun make-option (&key key name short aliases kind description value-name
                      type min max value-delimiter value-count value-hint complete
                      (default nil default-supplied-p)
                      env-var env-vars choices completion-candidates parser required-p
                      required-if required-unless requires
                      requires-any-of
                      conflicts-with multiple-p
                      consume-optional-value-p stop-parsing-p hidden-p deprecated group)
  "Create a parsed option specification.

NAME is the long option name without leading dashes. SHORT may be a single
character or short-name string. ALIASES is a list of additional option names.

TYPE selects a built-in value parser (:integer, :number, :float, :boolean, or
the default :string) for a :value option; MIN and MAX add inclusive bounds for
numeric types. A :type and an explicit :parser are mutually exclusive. KIND
:count turns the option into a repeatable counter (`-vvv` => 3) that defaults
to 0. VALUE-DELIMITER (a single character) makes a :value option split one
occurrence into a list (`--tags a,b,c` => (\"a\" \"b\" \"c\")), parsing each
piece and accumulating across occurrences. GROUP is a help-section label that
groups related options under a heading, mirroring a command's :group.

KIND :key-value parses each occurrence as `key=value` (a bare `key` yields
value T) and accumulates the pairs into an alist, so `-D a=1 -D b=2` reads as
((\"a\" . \"1\") (\"b\" . \"2\")).

VALUE-COUNT N makes a :value option consume exactly N following tokens as a
parsed list (`--point 1 2` => (1 2)); too few remaining tokens signal
CLI-MISSING-OPTION-VALUE, and with :multiple-p each occurrence contributes its
own N-element list. VALUE-COUNT may also be :+ (one or more) or :* (zero or
more), which greedily consume following tokens up to the next option-like token."
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
           (resolved-value-name (cond
                                  (value-name (princ-to-string value-name))
                                  ((eq resolved-kind :key-value) "KEY=VALUE")
                                  (t nil)))
           (resolved-negated-names
             (normalize-negated-option-names resolved-kind names))
           (resolved-env-vars (normalize-env-vars env-var env-vars))
           (resolved-choices (normalize-option-choices choices))
           (resolved-completion-candidates
             (normalize-option-completion-candidates completion-candidates))
           (resolved-requires (normalize-option-relations requires))
           (resolved-required-if (normalize-option-relations required-if))
           (resolved-required-unless (normalize-option-relations required-unless))
           (resolved-requires-any-of (normalize-option-relations requires-any-of))
           (resolved-conflicts-with (normalize-option-relations conflicts-with))
           ;; Validate the :type / :min / :max / :parser combination BEFORE
           ;; RESOLVED-PARSER runs BUILD-TYPED-VALUE-PARSER: that helper's ECASE
           ;; would otherwise raise a raw CASE-FAILURE on an unknown :type
           ;; instead of the CLI-INVALID-SPECIFICATION callers expect. LET* runs
           ;; bindings top-to-bottom, so this guard fires first.
           (%typed-value-check
             (progn
               ;; Restrict typed values to :value options. An :optional-value
               ;; stores the sentinel T for its bare form (`--opt` with no
               ;; value), which a typed parser such as :integer cannot accept --
               ;; so allowing :type there would make the bare form signal a
               ;; spurious invalid-value error at parse time.
               (when (and (or type min max)
                          (not (eq resolved-kind :value)))
                 (signal-cli-error 'cli-invalid-specification
                                   (format nil "Option ~A: :type / :min / :max apply only to :value options, not ~A."
                                           (option-token-display-name (first names))
                                           resolved-kind)))
               (validate-typed-value-spec type min max parser
                                          (format nil "Option ~A"
                                                  (option-token-display-name (first names))))
               (when (and value-delimiter (not (eq resolved-kind :value)))
                 (signal-cli-error 'cli-invalid-specification
                                   (format nil "Option ~A: :value-delimiter applies only to :value options, not ~A."
                                           (option-token-display-name (first names))
                                           resolved-kind)))
               (when value-count
                 (unless (or (variadic-value-count-p value-count)
                             (and (integerp value-count) (>= value-count 1)))
                   (signal-cli-error 'cli-invalid-specification
                                     (format nil "Option ~A: :value-count must be a positive integer or :+ / :*, got: ~S"
                                             (option-token-display-name (first names))
                                             value-count)))
                 (unless (eq resolved-kind :value)
                   (signal-cli-error 'cli-invalid-specification
                                     (format nil "Option ~A: :value-count applies only to :value options, not ~A."
                                             (option-token-display-name (first names))
                                             resolved-kind)))
                 (when (and value-delimiter (multi-value-count-p value-count))
                   (signal-cli-error 'cli-invalid-specification
                                     (format nil "Option ~A: :value-count cannot combine with :value-delimiter."
                                             (option-token-display-name (first names))))))
               (when (and value-hint
                          (member resolved-kind '(:flag :boolean :count)))
                 (signal-cli-error 'cli-invalid-specification
                                   (format nil "Option ~A: :value-hint applies only to value-bearing options, not ~A."
                                           (option-token-display-name (first names))
                                           resolved-kind)))
               (normalize-value-hint value-hint
                                     (format nil "Option ~A"
                                             (option-token-display-name (first names))))))
           (resolved-value-delimiter (normalize-value-delimiter value-delimiter))
           (resolved-parser (cond
                              (type (build-typed-value-parser type min max))
                              (parser parser)
                              (t (ecase resolved-kind
                                   (:flag (lambda (value)
                                            (declare (ignore value))
                                            t))
                                   (:count (lambda (value)
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
                                   (:optional-value #'identity)
                                   (:key-value #'identity)))))
           ;; A :count option is an accumulating counter, so it always has a
           ;; well-defined resolved value even when never supplied: default it
           ;; to 0 (unless the caller overrode :default) so OPTION-VALUE returns
           ;; a number rather than NIL.
           (count-default-p (and (eq resolved-kind :count)
                                 (not default-supplied-p)))
           (resolved-default (if count-default-p 0 default))
           (default-present-p (or default-supplied-p count-default-p)))
      (declare (ignore %typed-value-check))
      (when resolved-value-name
        (validate-non-empty-strings (list resolved-value-name) "Option value names")
        (validate-no-control-characters (list resolved-value-name) "Option value names"))
      (when (and complete (not (functionp complete)))
        (signal-cli-error 'cli-invalid-specification
                          (format nil "Option ~A: :complete must be a function."
                                  (option-token-display-name (first names)))))
      (validate-option-multiplicity resolved-kind multiple-p)
      (%make-option-spec :key resolved-key
                         :names names
                         :negated-names resolved-negated-names
                         :kind resolved-kind
                         :description (normalize-positional-description description)
                         :value-name resolved-value-name
                         :value-type type
                         :value-min min
                         :value-max max
                         :value-delimiter resolved-value-delimiter
                         :value-count value-count
                         :value-hint value-hint
                         :default resolved-default
                         :env-vars resolved-env-vars
                         :choices resolved-choices
                         :completion-candidates resolved-completion-candidates
                         :complete complete
                         :parser resolved-parser
                         :required-p required-p
                         :required-if resolved-required-if
                         :required-unless resolved-required-unless
                         :requires resolved-requires
                         :requires-any-of resolved-requires-any-of
                         :conflicts-with resolved-conflicts-with
                         :multiple-p multiple-p
                         :default-present-p default-present-p
                         :consume-optional-value-p consume-optional-value-p
                         :stop-parsing-p stop-parsing-p
                         :hidden-p hidden-p
                         :deprecated (normalize-deprecated deprecated)
                         :help-group (normalize-command-group group)))))

(defstruct (option-group (:constructor %make-option-group))
  "A set of options that participate together in a group relationship.

MODE is :EXCLUSIVE (at most one member, via pairwise conflicts) or :INCLUSIVE
(all-or-none: if any member is supplied, all must be)."
  members
  required-p
  (mode :exclusive))

(defun %wire-exclusive-group (options required-p)
  "Give each option in OPTIONS the others as conflicts and a shared group marker.

Exclusivity is enforced by the same cl-prolog-backed conflict validation used
for :conflicts-with (including hidden-target-safe error messages). Conflicts an
option already declares are preserved. The shared OPTION-GROUP lets parsing add
the at-least-one obligation when REQUIRED-P, and lets help render the members as
a single choice instead of pairwise conflicts."
  (let ((keys (mapcar #'option-key options))
        (group (%make-option-group :members (mapcar #'option-key options)
                                   :required-p required-p
                                   :mode :exclusive)))
    (dolist (option options)
      (let ((others (remove (option-key option) keys)))
        (setf (option-conflicts-with option)
              (remove-duplicates (append (option-conflicts-with option) others))
              (option-group option) group)))
    (copy-list options)))

(defun inclusive-group (&rest options)
  "Wire OPTIONS as an all-or-none group and return them as a fresh list.

If any member is supplied, every member must be supplied; supplying none is also
fine. Splice the result into :global-options or a command's :options. Unlike
EXCLUSIVE-GROUP this adds no conflicts -- the members are meant to be used
together (for example a paired --host and --port)."
  (let ((group (%make-option-group :members (mapcar #'option-key options)
                                   :required-p nil
                                   :mode :inclusive)))
    (dolist (option options)
      (setf (option-group option) group))
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

(defun make-positional (&key key name description parser type min max choices
                          completion-candidates value-hint complete
                          (default nil default-supplied-p) required-p rest-p
                          min-count max-count)
  "Create a positional argument specification.

TYPE selects a built-in value parser (:integer, :number, :float, :boolean, or
the default :string) and MIN / MAX add inclusive bounds for numeric types, just
as in MAKE-OPTION. A :type and an explicit :parser are mutually exclusive.
CHOICES restricts the value to a closed set, validated before the parser runs
(mismatches signal CLI-INVALID-POSITIONAL-VALUE) and shown in help.

MIN-COUNT / MAX-COUNT constrain how many values a rest positional (:rest-p t)
collects: too few signals CLI-MISSING-POSITIONAL, too many CLI-UNEXPECTED-ARGUMENT.
They require :rest-p and must be non-negative with MIN-COUNT <= MAX-COUNT."
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
    (validate-typed-value-spec type min max parser
                               (format nil "Positional ~S" resolved-key))
    (validate-rest-count-spec resolved-key rest-p min-count max-count)
    (normalize-value-hint value-hint (format nil "Positional ~S" resolved-key))
    (when (and complete (not (functionp complete)))
      (signal-cli-error 'cli-invalid-specification
                        (format nil "Positional ~S: :complete must be a function." resolved-key)))
    (setf (positional-spec-key spec) resolved-key
          (positional-spec-description spec) (normalize-positional-description description)
          (positional-spec-value-type spec) type
          (positional-spec-value-min spec) min
          (positional-spec-value-max spec) max
          (positional-spec-choices spec) (normalize-option-choices choices)
          (positional-spec-completion-candidates spec)
          (normalize-option-completion-candidates completion-candidates)
          (positional-spec-value-hint spec) value-hint
          (positional-spec-complete spec) complete
          (positional-spec-parser spec) (cond
                                          (type (build-typed-value-parser type min max))
                                          (parser parser)
                                          (t #'identity))
          (positional-spec-default spec) default
          (positional-spec-default-present-p spec) default-supplied-p
          (positional-spec-required-p spec) required-p
          (positional-spec-rest-p spec) rest-p
          (positional-spec-min-count spec) min-count
          (positional-spec-max-count spec) max-count)
    spec))

(defun make-command (&key name aliases group description examples options positionals subcommands default-command handler hidden-p deprecated help-footer)
  "Create a command specification.

DEPRECATED marks the command as deprecated (T, or a reason string). A deprecated
command stays visible in help and completion, is annotated as deprecated in help
and generated docs, and triggers a stderr warning when RUN-APP dispatches it.
HELP-FOOTER is trailing prose printed after the command's help, mirroring the
app-level :help-footer.

SUBCOMMANDS is a list of nested command specs (built with MAKE-COMMAND); a
command that declares them dispatches like a mini-app (`git remote add`). The
next non-option token selects a subcommand, the command's own options remain
available to the whole subtree, and the command's :handler / :positionals still
run when no subcommand token is supplied.

DEFAULT-COMMAND names one of :subcommands to dispatch when no subcommand token
is present, mirroring the app-level :default-command."
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
                        :subcommands subcommands
                        :default-command (and default-command (canonical-name default-command))
                        :handler handler
                        :hidden-p hidden-p
                        :deprecated (normalize-deprecated deprecated)
                        :help-footer (normalize-positional-description help-footer))))

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

(defun %validate-command-node (app command accumulated-specs)
  "Validate COMMAND and, recursively, its subcommands.

ACCUMULATED-SPECS is the option-spec set in scope from the app root down to (but
not including) COMMAND -- built-ins, globals, and every ancestor command's
options. COMMAND's own options extend that scope for both its own validation and
its subcommands', mirroring how a nested command inherits its ancestors'
options at parse time. The per-command relation rulebase is cached on the app
keyed by the command object."
  (%validate-positional-sequence (command-positionals command)
                                 (command-name command))
  (%validate-user-option-keys (command-options command) (command-name command))
  (let ((command-specs (append accumulated-specs (command-options command))))
    (multiple-value-bind (validated-command-specs command-rulebase)
        (validate-option-relationships-declared command-specs)
      (declare (ignore validated-command-specs))
      (setf (gethash command (app-command-relation-rulebases app))
            command-rulebase))
    (%validate-option-table command-specs)
    (%validate-option-key-uniqueness command-specs (command-name command))
    (if (command-subcommands command)
        (let ((subcommand-table (%validate-command-table (command-subcommands command))))
          (when (and (command-default-command command)
                     (null (gethash (command-default-command command) subcommand-table)))
            (signal-cli-error 'cli-invalid-specification
                              (format nil "Unknown :default-command for ~A: ~A"
                                      (command-name command)
                                      (command-default-command command))))
          (dolist (subcommand (command-subcommands command))
            (%validate-command-node app subcommand command-specs)))
        (when (command-default-command command)
          (signal-cli-error 'cli-invalid-specification
                            (format nil "Command ~A declares :default-command but has no :subcommands."
                                    (command-name command)))))))

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
    (let ((accumulated-specs (append built-ins (app-global-options app))))
      (dolist (command (app-commands app))
        (%validate-command-node app command accumulated-specs)))
    (when (and (app-default-command app)
               (null (gethash (app-default-command app) command-table)))
      (signal-cli-error 'cli-invalid-specification
                        (format nil "Unknown :default-command for ~A: ~A"
                                (app-name app)
                                (app-default-command app))))
    (when (and (app-require-command app)
               (null (app-commands app)))
      (signal-cli-error 'cli-invalid-specification
                        (format nil "~A declares :require-command but has no :commands."
                                (app-name app)))))
  app)
