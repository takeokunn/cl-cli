(in-package :cl-cli)

(defun positional-value (invocation key &optional default)
  "Return the parsed positional value stored under KEY in INVOCATION.

KEY is the keyword given as `:key` in `make-positional`. Rest positionals
return a list. DEFAULT is returned when the positional was not provided."
  (getf (invocation-positionals invocation) key default))

(defun option-value (invocation key &optional default)
  "Return the parsed option value stored under KEY in INVOCATION.

KEY is the option key derived from the option name, such as `:output` for
`--output`. Command-scoped values shadow global values. Options declared with
`:multiple-p t` return a list. DEFAULT is returned when the option was not
provided and has no environment or literal default."
  (let ((value (getf (invocation-command-options invocation) key :__missing__)))
    (when (eq value :__missing__)
      (setf value (getf (invocation-global-options invocation) key :__missing__)))
    (if (eq value :__missing__)
        default
        value)))

(defun %invocation-has-option-key-p (invocation key)
  "True when INVOCATION carries any value for KEY (command scope or global)."
  (or (plist-has-key-p (invocation-command-options invocation) key)
      (plist-has-key-p (invocation-global-options invocation) key)))

(defun option-value-source (invocation key)
  "Return where INVOCATION's value for KEY came from, or NIL when KEY is unset.

The result is one of:
  :COMMAND-LINE -- the user passed it on the argv,
  :ENV          -- filled from one of the option's environment variables,
  :CONFIG       -- filled from the :CONFIG layer (see PARSE-ARGV),
  :DEFAULT      -- filled from the option's literal :DEFAULT.

This is the analogue of clap's `ArgMatches::value_source`: it lets a handler
tell an explicit user choice apart from a fallback, so \"only override when the
user actually set it\" and layered-config merges become expressible. Command
scope shadows global scope, matching OPTION-VALUE."
  (let ((sources (invocation-option-sources invocation)))
    (if (plist-has-key-p sources key)
        (getf sources key)
        (when (%invocation-has-option-key-p invocation key)
          :command-line))))

(defun cli-command-handler (invocation)
  (let ((command (invocation-command invocation)))
    (if command
        (command-handler command)
        (app-handler (invocation-app invocation)))))

