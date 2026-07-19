(in-package :cl-cli)

(defun help-stream (stream)
  (or stream *standard-output*))

(defun %visible-options (options)
  (remove-if #'option-hidden-p options))

(defun %sorted-visible-options (options)
  (stable-sort-copy (%visible-options options)
                    #'string<
                    :key (lambda (spec)
                           (or (first (option-names spec)) ""))))

(defun %print-options (stream app options &key (title "Options"))
  (format stream "~&~A:~%" title)
  (dolist (option (%sorted-visible-options options))
    (unless (member (option-key option) '(:help :version))
      (%print-option-row stream option options)))
  (dolist (option (built-in-option-specs app))
    (%print-option-row stream option options)))

(defun %format-usage (app &optional command)
  (with-output-to-string (out)
    (cond
      (command
       (format out "Usage: ~A ~A" (app-name app) (command-name command))
       (when (or (app-global-options app)
                 (command-options command))
         (format out " ~A" (%usage-options-token "options")))
       (dolist (positional (command-positionals command))
         (format out " ~A" (%format-positional-token positional))))
      ((app-commands app)
       (write-string (string-right-trim '(#\Newline) (%format-command-dispatch-usage app)) out))
      (t
       (write-string (string-right-trim '(#\Newline) (%format-root-usage app)) out)))
    (terpri out)))

(defun print-command-help (app command &optional (stream *standard-output*))
  "Print help for COMMAND."
  (let ((stream (help-stream stream)))
    (format stream "~A" (%format-usage app command))
    (when (command-description command)
      (format stream "~&~A~%" (command-description command)))
    (%print-options stream app
                    (append (app-global-options app)
                            (command-options command)))
    (when (command-positionals command)
      (format stream "~&Positionals:~%")
      (dolist (positional (command-positionals command))
        (%print-positional-row stream positional)))
    (%print-examples stream (command-examples command))
    (when (app-help-footer app)
      (format stream "~&~A~%" (app-help-footer app))))
  (values))

(defun print-app-help (app &optional (stream *standard-output*))
  "Print application-level help."
  (let ((stream (help-stream stream)))
    (format stream "~A" (%format-usage app))
    (when (app-summary app)
      (format stream "~&~A~%" (app-summary app)))
    (when (app-description app)
      (format stream "~&~A~%" (app-description app)))
    (%print-commands stream (app-commands app))
    (%print-options stream app (app-global-options app) :title "Global Options")
    (when (app-positionals app)
      (format stream "~&Positionals:~%")
      (dolist (positional (app-positionals app))
        (%print-positional-row stream positional)))
    (%print-examples stream (app-examples app))
    (when (app-help-footer app)
      (format stream "~&~A~%" (app-help-footer app))))
  (values))
