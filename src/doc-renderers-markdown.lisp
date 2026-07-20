(in-package :cl-cli)

;;;; A Markdown documentation renderer.
;;;;
;;;; Follows the same optional-stream convention as the completion and man-page
;;;; renderers: with no stream RENDER-MARKDOWN returns the document as a string;
;;;; with a stream it writes to it and returns no values. The output is designed
;;;; to drop straight into a README or a docs site (GitHub-flavored Markdown).

(defun %md-escape-prose (text)
  "Escape free-form prose so metadata cannot inject raw HTML or Markdown."
  (with-output-to-string (out)
    (loop for char across (%md-control-safe-string text)
          do (case char
               (#\& (write-string "&amp;" out))
               (#\< (write-string "&lt;" out))
               (#\> (write-string "&gt;" out))
               ((#\\ #\` #\* #\_ #\{ #\} #\[ #\] #\# #\+ #\!)
                (write-char #\\ out)
                (write-char char out))
               (t (write-char char out))))))

(defun %md-control-safe-string (value)
  "Return VALUE with terminal-control characters folded out of Markdown output."
  (%completion-control-safe-string value))

(defun %md-single-line (value)
  (with-output-to-string (out)
    (loop for char across (%md-control-safe-string value)
          do (write-char (if (member char '(#\Newline #\Return) :test #'char=)
                             #\Space
                             char)
                         out))))

(defun %md-max-backtick-run (strings)
  (let ((maximum 0))
    (dolist (string strings maximum)
      (let ((run 0))
        (loop for char across (%md-control-safe-string string)
              do (if (char= char #\`)
                     (setf run (1+ run)
                           maximum (max maximum run))
                     (setf run 0)))))))

(defun %md-backtick-delimiter (strings &key (minimum 1))
  (make-string (max minimum (1+ (%md-max-backtick-run strings)))
               :initial-element #\`))

(defun %md-escape-cell (text)
  "Escape TEXT for use inside a Markdown table cell.

A raw `|` would end the cell, and an embedded newline would break the row, so
escape the former and fold the latter to a space."
  (with-output-to-string (out)
    (loop for char across (%md-escape-prose text)
          do (case char
               (#\| (write-string "\\|" out))
                ((#\Newline #\Return) (write-char #\Space out))
                (t (write-char char out))))))

(defun %md-inline-code (text)
  "Wrap TEXT in a code span that cannot be closed by TEXT's backticks."
  (let* ((safe (%md-single-line text))
         (delimiter (%md-backtick-delimiter (list safe))))
    (format nil "~A~A~A" delimiter safe delimiter)))

(defun %md-synopsis (app)
  (format nil "~A~A" (%md-single-line (app-name app)) (%doc-synopsis-tail app)))

(defun %md-fenced-block (stream lines)
  (let ((fence (%md-backtick-delimiter lines :minimum 3)))
    (format stream "~A~%" fence)
    (dolist (line lines)
      (format stream "~A~%" (%md-control-safe-string line)))
    (format stream "~A~%~%" fence)))

(defun %md-title-section (app stream)
  (format stream "# ~A~%~%" (%md-escape-prose (%md-single-line (app-name app))))
  (let ((summary (%doc-app-summary app)))
    (when summary
      (format stream "> ~A~%~%" (%md-escape-cell summary))))
  (let ((version (app-version-string app)))
    (when version
      (format stream "**Version:** ~A~%~%" (%md-escape-prose version))))
  (let ((description (app-description app)))
    (when (and description
               ;; Avoid repeating the description when it already served as the
               ;; summary blockquote above.
               (not (equal description (%doc-app-summary app))))
      (format stream "~A~%~%" (%md-escape-prose description)))))

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
      (format stream "~A~%~%" (%md-escape-prose description))))
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
    (format stream "~A~%~%" (%md-escape-prose (command-help-footer command))))
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
