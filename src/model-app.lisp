(in-package :cl-cli)

(defun make-app (&key name version summary description global-options positionals
                   commands default-command handler examples help-footer)
  "Create an application specification."
  (let ((resolved-name (and name (canonical-name name))))
    (when (or (null resolved-name)
              (zerop (length resolved-name)))
      (signal-cli-error 'cli-invalid-specification
                        "An app needs a non-empty name."))
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
                     :help-footer (normalize-positional-description help-footer)))))

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
