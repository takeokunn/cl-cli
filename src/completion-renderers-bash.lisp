(in-package :cl-cli)

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
            (format out "      value_source=~A~%" value-source)
            (format out "      COMPREPLY=( $(compgen -W \"$value_source\" -- \"$cur\") )~%")
            (format out "      return 0~%")
            (format out "      ;;~%")))))))

(defun %completion-bash-option-case-body (options &key command-name)
  (with-output-to-string (out)
    (write-string (%completion-option-scan-rules options
                                                 :command-name command-name)
                  out)))

(defun %completion-bash-cur-case-source (app)
  (with-output-to-string (out)
    (let ((global-options (app-global-options app)))
      (format out "  case \"$cur\" in~%")
      (write-string (%completion-bash-value-case-body global-options) out)
      (format out "  esac~%")
      (format out "  case \"$prev\" in~%")
      (write-string (%completion-bash-option-case-body global-options) out)
      (format out "  esac~%")
      (when (%completion-visible-commands app)
        (format out "  if (( cword == 1 )); then~%")
        (format out "    COMPREPLY=( $(compgen -W ~A -- \"$cur\") )~%"
                (%completion-shell-quote
                 (%completion-space-joined
                  (%completion-visible-command-tokens app))))
        (format out "    return 0~%")
        (format out "  fi~%"))
      (format out "  if [[ \"$cur\" == -* ]]; then~%")
      (format out "    COMPREPLY=( $(compgen -W ~A -- \"$cur\") )~%"
              (%completion-shell-quote
               (%completion-space-joined
                (%completion-command-option-tokens app nil))))
      (format out "    return 0~%")
      (format out "  fi~%"))))

(defun %completion-bash-command-case-source (app command)
  (with-output-to-string (out)
    (let* ((command-name (command-name command))
           (options (append (app-global-options app)
                            (command-options command))))
      (format out "  case \"${words[1]}\" in~%")
      (format out "    ~A)~%"
              (%completion-case-labels (%completion-command-names command)))
      (format out "      case \"$cur\" in~%")
      (write-string (%completion-bash-value-case-body options
                                                       :command-name command-name)
                    out)
      (format out "      esac~%")
      (format out "      case \"~A:$prev\" in~%" command-name)
      (write-string (%completion-bash-option-case-body options
                                                        :command-name command-name)
                    out)
      (format out "      esac~%")
      (format out "      if [[ \"$cur\" == -* ]]; then~%")
      (format out "        COMPREPLY=( $(compgen -W ~A -- \"$cur\") )~%"
              (%completion-shell-quote
               (%completion-space-joined
                (%completion-command-option-tokens app command))))
      (format out "      fi~%")
      (format out "      return 0~%")
      (format out "      ;;~%")
      (format out "  esac~%"))))

(defun render-bash-completion (app &optional stream)
  "Render a bash completion script."
  (let ((stream (or stream *standard-output*))
        (function-name (%completion-function-name app))
        (app-name (app-name app)))
      (format stream "#!/usr/bin/env bash~%")
      (format stream "# bash completion for ~A~%" app-name)
      (format stream "~A() {~%" function-name)
      (format stream "  local cur prev words cword value_source~%")
      (format stream "  _init_completion || return~%")
      (write-string (or (%completion-bash-cur-case-source app) "")
                    stream)
      (dolist (command (%completion-visible-commands app))
        (write-string (%completion-bash-command-case-source app command)
                      stream))
      (format stream "}~%")
      (format stream "complete -F ~A ~A~%"
              function-name
              (%completion-shell-quote app-name))
    (values)))