(defun current-process-argv ()
  "Return the current process argv in a portable shape.

On SBCL this returns `sb-ext:*posix-argv*`; on other implementations it falls
back to `uiop:command-line-arguments`."
  #+sbcl (copy-list sb-ext:*posix-argv*)
  #-sbcl (copy-list (uiop:command-line-arguments)))

(defun default-runtime-markers ()
  "Return known launcher markers used before application argv.

These markers describe upstream launchers such as SBCL or Nix and therefore
must not depend on the Lisp implementation currently running this library."
  (list "--no-userinit" "--end-toplevel-options"))

(defun %last-matching-index (items candidates)
  (loop with best = nil
        for candidate in candidates
        for index = (position candidate items :test #'string= :from-end t)
        when index
          do (setf best (if best (max best index) index))
        finally (return best)))

(defun %drop-through-last-marker (argv runtime-markers)
  (let ((marker-index (%last-matching-index argv runtime-markers)))
    (if marker-index
        (nthcdr (1+ marker-index) argv)
        argv)))

(defun extract-application-argv (&key (argv (current-process-argv))
                                   runtime-markers
                                   separator)
  "Extract application argv from launcher/runtime ARGV.

If SEPARATOR is present in ARGV, everything after its first occurrence is the
application argv, full stop -- RUNTIME-MARKERS is not applied to it. A literal
application argument that happens to match a runtime marker (e.g. an app that
itself accepts \"--end-toplevel-options\") must never be reinterpreted as a
launcher token just because some earlier, unrelated launcher also uses that
marker. Only when SEPARATOR is absent (or not given) does RUNTIME-MARKERS
apply, dropping everything through the last matching marker."
  (let* ((remaining (copy-list argv))
         (tail (and separator (member separator remaining :test #'string=))))
    (cond
      (tail (rest tail))
      (runtime-markers (%drop-through-last-marker remaining runtime-markers))
      (t remaining))))

(defun application-argv (&key (argv (current-process-argv))
                           (runtime-markers (default-runtime-markers))
                           separator)
  "Return application argv with common launcher wrappers removed.

This is a convenience wrapper over `extract-application-argv` that applies the
library's default runtime markers. Pass SEPARATOR, usually `\"--\"`, when the
real application argv starts after a launcher separator."
  (extract-application-argv :argv argv
                            :runtime-markers runtime-markers
                            :separator separator))

(defun strip-argv-separators (argv &key (separator "--"))
  "Return ARGV without separator sentinel tokens.

This is useful after parsing an option with `:stop-parsing-p t` when a
downstream consumer should receive only opaque script arguments, not the
literal separator token used to terminate CLI option parsing."
  (loop for token in argv
        unless (string= token separator)
          collect token))

(defun %warn-deprecated-command (command stream)
  "Print a stderr deprecation warning for a dispatched deprecated COMMAND."
  (format stream "~&warning: command '~A' is ~A~%"
          (command-name command)
          (or (%deprecation-note (command-deprecated command)) "deprecated")))

(defun print-app-version-line (app stream)
  (let ((version (app-version-string app)))
    (if version
        (format stream "~A ~A~%" (app-name app) version)
        (format stream "~A~%" (app-name app)))))

(defun run-app (app &key argv (argv0 (first argv)) (stdout *standard-output*)
                  (stderr *error-output*) config color width
                  (usage-exit-code 64) (error-exit-code 70))
  "Parse ARGV, dispatch the selected handler, and return an exit code.

CONFIG is forwarded to PARSE-ARGV as the option-default config layer (see
PARSE-ARGV / *OPTION-CONFIG-VALUES*). COLOR and WIDTH govern help printed by
RUN-APP (for --help and for usage errors) and each accepts :AUTO in addition to
explicit values: COLOR :AUTO honors NO_COLOR / CLICOLOR_FORCE / whether the
target stream is a terminal, and WIDTH :AUTO reads $COLUMNS. They default to NIL
(no styling, no wrapping) so behavior is unchanged unless a caller opts in.

A successful run returns 0 (or the integer a handler returns). USAGE-EXIT-CODE
is returned for a CLI-USAGE-ERROR and ERROR-EXIT-CODE for any other unhandled
error; they default to the BSD sysexits values EX_USAGE (64) and EX_SOFTWARE
(70) but a caller can override either to match a different exit-code policy."
  (handler-case
      (let ((invocation (parse-argv app argv :argv0 argv0 :config config)))
        (setf (invocation-stdout invocation) stdout
              (invocation-stderr invocation) stderr)
        (ecase (invocation-action invocation)
          (:help
           (if (invocation-command invocation)
               (print-command-help app (invocation-command invocation) stdout
                                   (invocation-command-path invocation) :color color :width width)
               (print-app-help app stdout :color color :width width)))
          (:version (print-app-version-line app stdout))
          (:dispatch
           (dolist (command (invocation-command-path invocation))
             (when (command-deprecated command)
               (%warn-deprecated-command command stderr)))
           (let ((handler (cli-command-handler invocation)))
             (if handler
                 (let ((result (funcall handler invocation)))
                   (when (integerp result)
                     (return-from run-app result)))
                 ;; No handler: a command node (e.g. a pure subcommand group with
                 ;; no default action) shows its own help listing subcommands;
                 ;; the app root falls back to app help.
                 (if (invocation-command invocation)
                     (print-command-help app (invocation-command invocation) stdout
                                         (invocation-command-path invocation) :color color :width width)
                     (print-app-help app stdout :color color :width width))))))
        0)
    (cli-usage-error (condition)
      (format stderr "~&~A~%" condition)
      (cond
        ((and (cli-usage-error-app condition)
              (cli-usage-error-command condition))
         (format stderr "~&")
         (print-command-help (cli-usage-error-app condition)
                             (cli-usage-error-command condition)
                             stderr
                             (list (cli-usage-error-command condition))
                             :color color :width width))
        ((or (cli-usage-error-app condition) app)
        (format stderr "~&")
         (print-app-help (or (cli-usage-error-app condition) app) stderr
                         :color color :width width)))
      usage-exit-code)
    (error (condition)
      (format stderr "~&Internal error: ~A~%" condition)
      error-exit-code)))
