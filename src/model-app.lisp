(in-package :cl-cli)

(defun make-app (&key name version summary description global-options positionals
                   commands default-command handler examples help-footer
                   allow-abbreviated-options expand-response-files
                   allow-negative-numbers require-command see-also authors
                   manual-date (auto-help t))
  "Create an application specification.

ALLOW-ABBREVIATED-OPTIONS, when true, lets a unique unambiguous prefix of a long
option stand in for the full name (`--verb` for `--verbose`). An ambiguous prefix
signals CLI-UNKNOWN-OPTION listing the matches. It defaults to NIL to preserve
strict exact-match parsing.

EXPAND-RESPONSE-FILES, when true, expands a `@path` argument into the
whitespace-separated arguments read from that file before parsing (`@@` escapes
a literal leading `@`), mirroring the response-file convention of gcc and clap.

ALLOW-NEGATIVE-NUMBERS, when true, keeps a token that looks like a negative
number (`-5`, `-1.5`) from being parsed as a short-option cluster, so it can be
taken as a positional or option value. It defaults to NIL.

REQUIRE-COMMAND, when true, makes parsing fail with CLI-UNKNOWN-COMMAND unless a
subcommand is dispatched -- expressing a \"subcommand mandatory\" contract for an
app whose root does nothing on its own. It requires :COMMANDS.

SEE-ALSO (a list of references such as \"git(1)\") and AUTHORS (a list of author
lines) are rendered as the SEE ALSO and AUTHORS sections of the generated man
page and exposed in the JSON schema.

AUTO-HELP defaults to T; pass NIL to suppress the built-in `-h` / `--help` flag
(for a CLI that manages its own help, or forwards `--help` to a wrapped tool).
A `help` command added via MAKE-STANDARD-COMMANDS is unaffected."
  (let ((resolved-name (and name (canonical-name name))))
    (when (or (null resolved-name)
              (zerop (length resolved-name)))
      (signal-cli-error 'cli-invalid-specification
                        "An app needs a non-empty name."))
    (validate-safe-identifier-names (list resolved-name) "App name")
    (%validate-app-spec
     (%make-app-spec :name resolved-name
                     :version (and version (princ-to-string version))
                     :summary (normalize-positional-description summary)
                     :description (normalize-positional-description description)
                     :global-options global-options
                     :positionals positionals
                     :commands commands
                     :default-command (and default-command (canonical-name default-command))
                     :handler handler
                     :examples (normalize-example-strings examples)
                     :help-footer (normalize-positional-description help-footer)
                     :allow-abbreviated-options allow-abbreviated-options
                     :expand-response-files expand-response-files
                     :allow-negative-numbers allow-negative-numbers
                     :require-command require-command
                     :see-also (normalize-example-strings see-also)
                     :authors (normalize-example-strings authors)
                     :manual-date (normalize-positional-description manual-date)
                     :auto-help auto-help))))

(defun command-by-name (app name)
  "Return the command in APP matching NAME or NIL."
  (declare (notinline canonical-name app-commands command-name command-aliases))
  (let ((needle (canonical-name name)))
    (block command-by-name
      (dolist (command (app-commands app))
        (when (string= needle (command-name command))
          (return-from command-by-name command))
        (dolist (alias (command-aliases command))
          (when (string= needle alias)
            (return-from command-by-name command))))
      nil)))
