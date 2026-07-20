(in-package :cl-cli)

(defun help-stream (stream)
  (or stream *standard-output*))

(defun %parse-help-render-options (args)
  (destructuring-bind (&key color width) args
    (values color width)))

(defun %parse-app-help-args (args)
  (if (and args (keywordp (first args)))
      (multiple-value-bind (color width) (%parse-help-render-options args)
        (values *standard-output* color width))
      (multiple-value-bind (color width) (%parse-help-render-options (rest args))
        (values (if args (first args) *standard-output*) color width))))

(defun %parse-command-help-args (command args)
  (let ((stream *standard-output*)
        (command-path (when command (list command)))
        (rest-args args))
    (unless (or (null rest-args)
                (keywordp (first rest-args)))
      (setf stream (pop rest-args)))
    (unless (or (null rest-args)
                (keywordp (first rest-args)))
      (setf command-path (pop rest-args)))
    (multiple-value-bind (color width) (%parse-help-render-options rest-args)
      (values stream command-path color width))))

(defun %visible-options (options)
  (remove-if #'option-hidden-p options))

(defun %sorted-visible-options (options)
  (stable-sort-copy (%visible-options options)
                    #'string<
                    :key (lambda (spec)
                           (or (first (option-names spec)) ""))))

(defun %option-group-sections (options)
  "Group OPTIONS that declare a :group into (group-label . options) sections.

Groups appear in first-seen order; options without a :group are excluded (they
belong under the main options heading)."
  (let ((order nil)
        (table (make-hash-table :test #'equal)))
    (dolist (option options)
      (let ((group (option-help-group option)))
        (when group
          (unless (nth-value 1 (gethash group table))
            (setf (gethash group table) nil)
            (push group order))
          (push option (gethash group table)))))
    (mapcar (lambda (group) (cons group (nreverse (gethash group table))))
            (nreverse order))))

(defun %print-options (stream app options &key (title "Options"))
  (let* ((visible (%sorted-visible-options options))
         (target-table (%option-target-table options))
         (user-options (remove-if (lambda (option)
                                    (member (option-key option) '(:help :version)))
                                  visible)))
    ;; Main heading: options without a :group, followed by the built-ins.
    (format stream "~&~A~%" (%style-heading (format nil "~A:" title)))
    (dolist (option (remove-if #'option-help-group user-options))
      (%print-option-row stream option options target-table))
    (dolist (option (built-in-option-specs app))
      (%print-option-row stream option options target-table))
    ;; One heading per declared option group.
    (dolist (section (%option-group-sections user-options))
      (format stream "~&~A~%" (%style-heading (format nil "~A:" (car section))))
      (dolist (option (cdr section))
        (%print-option-row stream option options target-table)))))

(defun %format-usage (app &optional command command-path)
  (with-output-to-string (out)
    (cond
      (command
       (let ((path (or command-path (list command))))
         (format out "Usage: ~A~{ ~A~}"
                 (%terminal-safe-text (app-name app))
                 (mapcar #'%terminal-safe-text (mapcar #'command-name path))))
       (when (or (app-global-options app)
                 (command-options command))
         (format out " ~A" (%usage-options-token "options")))
       (write-string (%required-options-synopsis
                      (append (app-global-options app)
                              (command-options command)))
                     out)
       (if (command-subcommands command)
           (format out " <command> [args]")
           (dolist (positional (command-positionals command))
             (format out " ~A" (%format-positional-token positional)))))
      ((app-commands app)
       (write-string (string-right-trim '(#\Newline) (%format-command-dispatch-usage app)) out))
      (t
       (write-string (string-right-trim '(#\Newline) (%format-root-usage app)) out)))
    (terpri out)))

(defun print-command-help (app command &rest args)
  "Print help for COMMAND.

COMMAND-PATH is the chain of commands from the app root to COMMAND (defaulting to
COMMAND alone); it is used to render an accurate `app parent child` usage line
for a nested subcommand. COLOR may be T, NIL, or :AUTO (honor NO_COLOR /
CLICOLOR_FORCE / whether STREAM is a terminal); WIDTH may be a positive integer,
NIL, or :AUTO (read $COLUMNS) to word-wrap descriptions."
  (multiple-value-bind (stream command-path color width)
      (%parse-command-help-args command args)
    (let* ((stream (help-stream stream))
           (*help-color* (%resolve-help-color color stream))
           (*help-width* (%resolve-help-width width stream))
           (description (%terminal-safe-text (%command-description-string command)))
          ;; A command's own :help-footer takes precedence; fall back to the app
          ;; footer so a command without one still shows shared trailing prose.
          (footer (or (command-help-footer command)
                      (app-help-footer app))))
      (format stream "~A" (%format-usage app command command-path))
      (when (plusp (length description))
        (format stream "~&~A~%" description))
      (when (command-subcommands command)
        (%print-commands stream (command-subcommands command)))
      (%print-options stream app
                      (append (app-global-options app)
                              (command-options command)))
      (when (command-positionals command)
        (format stream "~&~A~%" (%style-heading "Positionals:"))
        (dolist (positional (command-positionals command))
          (%print-positional-row stream positional)))
      (%print-examples stream (command-examples command))
      (when footer
        (format stream "~&~A~%" (%terminal-safe-text footer)))))
  (values))

(defun print-app-help (app &rest args)
  "Print application-level help.

COLOR may be T, NIL, or :AUTO (honor NO_COLOR / CLICOLOR_FORCE / whether STREAM
is a terminal); WIDTH may be a positive integer, NIL, or :AUTO (read $COLUMNS)
to word-wrap descriptions."
  (multiple-value-bind (stream color width) (%parse-app-help-args args)
    (let* ((stream (help-stream stream))
           (*help-color* (%resolve-help-color color stream))
           (*help-width* (%resolve-help-width width stream)))
      (format stream "~A" (%format-usage app))
      (when (app-summary app)
        (format stream "~&~A~%" (%terminal-safe-text (app-summary app))))
      (when (app-description app)
        (format stream "~&~A~%" (%terminal-safe-text (app-description app))))
      (%print-commands stream (app-commands app))
      (%print-options stream app (app-global-options app) :title "Global Options")
      (when (app-positionals app)
        (format stream "~&~A~%" (%style-heading "Positionals:"))
        (dolist (positional (app-positionals app))
          (%print-positional-row stream positional)))
      (%print-examples stream (app-examples app))
      (when (app-help-footer app)
        (format stream "~&~A~%" (%terminal-safe-text (app-help-footer app))))))
  (values))
