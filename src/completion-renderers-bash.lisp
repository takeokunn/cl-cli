(in-package :cl-cli)

(defun %completion-bash-static-compreply-source (values indent &key replace-p)
  (with-output-to-string (out)
    (when replace-p
      (format out "~ACOMPREPLY=()~%" indent))
    (format out "~Acomp_values=~A~%" indent
            (%completion-bash-array-literal values))
    (format out "~Afor comp_value in \"${comp_values[@]}\"; do~%" indent)
    (format out "~A  [[ -n \"$comp_value\" && \"$comp_value\" == \"$cur\"* ]] && COMPREPLY+=(\"$comp_value\")~%" indent)
    (format out "~Adone~%" indent)))

(defun %completion-bash-value-case-body (options &key command-name)
  (with-output-to-string (out)
    (dolist (option options)
      (unless (option-hidden-p option)
        (let* ((labels (%completion-option-value-patterns option
                                                          :command-name command-name
                                                          :attached-p t))
               (value-source (%completion-option-value-source option)))
          (when (and labels value-source)
            (format out "    ~A)~%" (%completion-case-labels labels))
            (write-string (%completion-bash-static-compreply-source
                           value-source "      " :replace-p t)
                          out)
            (format out "      return 0~%")
            (format out "      ;;~%")))))))

(defun %completion-bash-option-case-body (options &key command-name)
  (with-output-to-string (out)
    (write-string (%completion-option-scan-rules options
                                                 :command-name command-name)
                  out)))

(defun %completion-bash-expect-value-source (indent)
  "Emit the block that turns a pending expect_value into COMPREPLY.

The `case \"$prev\"` scan sets expect_value / expect_optional_value and
value_source when the previous word is a value option; this consumes them so a
separated value (`--option <TAB>`) actually completes its candidates."
  (with-output-to-string (out)
    (format out "~Aif [[ -n \"$expect_value\" || -n \"$expect_optional_value\" ]]; then~%" indent)
    (format out "~A  COMPREPLY=()~%" indent)
    (format out "~A  if [[ -n \"$comp_dynamic\" ]]; then~%" indent)
    ;; Query the program itself for runtime candidates (${words[0]} is the exact
    ;; command the user invoked); requires a __complete command in the app.
    ;; Read the tab-separated protocol directly so spaces in candidate values
    ;; stay within the same completion record.
    (format out "~A    while IFS=$'\\t' read -r comp_value _; do~%" indent)
    (format out "~A      [[ -n \"$comp_value\" && \"$comp_value\" == \"$cur\"* ]] && COMPREPLY+=(\"$comp_value\")~%" indent)
    (format out "~A    done < <(\"${words[0]}\" __complete \"$comp_dynamic\" \"$cur\" 2>/dev/null)~%" indent)
    (format out "~A  elif [[ -n \"$comp_dir\" ]]; then~%" indent)
    (format out "~A    COMPREPLY=( $(compgen -d -- \"$cur\") )~%" indent)
    (format out "~A  else~%" indent)
    (format out "~A    for comp_value in \"${value_source[@]}\"; do~%" indent)
    (format out "~A      [[ -n \"$comp_value\" && \"$comp_value\" == \"$cur\"* ]] && COMPREPLY+=(\"$comp_value\")~%" indent)
    (format out "~A    done~%" indent)
    (format out "~A  fi~%" indent)
    (format out "~A  return 0~%" indent)
    (format out "~Afi~%" indent)))

