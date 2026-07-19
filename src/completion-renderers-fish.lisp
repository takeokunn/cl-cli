(in-package :cl-cli)

(defun render-fish-completion (app &optional stream)
  "Render a fish completion script.

With no STREAM, return the completion script as a string. With a STREAM,
write the script to it and return no values."
  (unless stream
    (return-from render-fish-completion
      (with-output-to-string (string-stream)
        (render-fish-completion app string-stream))))
  (let ((app-name (app-name app)))
    (format stream "complete -c ~A -f~%" (%completion-shell-quote app-name))
    (dolist (command (%completion-visible-commands app))
      (format stream "complete -c ~A -n ~A -a ~A -d ~A~%"
              (%completion-shell-quote app-name)
              (%completion-shell-quote (%completion-fish-command-condition command))
              (%completion-shell-quote (command-name command))
              (%completion-shell-quote (or (command-description command) "")))
      (dolist (alias (command-aliases command))
        (format stream "complete -c ~A -n ~A -a ~A -d ~A~%"
                (%completion-shell-quote app-name)
                (%completion-shell-quote (%completion-fish-command-condition command))
                (%completion-shell-quote alias)
                (%completion-shell-quote (or (command-description command) "")))))
    (%render-fish-option-lines app (app-global-options app) nil stream)
    (dolist (command (%completion-visible-commands app))
      (%render-fish-option-lines app
                                 (command-options command)
                                 (%completion-fish-command-condition command)
                                 stream))
    (values)))
