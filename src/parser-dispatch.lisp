(in-package :cl-cli)

(defun make-parser-invocation (app command argv0 raw-argv action
                               global-options command-options positionals
                               &optional (command-path (when command (list command))))
  (%make-invocation :app app
                    :command command
                    :command-path command-path
                    :action action
                    :argv0 argv0
                    :raw-argv raw-argv
                    :global-options global-options
                    :command-options command-options
                    :positionals positionals
                    ;; Captured from the dynamic accumulator bound in PARSE-ARGV;
                    ;; copied so a later parse cannot mutate this invocation.
                    :option-sources (copy-list *option-value-sources*)
                    :stdout nil
                    :stderr nil))

(defun app-global-stop-parsing-p (app global-values)
  (loop for spec in (app-global-options app)
        thereis (and (option-stop-parsing-p spec)
                     (plist-has-key-p global-values
                                      (option-key spec)))))

(defun merge-global-options (app parsed-global-options initial-global-values)
  (apply-option-defaults
   (merge-option-values initial-global-values
                        (app-global-options app)
                        parsed-global-options)
   (app-global-options app)))

(defun resolve-dispatch-command (app command-table remaining global-stop-parsing-p
                                 &optional literal-separator-seen-p)
  (cond
    ((and (null remaining)
          (app-default-command app))
     (values (resolve-default-command app command-table) remaining))
    ((and remaining
          (not global-stop-parsing-p)
          ;; After a literal "--", every remaining token is a positional by
          ;; POSIX/GNU convention (e.g. `git -- log`); do not treat the next one
          ;; as a command name to dispatch.
          (not literal-separator-seen-p)
          (not (command-line-option-p (first remaining))))
     (multiple-value-bind (resolved-command consume-token-p)
         (resolve-command-selection app command-table (first remaining))
       (if resolved-command
           (values resolved-command
                   (if consume-token-p
                       (rest remaining)
                       remaining))
           (values nil remaining))))
    (t
     (values nil remaining))))

(defun %command-path-option-specs (app path)
  "The option specs in scope at the leaf of PATH: globals plus each command's."
  (append (app-global-options app)
          (loop for command in path append (command-options command))))

(defun %path-command-option-specs (path)
  "The option specs contributed by the commands in PATH (excluding globals)."
  (loop for command in path append (command-options command)))

(defun %scope-stop-parsing-p (option-specs values)
  "True when a stop-parsing option in OPTION-SPECS has been set in VALUES."
  (loop for spec in option-specs
        thereis (and (option-stop-parsing-p spec)
                     (plist-has-key-p values (option-key spec)))))

(defun %unknown-subcommand-message (command token)
  (format nil "Unknown subcommand of ~A: ~A~A"
          (command-name command)
          token
          (format-suggestion-suffix
           token
           (loop for subcommand in (command-subcommands command)
                 unless (command-hidden-p subcommand)
                   append (cons (command-name subcommand)
                                (command-aliases subcommand))))))

(defun %resolve-subcommand (command subcommand-table remaining stop-parsing-p
                            literal-separator-seen-p)
  "Resolve the leading token of REMAINING as a subcommand of COMMAND.

Returns (VALUES subcommand rest) when a subcommand matches. A declared
:default-command is dispatched (keeping the token as its argument) when the token
is not a known subcommand, or when there is no subcommand token at all. Returns
(VALUES NIL REMAINING) when the token should be treated as one of COMMAND's own
positionals -- but signals CLI-UNKNOWN-COMMAND when COMMAND takes no positionals
and has no default, so a mistyped subcommand is reported rather than silently
mis-dispatched."
  (let ((default-spec
          (when (command-default-command command)
            (getf (resolve-command-spec subcommand-table
                                        (command-default-command command))
                  :command))))
    (cond
      ((and remaining
            (not stop-parsing-p)
            (not literal-separator-seen-p)
            (not (command-line-option-p (first remaining))))
       (let ((entry (resolve-command-spec subcommand-table (first remaining))))
         (cond
           (entry (values (getf entry :command) (rest remaining)))
           (default-spec (values default-spec remaining))
           ((null (command-positionals command))
            (signal-cli-error 'cli-unknown-command
                              (%unknown-subcommand-message command (first remaining))
                              :command (first remaining)))
           (t (values nil remaining)))))
      (default-spec (values default-spec remaining))
      (t (values nil remaining)))))

