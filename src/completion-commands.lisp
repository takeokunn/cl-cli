(in-package :cl-cli)

(defun %parse-supported-shell (value)
  (let ((shell (canonical-name value)))
    (cond
      ((member shell '("bash" "zsh" "fish" "powershell" "nushell" "elvish")
               :test #'string=)
       shell)
      ;; `pwsh` is the executable name for PowerShell Core; accept it as an
      ;; alias so `completion pwsh` works the way a PowerShell user expects.
      ((string= shell "pwsh") "powershell")
      ;; `nu` is the Nushell executable name; accept it as an alias too.
      ((string= shell "nu") "nushell")
      (t
       (signal-cli-error 'cli-invalid-positional-value
                         (format nil "Unsupported completion shell: ~A" value)
                         :name :shell
                         :value value
                         :cause "Supported shells are bash, zsh, fish, powershell, nushell, and elvish.")))))

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
      ((string= resolved-shell "powershell")
       (render-powershell-completion app stream))
      ((string= resolved-shell "nushell")
       (render-nushell-completion app stream))
      ((string= resolved-shell "elvish")
       (render-elvish-completion app stream))
      (t
       (signal-cli-error 'cli-invalid-positional-value
                         (format nil "Unsupported completion shell: ~A" shell)
                         :name :shell
                         :value shell)))))

(defun make-completion-command (&key (name "completion")
                                     (description "Print shell completion script."))
  "Create a `completion [SHELL]` command spec that prints a completion script.

SHELL defaults to bash; bash, zsh, fish, powershell, nushell, and elvish are supported."
  (make-command
   :name name
   :description description
   :positionals (list (make-positional :key :shell
                                       :description "Target shell (bash, zsh, fish, powershell, nushell, elvish)."
                                       :default "bash"
                                       :parser #'%parse-supported-shell
                                       ;; Candidates (not :choices) so shell
                                       ;; completion suggests these names while
                                       ;; the parser still accepts aliases such
                                       ;; as pwsh / nu.
                                       :completion-candidates
                                       '("bash" "zsh" "fish" "powershell" "nushell" "elvish")
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
                                    (include-docs-p nil)
                                    (include-dynamic-p nil)
                                    (help-name "help")
                                    (help-description "Show help for the application or a command.")
                                    (version-name "version")
                                    (version-description "Print version information.")
                                    (completion-name "completion")
                                    (completion-description "Print shell completion script.")
                                    (docs-name "docs")
                                    (docs-description "Print generated reference documentation."))
  "Create a standard built-in command set.

Returns a list of command specs suitable for APP :COMMANDS. By default this
includes help and version commands. Set INCLUDE-COMPLETION-P to include a
completion command, and INCLUDE-DOCS-P to include a `docs [FORMAT]` command that
prints a generated man page or Markdown reference."
  (remove nil
          (list (when include-help-p
                  (make-help-command :name help-name
                                     :description help-description))
                (when include-version-p
                  (make-version-command :name version-name
                                        :description version-description))
                (when include-completion-p
                  (make-completion-command :name completion-name
                                           :description completion-description))
                (when include-docs-p
                  (make-docs-command :name docs-name
                                     :description docs-description))
                (when include-dynamic-p
                  (make-complete-command)))))
