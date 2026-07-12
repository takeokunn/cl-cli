(in-package :cl-cli)

(defun %parse-supported-shell (value)
  (let ((shell (canonical-name value)))
    (if (member shell '("bash" "zsh" "fish") :test #'string=)
        shell
        (signal-cli-error 'cli-invalid-positional-value
                          (format nil "Unsupported completion shell: ~A" value)
                          :name :shell
                          :value value
                          :cause "Supported shells are bash, zsh, and fish."))))

(defun render-completion (app shell &optional stream)
  "Render a completion script for SHELL."
  (let ((resolved-shell (%parse-supported-shell shell)))
    (cond
      ((string= resolved-shell "bash")
       (render-bash-completion app stream))
      ((string= resolved-shell "zsh")
       (render-zsh-completion app stream))
      ((string= resolved-shell "fish")
       (render-fish-completion app stream))
      (t
       (signal-cli-error 'cli-invalid-positional-value
                         (format nil "Unsupported completion shell: ~A" shell)
                         :name :shell
                         :value shell)))))

(defun make-completion-command (&key (name "completion")
                                     (description "Print shell completion script."))
  "Create a `completion [SHELL]` command spec that prints a completion script.

SHELL defaults to bash; bash, zsh, and fish are supported."
  (make-command
   :name name
   :description description
   :positionals (list (make-positional :key :shell
                                       :description "Target shell (bash, zsh, fish)."
                                       :default "bash"
                                       :parser #'%parse-supported-shell
                                       :required-p nil))
   :handler (lambda (invocation)
              (let ((shell (positional-value invocation :shell)))
                (render-completion
                 (invocation-app invocation)
                 shell
                 (or (invocation-stdout invocation)
                     *standard-output*))))
   :hidden-p nil))

(defun make-standard-commands (&key (include-help-p t)
                                    (include-version-p t)
                                    (include-completion-p nil)
                                    (help-name "help")
                                    (help-description "Show help for the application or a command.")
                                    (version-name "version")
                                    (version-description "Print version information.")
                                    (completion-name "completion")
                                    (completion-description "Print shell completion script."))
  "Create a standard built-in command set.

Returns a list of command specs suitable for APP :COMMANDS. By default this
includes help and version commands. Set INCLUDE-COMPLETION-P to include a
completion command as well."
  (remove nil
          (list (when include-help-p
                  (make-help-command :name help-name
                                     :description help-description))
                (when include-version-p
                  (make-version-command :name version-name
                                        :description version-description))
                (when include-completion-p
                  (make-completion-command :name completion-name
                                           :description completion-description)))))
