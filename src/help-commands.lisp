(in-package :cl-cli)

(defun make-help-command (&key (name "help")
                              (description "Show help for the application or a command."))
  "Create a `help [COMMAND]` command spec that prints app or command help."
  (make-command
   :name name
   :description description
   :positionals (list (make-positional :key :target
                                       :description "Optional command name."
                                       :required-p nil))
   :handler (lambda (invocation)
              (let* ((app (invocation-app invocation))
                     (stream (or (invocation-stdout invocation)
                                 *standard-output*))
                     (target (positional-value invocation :target)))
                (if target
                    (let ((command (command-by-name app target)))
                      (unless command
                        (signal-cli-error 'cli-unknown-command
                                          (unknown-command-message app target)
                                          :command target))
                      (print-command-help app command stream))
                    (print-app-help app stream))))
   :hidden-p nil))

(defun make-version-command (&key (name "version")
                                  (description "Print version information."))
  "Create a `version` command spec that prints the app name and version."
  (make-command
   :name name
   :description description
   :handler (lambda (invocation)
              (let ((stream (or (invocation-stdout invocation)
                                *standard-output*)))
                (print-app-version-line (invocation-app invocation) stream)))
   :hidden-p nil))
