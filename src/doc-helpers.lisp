(in-package :cl-cli)

;;;; Shared helpers for the offline documentation renderers (man page, Markdown).
;;;;
;;;; These renderers reuse the same spec accessors and metadata helpers the
;;;; interactive help printer uses, so generated docs stay aligned with `--help`
;;;; without a second source of truth.

(defun %doc-visible-options (options)
  "Public (non-hidden) options in declaration order."
  (remove-if #'option-hidden-p options))

(defun %doc-app-summary (app)
  "Best one-line summary for APP: its :summary, else the first :description line."
  (or (app-summary app)
      (let ((description (app-description app)))
        (when description
          (let ((newline (position #\Newline description)))
            (if newline (subseq description 0 newline) description))))))

(defun %doc-synopsis-tail (app)
  "The argument portion of APP's synopsis, after the program name.

Mirrors the shape the interactive usage lines choose: a dispatch CLI shows
`<command> [args]`, a flat CLI shows its positionals or a generic `[args]`."
  (with-output-to-string (out)
    (when (app-global-options app)
      (write-string " [global-options]" out))
    (cond
      ((app-commands app)
       (write-string " <command> [args]" out))
      ((app-positionals app)
       (dolist (positional (app-positionals app))
         (format out " ~A" (%format-positional-token positional))))
      ((app-handler app)
       (write-string " [args]" out)))))

(defun %doc-option-synopsis (option)
  "A compact `-o, --output <VALUE>` display string for OPTION."
  (%option-display-string option))

(defun %doc-command-synopsis-tail (command)
  "The argument portion of COMMAND's synopsis, after the command name."
  (with-output-to-string (out)
    (when (or (%doc-visible-options (command-options command)))
      (write-string " [options]" out))
    (if (command-subcommands command)
        (write-string " <command> [args]" out)
        (dolist (positional (command-positionals command))
          (format out " ~A" (%format-positional-token positional))))))
