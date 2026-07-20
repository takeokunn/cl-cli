(in-package :cl-cli)

(defun %completion-zsh-command-labels (command)
  (format nil "~{~A~^|~}"
          (%completion-command-names command)))

(defun %completion-zsh-write-case-section (stream word body)
  (when (plusp (length body))
    (format stream "    case \"$~A\" in~%" word)
    (write-string body stream)
    (format stream "    esac~%")))

(defun %completion-zsh-render-value-cases (options stream)
  (dolist (section (list (list "previous_word"
                               (%completion-zsh-value-case-body options))
                         (list "current_word"
                               (%completion-zsh-attached-value-case-body options))))
    (%completion-zsh-write-case-section stream (first section) (second section))))

(defun %completion-zsh-subcommand-specs-source (subcommands)
  "Assign the NAME:description specs of SUBCOMMANDS to `subcommand_specs`."
  (%completion-zsh-assignment-source
   "subcommand_specs"
   (let (specs)
     (dolist (command subcommands (nreverse specs))
       (push (format nil "~A:~A"
                     (%completion-zsh-describe-field (command-name command))
                     (%completion-zsh-describe-field (command-description command)))
             specs)
       (dolist (alias (command-aliases command))
         (push (format nil "~A:alias for ~A"
                       (%completion-zsh-describe-field alias)
                       (%completion-zsh-describe-field (command-name command)))
               specs))))))

(defun %completion-zsh-command-node (app command scope-options depth)
  "Render the `NAME) ... ;;' case clause for COMMAND at word index DEPTH.

SCOPE-OPTIONS accumulates globals plus every ancestor command's options; a
command with subcommands dispatches the next word to them and offers their names
when the cursor is at DEPTH+1. `command_option_specs` is rebuilt per clause,
which is safe because only the single matched command chain executes."
  (with-output-to-string (out)
    (let* ((options (append scope-options (command-options command)))
           (subcommands (remove-if #'command-hidden-p (command-subcommands command)))
           (child-depth (1+ depth)))
      (format out "    ~A)~%" (%completion-zsh-command-labels command))
      (write-string (%completion-zsh-option-specs-source options
                                                         "command_option_specs"
                                                         :app app)
                    out)
      (%completion-zsh-render-value-cases options out)
      (when subcommands
        (format out "      case \"${words[~A]}\" in~%" child-depth)
        (dolist (subcommand subcommands)
          (write-string (%completion-zsh-command-node app subcommand options child-depth)
                        out))
        (format out "      esac~%"))
      (format out "      if [[ \"$current_word\" == -* ]]; then~%")
      (format out "        _describe 'options' command_option_specs~%")
      (format out "        return 0~%")
      (format out "      fi~%")
      (when subcommands
        (format out "      if (( CURRENT == ~A )); then~%" child-depth)
        (write-string (%completion-zsh-subcommand-specs-source subcommands) out)
        (format out "        _describe 'commands' subcommand_specs~%")
        (format out "        return 0~%")
        (format out "      fi~%"))
      (let ((positional-values (%completion-command-positional-values command)))
        (when positional-values
          (format out "      compadd -- ~{~A~^ ~}~%"
                  (mapcar #'%completion-shell-quote positional-values))))
      (when (%completion-command-positional-hint-p command :file)
        (format out "      _files~%"))
      (when (%completion-command-positional-hint-p command :dir)
        (format out "      _files -/~%"))
      (format out "      _describe 'options' command_option_specs~%")
      (format out "      return 0~%")
      (format out "      ;;~%"))))

(defun %completion-zsh-command-case-source (app command)
  (%completion-zsh-command-node app command (app-global-options app) 2))

(defun render-zsh-completion (app &optional stream)
  "Render a zsh completion script.

With no STREAM, return the completion script as a string. With a STREAM,
write the script to it and return no values."
  (unless stream
    (return-from render-zsh-completion
      (with-output-to-string (string-stream)
        (render-zsh-completion app string-stream))))
  (let ((function-name (%completion-function-name app))
        (app-name (%completion-control-safe-string (app-name app))))
    (format stream "#compdef ~A~%" app-name)
    (format stream "~A() {~%" function-name)
    (format stream "  local current_word previous_word command_word~%")
    (format stream "  local -a command_specs option_specs command_option_specs subcommand_specs value_candidates~%")
    (format stream "  current_word=${words[CURRENT]}~%")
    (format stream "  if (( CURRENT > 1 )); then~%")
    (format stream "    previous_word=${words[CURRENT-1]}~%")
    (format stream "  else~%")
    (format stream "    previous_word=~%")
    (format stream "  fi~%")
    (format stream "  if (( CURRENT > 2 )); then~%")
    (format stream "    command_word=${words[2]}~%")
    (format stream "  else~%")
    (format stream "    command_word=~%")
    (format stream "  fi~%")
    (write-string (%completion-zsh-command-specs-source app) stream)
    (write-string (%completion-zsh-option-specs-source (app-global-options app)
                                                       "option_specs"
                                                       :app app)
                  stream)
    (%completion-zsh-render-value-cases (app-global-options app) stream)
    (if (%completion-visible-commands app)
        (progn
          (format stream "  case \"$command_word\" in~%")
          (dolist (command (%completion-visible-commands app))
            (write-string (%completion-zsh-command-case-source app command)
                          stream))
          (format stream "    *)~%")
          (format stream "      if [[ \"$current_word\" == -* ]]; then~%")
          (format stream "        _describe 'options' option_specs~%")
          (format stream "        return 0~%")
          (format stream "      fi~%")
          (let ((positional-values (%completion-app-positional-values app)))
            (when positional-values
              (format stream "      compadd -- ~{~A~^ ~}~%"
                      (mapcar #'%completion-shell-quote positional-values))))
          (when (%completion-app-positional-hint-p app :file)
            (format stream "      _files~%"))
          (when (%completion-app-positional-hint-p app :dir)
            (format stream "      _files -/~%"))
          (format stream "      _describe 'commands' command_specs~%")
          (format stream "      return 0~%")
          (format stream "      ;;~%")
          (format stream "  esac~%"))
        (progn
          (format stream "  if [[ -z \"$current_word\" || \"$current_word\" == -* ]]; then~%")
          (format stream "    _describe 'options' option_specs~%")
          (format stream "    return 0~%")
          (format stream "  fi~%")
          (let ((positional-values (%completion-app-positional-values app)))
            (when positional-values
              (format stream "  compadd -- ~{~A~^ ~}~%"
                      (mapcar #'%completion-shell-quote positional-values))))
          (when (%completion-app-positional-hint-p app :file)
            (format stream "  _files~%"))
          (when (%completion-app-positional-hint-p app :dir)
            (format stream "  _files -/~%"))))
    (format stream "}~%")
    (format stream "compdef ~A ~A~%"
            function-name
            (%completion-shell-quote app-name))
    (values)))
