(in-package :cl-cli)

;;;; A Markdown documentation renderer.
;;;;
;;;; Follows the same optional-stream convention as the completion and man-page
;;;; renderers: with no stream RENDER-MARKDOWN returns the document as a string;
;;;; with a stream it writes to it and returns no values. The output is designed
;;;; to drop straight into a README or a docs site (GitHub-flavored Markdown).

(defun %md-escape-cell (text)
  "Escape TEXT for use inside a Markdown table cell.

A raw `|` would end the cell, and an embedded newline would break the row, so
escape the former and fold the latter to a space."
  (with-output-to-string (out)
    (loop for char across (or text "")
          do (case char
               (#\| (write-string "\\|" out))
               ((#\Newline #\Return) (write-char #\Space out))
               (t (write-char char out))))))

(defun %md-inline-code (text)
  "Wrap TEXT in a backtick code span."
  (format nil "`~A`" text))

(defun %md-synopsis (app)
  (format nil "~A~A" (app-name app) (%doc-synopsis-tail app)))

(defun %md-fenced-block (stream lines)
  (format stream "```~%")
  (dolist (line lines)
    (format stream "~A~%" line))
  (format stream "```~%~%"))

(defun %md-title-section (app stream)
  (format stream "# ~A~%~%" (app-name app))
  (let ((summary (%doc-app-summary app)))
    (when summary
      (format stream "> ~A~%~%" (%md-escape-cell summary))))
  (let ((version (app-version-string app)))
    (when version
      (format stream "**Version:** ~A~%~%" version)))
  (let ((description (app-description app)))
    (when (and description
               ;; Avoid repeating the description when it already served as the
               ;; summary blockquote above.
               (not (equal description (%doc-app-summary app))))
      (format stream "~A~%~%" description))))

(defun %md-usage-section (app stream)
  (format stream "## Usage~%~%")
  (%md-fenced-block stream (list (%md-synopsis app))))

(defun %md-option-table (row-options resolution-options stream)
  (when row-options
    (format stream "| Option | Description |~%")
    (format stream "| --- | --- |~%")
    (dolist (option row-options)
      (format stream "| ~A | ~A |~%"
              (%md-inline-code (%doc-option-synopsis option))
              (%md-escape-cell (%option-description-string option resolution-options))))
    (format stream "~%")))

(defun %md-positional-table (positionals stream)
  (when positionals
    (format stream "| Argument | Description |~%")
    (format stream "| --- | --- |~%")
    (dolist (positional positionals)
      (format stream "| ~A | ~A |~%"
              (%md-inline-code (%format-positional-token positional))
              (%md-escape-cell (%positional-description-string positional))))
    (format stream "~%")))

(defun %md-options-section (app stream)
  (let ((options (%doc-visible-options (app-global-options app))))
    (when options
      (format stream "## Options~%~%")
      (%md-option-table options (app-global-options app) stream))))

(defun %md-arguments-section (app stream)
  (when (app-positionals app)
    (format stream "## Arguments~%~%")
    (%md-positional-table (app-positionals app) stream)))

(defun %md-command-section (app command full-name stream)
  "Render COMMAND's section under the heading FULL-NAME (its path from the app).

Recurses into visible subcommands, extending FULL-NAME so a nested command reads
as `parent child`."
  (format stream "### ~A~%~%" (%md-inline-code full-name))
  (let ((description (%command-description-string command)))
    (when (plusp (length description))
      (format stream "~A~%~%" description)))
  (%md-fenced-block stream
                    (list (format nil "~A ~A~A"
                                  (app-name app)
                                  full-name
                                  (%doc-command-synopsis-tail command))))
  (%md-positional-table (command-positionals command) stream)
  (%md-option-table (%doc-visible-options (command-options command))
                    (append (app-global-options app) (command-options command))
                    stream)
  (let ((examples (command-examples command)))
    (when examples
      (format stream "Examples:~%~%")
      (%md-fenced-block stream examples)))
  (when (command-help-footer command)
    (format stream "~A~%~%" (command-help-footer command)))
  (dolist (subcommand (%visible-commands (command-subcommands command)))
    (%md-command-section app subcommand
                         (format nil "~A ~A" full-name (command-name subcommand))
                         stream)))

(defun %md-commands-section (app stream)
  (let ((commands (%visible-commands (app-commands app))))
    (when commands
      (format stream "## Commands~%~%")
      (dolist (command commands)
        (%md-command-section app command (command-name command) stream)))))

(defun %md-examples-section (app stream)
  (let ((examples (app-examples app)))
    (when examples
      (format stream "## Examples~%~%")
      (%md-fenced-block stream examples))))

(defun render-markdown (app &optional stream)
  "Render Markdown reference documentation for APP.

With no STREAM, return the document as a string. With a STREAM, write to it and
return no values. Output is GitHub-flavored Markdown with a title, usage block,
option/argument tables, per-command sections, and examples, all drawn from the
same spec as `--help`. Hidden options and commands are omitted."
  (unless stream
    (return-from render-markdown
      (with-output-to-string (string-stream)
        (render-markdown app string-stream))))
  (%md-title-section app stream)
  (%md-usage-section app stream)
  (%md-options-section app stream)
  (%md-arguments-section app stream)
  (%md-commands-section app stream)
  (%md-examples-section app stream)
  (values))
