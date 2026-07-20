(in-package :cl-cli)

;;;; A section-1 man page renderer (roff / man macros).
;;;;
;;;; Follows the same optional-stream convention as the completion renderers:
;;;; with no stream RENDER-MANPAGE returns the page as a string; with a stream
;;;; it writes to it and returns no values.

(defun %roff-escape (text)
  "Escape TEXT for inline use in a roff document.

A literal backslash becomes `\\e`, and a literal hyphen becomes `\\-` so groff
renders it as a hyphen-minus rather than treating it specially -- the standard
convention used by help2man and friends, and essential for option tokens such
as `--output`."
  (with-output-to-string (out)
    (loop for char across (or text "")
          do (case char
               (#\\ (write-string "\\e" out))
               (#\- (write-string "\\-" out))
               (t (write-char char out))))))

(defun %roff-text-line (stream text)
  "Write TEXT as a body line, guarding a leading control character.

A line that begins with `.` or `'` would be read as a roff request; prefixing
`\\&` (a zero-width character) keeps author text such as a description that
starts with a period from being interpreted as markup."
  (let ((escaped (%roff-escape text)))
    (if (and (plusp (length escaped))
             (member (char escaped 0) '(#\. #\')))
        (format stream "\\&~A~%" escaped)
        (format stream "~A~%" escaped))))

(defun %manpage-title (app)
  (let ((version (app-version-string app)))
    (if version
        (format nil "~A ~A" (app-name app) version)
        (app-name app))))

(defun %manpage-header (app stream)
  (format stream ".TH ~S ~S ~S ~S ~S~%"
          (string-upcase (app-name app))
          "1"
          (or (app-manual-date app) "")
          (%manpage-title app)
          "User Commands"))

(defun %manpage-name-section (app stream)
  (format stream ".SH NAME~%")
  (let ((summary (%doc-app-summary app)))
    (if summary
        (format stream "~A \\- ~A~%"
                (%roff-escape (app-name app))
                (%roff-escape summary))
        (format stream "~A~%" (%roff-escape (app-name app))))))

(defun %manpage-synopsis-section (app stream)
  (format stream ".SH SYNOPSIS~%")
  (format stream ".B ~A~%" (%roff-escape (app-name app)))
  (let ((tail (%doc-synopsis-tail app)))
    (when (plusp (length tail))
      (%roff-text-line stream (string-left-trim " " tail)))))

(defun %manpage-description-section (app stream)
  (let ((description (app-description app))
        (footer (app-help-footer app)))
    (when (or description footer)
      (format stream ".SH DESCRIPTION~%")
      (when description
        (%roff-text-line stream description))
      (when footer
        (when description
          (format stream ".PP~%"))
        (%roff-text-line stream footer)))))

(defun %manpage-option-entry (option options stream)
  (format stream ".TP~%")
  (format stream ".B ~A~%" (%roff-escape (%doc-option-synopsis option)))
  (let ((description (%option-description-string option options)))
    (%roff-text-line stream (if (plusp (length description))
                                description
                                "(no description)"))))

(defun %manpage-positional-entry (positional stream)
  (format stream ".TP~%")
  (format stream ".B ~A~%" (%roff-escape (%format-positional-token positional)))
  (let ((description (%positional-description-string positional)))
    (%roff-text-line stream (if (plusp (length description))
                                description
                                "(no description)"))))

(defun %manpage-options-section (app stream)
  (let ((options (%doc-visible-options (app-global-options app))))
    (when options
      (format stream ".SH OPTIONS~%")
      (dolist (option options)
        (%manpage-option-entry option options stream)))))

(defun %manpage-arguments-section (app stream)
  (when (app-positionals app)
    (format stream ".SH ARGUMENTS~%")
    (dolist (positional (app-positionals app))
      (%manpage-positional-entry positional stream))))

(defun %manpage-command-entry (app command name-prefix stream)
  "Render a COMMANDS entry for COMMAND, qualified by its NAME-PREFIX path.

Recurses into visible subcommands with an extended prefix so `remote add`
appears as its own path-qualified entry."
  (format stream ".TP~%")
  (format stream ".B ~A~%"
          (%roff-escape (format nil "~@[~A ~]~A"
                                name-prefix
                                (%command-display-name command))))
  (let ((description (%command-description-string command)))
    (%roff-text-line stream (if (plusp (length description))
                                description
                                "(no description)")))
  (let ((options (%doc-visible-options (command-options command)))
        (positionals (command-positionals command)))
    (when (or options positionals)
      (format stream ".RS~%")
      (dolist (positional positionals)
        (%manpage-positional-entry positional stream))
      (dolist (option options)
        (%manpage-option-entry option options stream))
      (format stream ".RE~%")))
  (when (command-help-footer command)
    (format stream ".PP~%")
    (%roff-text-line stream (command-help-footer command)))
  (let ((child-prefix (format nil "~@[~A ~]~A" name-prefix (command-name command))))
    (dolist (subcommand (%visible-commands (command-subcommands command)))
      (%manpage-command-entry app subcommand child-prefix stream))))

(defun %manpage-commands-section (app stream)
  (let ((commands (%visible-commands (app-commands app))))
    (when commands
      (format stream ".SH COMMANDS~%")
      (dolist (command commands)
        (%manpage-command-entry app command nil stream)))))

(defun %manpage-examples-section (app stream)
  (let ((examples (app-examples app)))
    (when examples
      (format stream ".SH EXAMPLES~%")
      (format stream ".nf~%")
      (dolist (example examples)
        (%roff-text-line stream example))
      (format stream ".fi~%"))))

(defun %manpage-env-backed-options (app)
  "Every visible option (global or on any command, nested included) with env vars."
  (labels ((walk (commands)
             (loop for command in commands
                   append (append (command-options command)
                                  (walk (command-subcommands command))))))
    (remove-if-not #'option-env-vars
                   (remove-if #'option-hidden-p
                              (append (app-global-options app)
                                      (walk (app-commands app)))))))

(defun %manpage-environment-section (app stream)
  (let ((options (%manpage-env-backed-options app)))
    (when options
      (format stream ".SH ENVIRONMENT~%")
      (dolist (option options)
        (dolist (env-var (option-env-vars option))
          (format stream ".TP~%")
          (format stream ".B ~A~%" (%roff-escape env-var))
          (%roff-text-line stream
                           (format nil "Default for ~A.~@[ ~A~]"
                                   (%doc-option-synopsis option)
                                   (option-description option))))))))

(defun %manpage-exit-status-section (app stream)
  (declare (ignore app))
  (format stream ".SH EXIT STATUS~%")
  (format stream ".TP~%.B 0~%")
  (%roff-text-line stream "Success.")
  (format stream ".TP~%.B 64~%")
  (%roff-text-line stream "Usage error (bad arguments); help is printed to stderr.")
  (format stream ".TP~%.B 70~%")
  (%roff-text-line stream "Internal error (an unhandled condition in a handler).")
  (format stream ".PP~%")
  (%roff-text-line stream "A command handler may return its own integer exit code."))

(defun %manpage-authors-section (app stream)
  (let ((authors (app-authors app)))
    (when authors
      (format stream ".SH AUTHORS~%")
      ;; A line break between authors, but not a trailing one -- a `.br` at the
      ;; end of a section makes mandoc warn about a skipped paragraph macro.
      (loop for (author . rest) on authors
            do (%roff-text-line stream author)
               (when rest
                 (format stream ".br~%"))))))

(defun %manpage-see-also-section (app stream)
  (let ((references (app-see-also app)))
    (when references
      (format stream ".SH SEE ALSO~%")
      (%roff-text-line stream (format nil "~{~A~^, ~}" references)))))

(defun render-manpage (app &optional stream)
  "Render a section-1 man page for APP in roff/man-macro form.

With no STREAM, return the man page as a string. With a STREAM, write the page
to it and return no values. The generated page draws NAME, SYNOPSIS,
DESCRIPTION, OPTIONS, ARGUMENTS, COMMANDS, and EXAMPLES from the same spec the
interactive help printer uses, and honors hidden options and commands."
  (unless stream
    (return-from render-manpage
      (with-output-to-string (string-stream)
        (render-manpage app string-stream))))
  (%manpage-header app stream)
  (%manpage-name-section app stream)
  (%manpage-synopsis-section app stream)
  (%manpage-description-section app stream)
  (%manpage-options-section app stream)
  (%manpage-arguments-section app stream)
  (%manpage-commands-section app stream)
  (%manpage-exit-status-section app stream)
  (%manpage-environment-section app stream)
  (%manpage-examples-section app stream)
  (%manpage-see-also-section app stream)
  (%manpage-authors-section app stream)
  (values))