(defun %finalize-command-node (app path argv0 raw-argv remaining accumulated-values)
  "Terminal parse for the leaf command of PATH: its options and positionals."
  (let* ((command (first (last path)))
         (scope-specs (%command-path-option-specs app path)))
    (multiple-value-bind (combined-option-values parsed-positionals command-action)
        (parse-mixed-arguments app remaining scope-specs
                               (command-positionals command)
                               :initial-option-values accumulated-values
                               :command command)
      (let ((resolved-global-options
              (merge-global-options app combined-option-values accumulated-values))
            (resolved-command-options
              (collect-option-values (%path-command-option-specs path)
                                     combined-option-values)))
        (unless (member command-action '(:help :version))
          (validate-required-options resolved-global-options
                                     (app-global-options app)))
        (make-parser-invocation app command argv0 raw-argv command-action
                                resolved-global-options
                                resolved-command-options
                                parsed-positionals
                                path)))))

(defun dispatch-command-node (app path argv0 raw-argv remaining accumulated-values)
  "Parse the leaf command of PATH, recursing into a nested subcommand if present.

ACCUMULATED-VALUES carries the option values parsed by ancestors (starting from
the app-level global values) so counters accumulate and ancestor options stay
visible down the whole subtree."
  (let* ((command (first (last path)))
         (*cli-error-command* command))
    (if (null (command-subcommands command))
        (%finalize-command-node app path argv0 raw-argv remaining accumulated-values)
        (let ((scope-specs (%command-path-option-specs app path)))
          (multiple-value-bind (values remaining2 action literal-separator-seen-p)
              (parse-options-prefix app remaining scope-specs accumulated-values)
            (if (member action '(:help :version))
                (make-parser-invocation
                 app command argv0 raw-argv action
                 (merge-global-options app values accumulated-values)
                 (collect-option-values (%path-command-option-specs path) values)
                 nil
                 path)
                (let ((subcommand-table
                        (command-table-from-specs (command-subcommands command)))
                      (stop-parsing-p (%scope-stop-parsing-p scope-specs values)))
                  (multiple-value-bind (subcommand sub-remaining)
                      (%resolve-subcommand command subcommand-table remaining2
                                           stop-parsing-p literal-separator-seen-p)
                    (if subcommand
                        (dispatch-command-node app (append path (list subcommand))
                                               argv0 raw-argv sub-remaining values)
                        ;; No subcommand token: this command handles the rest as
                        ;; its own positionals/options, seeded with the prefix.
                        (%finalize-command-node app path argv0 raw-argv
                                                remaining2 values))))))))))

(defun parse-command-argv (app command argv0 raw-argv remaining global-values)
  (dispatch-command-node app (list command) argv0 raw-argv remaining global-values))

(defun parse-root-argv (app argv0 raw-argv remaining global-values
                        global-stop-parsing-p global-literal-separator-seen-p)
  (multiple-value-bind (parsed-global-options parsed-positionals parsed-action)
      (if (or global-stop-parsing-p
              global-literal-separator-seen-p)
          (values nil
                  (parse-literal-positionals (app-positionals app) remaining)
                  :dispatch)
          (parse-mixed-arguments app remaining
                                 (app-global-options app)
                                 (app-positionals app)
                                 :initial-option-values global-values))
    (let ((resolved-global-options
            (merge-global-options app parsed-global-options global-values)))
      (unless (member parsed-action '(:help :version))
        (validate-required-options resolved-global-options
                                   (app-global-options app)))
      (make-parser-invocation app nil argv0 raw-argv parsed-action
                              resolved-global-options
                              nil
                              parsed-positionals))))

(defun parse-argv (app argv &key (argv0 (first argv)) config)
  "Parse ARGV according to APP and return an invocation.

CONFIG is an optional plist of option-key -> value that supplies option defaults
below CLI arguments and environment variables but above literal :default (see
*OPTION-CONFIG-VALUES*), so a caller can layer in values loaded from a config
file without forking the parser."
  (let* ((*cli-error-app* app)
         (*cli-error-command* nil)
         (*option-value-sources* nil)
         (*option-config-values* config)
         (*allow-abbreviated-options* (app-allow-abbreviated-options app))
         (*allow-negative-numbers* (app-allow-negative-numbers app))
         (raw-argv (copy-list argv))
         (arguments (if (app-expand-response-files app)
                        (expand-response-files (rest argv))
                        (rest argv)))
         (command-table (command-table-from-specs (app-commands app))))
    (multiple-value-bind (global-values remaining global-action
                          literal-separator-seen-p)
        (parse-options-prefix app arguments (app-global-options app))
      (let ((global-stop-parsing-p
              (app-global-stop-parsing-p app global-values)))
        (multiple-value-bind (command command-remaining)
            (resolve-dispatch-command app command-table remaining
                                      global-stop-parsing-p
                                      literal-separator-seen-p)
          (cond
            ((member global-action '(:help :version))
             (make-parser-invocation app nil argv0 raw-argv global-action
                                     (merge-global-options app global-values nil)
                                     nil nil))
            (command
             (parse-command-argv app command argv0 raw-argv
                                 command-remaining global-values))
            (t
             (when (app-require-command app)
               (signal-cli-error 'cli-unknown-command
                                 (format nil "~A requires a command; available: ~{~A~^, ~}"
                                         (app-name app)
                                         (command-candidate-names app))
                                 :command nil))
             (parse-root-argv app argv0 raw-argv remaining global-values
                              global-stop-parsing-p
                              literal-separator-seen-p))))))))
