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