(defun %completion-bash-cur-case-source (app)
  (with-output-to-string (out)
    (let ((global-options (app-global-options app)))
      (format out "  case \"$cur\" in~%")
      (write-string (%completion-bash-value-case-body global-options) out)
      (format out "  esac~%")
      (format out "  case \"$prev\" in~%")
      (write-string (%completion-bash-option-case-body global-options) out)
      (format out "  esac~%")
      (write-string (%completion-bash-expect-value-source "  ") out)
      (when (%completion-visible-commands app)
        ;; Complete command names at the first word -- but not when the user is
        ;; typing an option there (`app -<TAB>`), which must fall through to the
        ;; global-option completion below.
        (format out "  if (( cword == 1 )) && [[ \"$cur\" != -* ]]; then~%")
        (write-string (%completion-bash-static-compreply-source
                       (%completion-visible-command-tokens app)
                       "    " :replace-p t)
                      out)
        (format out "    return 0~%")
        (format out "  fi~%"))
      (format out "  if [[ \"$cur\" == -* ]]; then~%")
      (if (%completion-visible-commands app)
          ;; Offer global options only before a subcommand is on the line; once a
          ;; command is present its own case completes options with the full
          ;; option scope (globals + the command's own). Without this guard the
          ;; root fallback returns global options for every `-*` and shadows all
          ;; subcommand option completion.
          (progn
            (format out "    case \"${words[1]}\" in~%")
            (format out "      ~A) ;;~%"
                    (%completion-case-labels (%completion-visible-command-tokens app)))
            (format out "      *)~%")
            (write-string (%completion-bash-static-compreply-source
                           (%completion-command-option-tokens app nil)
                           "        " :replace-p t)
                          out)
            (format out "        return 0~%")
            (format out "        ;;~%")
            (format out "    esac~%"))
          (progn
            (write-string (%completion-bash-static-compreply-source
                           (%completion-command-option-tokens app nil)
                           "    " :replace-p t)
                          out)
            (format out "    return 0~%")))
      (format out "  fi~%")
      (let ((positional-values (%completion-app-positional-values app)))
        (when positional-values
          (write-string (%completion-bash-static-compreply-source
                         positional-values "  ")
                        out)))
      (when (%completion-app-positional-hint-p app :file)
        (format out "  COMPREPLY+=( $(compgen -f -- \"$cur\") )~%"))
      (when (%completion-app-positional-hint-p app :dir)
        (format out "  COMPREPLY+=( $(compgen -d -- \"$cur\") )~%")))))

(defun %completion-bash-scope-option-tokens (scope-options app)
  "Visible option tokens for SCOPE-OPTIONS plus APP's built-in tokens."
  (append (%completion-visible-option-tokens scope-options)
          (%completion-option-tokens-for-specs (built-in-option-specs app))))

(defun %completion-bash-command-node (app command scope-options depth prefix)
  "Recursively render the bash case block for COMMAND at word index DEPTH.

SCOPE-OPTIONS accumulates the options in scope (globals + every ancestor
command's options + COMMAND's own); PREFIX is a per-node label prefix (the
command path) that keeps the value/option `case` labels distinct across the
tree. A command with subcommands offers their names at DEPTH+1 and recurses."
  (with-output-to-string (out)
    (let* ((options (append scope-options (command-options command)))
           (subcommands (remove-if #'command-hidden-p (command-subcommands command)))
           (child-depth (1+ depth)))
      (format out "  case \"${words[~A]}\" in~%" depth)
      (format out "    ~A)~%"
              (%completion-case-labels (%completion-command-names command)))
      (format out "      case \"~A:$cur\" in~%" prefix)
      (write-string (%completion-bash-value-case-body options :command-name prefix)
                    out)
      (format out "      esac~%")
      (format out "      case \"~A:$prev\" in~%" prefix)
      (write-string (%completion-bash-option-case-body options :command-name prefix)
                    out)
      (format out "      esac~%")
      (write-string (%completion-bash-expect-value-source "      ") out)
      (when subcommands
        (format out "      if (( cword == ~A )); then~%" child-depth)
        (write-string (%completion-bash-static-compreply-source
                       (let (names)
                         (dolist (sub subcommands (nreverse names))
                           (dolist (name (%completion-command-names sub))
                             (push name names))))
                       "        ")
                      out)
        (format out "      fi~%")
        (dolist (sub subcommands)
          (write-string (%completion-bash-command-node
                         app sub options child-depth
                         (format nil "~A/~A" prefix (command-name sub)))
                        out)))
      (format out "      if [[ \"$cur\" == -* ]]; then~%")
      (write-string (%completion-bash-static-compreply-source
                     (%completion-bash-scope-option-tokens options app)
                     "        " :replace-p t)
                    out)
      (format out "      fi~%")
      (let ((positional-values (%completion-command-positional-values command)))
        (when positional-values
          (write-string (%completion-bash-static-compreply-source
                         positional-values "      ")
                        out)))
      (when (%completion-command-positional-hint-p command :file)
        (format out "      COMPREPLY+=( $(compgen -f -- \"$cur\") )~%"))
      (when (%completion-command-positional-hint-p command :dir)
        (format out "      COMPREPLY+=( $(compgen -d -- \"$cur\") )~%"))
      (format out "      return 0~%")
      (format out "      ;;~%")
      (format out "  esac~%"))))

(defun %completion-bash-command-case-source (app command)
  (%completion-bash-command-node app command (app-global-options app) 1
                                 (command-name command)))

(defun render-bash-completion (app &optional stream)
  "Render a bash completion script.

With no STREAM, return the completion script as a string. With a STREAM,
write the script to it and return no values."
  (unless stream
    (return-from render-bash-completion
      (with-output-to-string (string-stream)
        (render-bash-completion app string-stream))))
  (let ((function-name (%completion-function-name app))
        (app-name (%completion-control-safe-string (app-name app))))
      (format stream "#!/usr/bin/env bash~%")
      (format stream "# bash completion for ~A~%" app-name)
      (format stream "~A() {~%" function-name)
      (format stream "  local cur prev words cword expect_value expect_optional_value comp_dir comp_dynamic comp_value~%")
      (format stream "  local -a value_source comp_values~%")
      ;; -s makes _init_completion split `--opt=value` so an attached value
      ;; completes through the same prev-word path as a separated one.
      (format stream "  _init_completion -s || return~%")
      (write-string (%completion-bash-cur-case-source app) stream)
      (dolist (command (%completion-visible-commands app))
        (write-string (%completion-bash-command-case-source app command)
                      stream))
      (format stream "}~%")
      ;; -o default lets a value slot with no explicit candidates (a plain
      ;; :value option, or one with a :file hint) fall back to readline filename
      ;; completion instead of completing nothing.
      (format stream "complete -o default -F ~A ~A~%"
              function-name
              (%completion-shell-quote app-name))
    (values)))
