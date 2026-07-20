(in-package :cl-cli)

(defun %fish-command-seen-condition (command)
  "Fish predicate true once COMMAND (by any of its names) has been used."
  (format nil "__fish_seen_subcommand_from ~{~A~^ ~}"
          (mapcar #'%completion-shell-quote
                  (%completion-command-names command))))

(defun %fish-path-seen-condition (path)
  "Fish predicate true when every command in PATH has been seen.

PATH is the chain of ancestor command specs from the app root down to (but not
including) the level being completed. At the root (empty PATH) the predicate is
`__fish_use_subcommand`, which fish makes true only before any subcommand is
chosen -- so a top-level command name is offered exactly when no command has yet
been typed. A nested level requires each ancestor to have been seen."
  (if (null path)
      "__fish_use_subcommand"
      (format nil "~{~A~^; and ~}"
              (mapcar #'%fish-command-seen-condition path))))

(defun %render-fish-command-values (app command condition stream)
  "Emit COMMAND's positional value / directory-hint completions under CONDITION."
  (let ((app-name (app-name app))
        (values (%completion-command-positional-values command)))
    (when values
      (format stream "complete -c ~A -n ~A -a ~A~%"
              (%completion-shell-quote app-name)
              (%completion-shell-quote condition)
              (%completion-shell-quote (%completion-space-joined values))))
    (when (%completion-command-positional-hint-p command :dir)
      (format stream "complete -c ~A -n ~A -a '(__fish_complete_directories)'~%"
              (%completion-shell-quote app-name)
              (%completion-shell-quote condition)))))

(defun %render-fish-command-tree (app reversed-path commands stream)
  "Recursively emit fish completions for COMMANDS (children of PATH's leaf).

Offers each visible command's name (and aliases) when the ancestor path is seen
and no sibling at this level has been chosen yet, then emits each command's
options and positionals, and recurses into its subcommands."
  (let ((app-name (app-name app))
        (path (nreverse (copy-list reversed-path)))
        (visible (remove-if #'command-hidden-p commands)))
    (when visible
      (let* ((sibling-names (let (names)
                              (dolist (command visible (nreverse names))
                                (dolist (name (%completion-command-names command))
                                  (push (%completion-shell-quote name) names)))))
             (offer-condition
               (format nil "~A; and not __fish_seen_subcommand_from ~{~A~^ ~}"
                       (%fish-path-seen-condition path)
                       sibling-names)))
        (dolist (command visible)
          (let ((description (or (command-description command) "")))
            (dolist (name (%completion-command-names command))
              (format stream "complete -c ~A -n ~A -a ~A -d ~A~%"
                      (%completion-shell-quote app-name)
                      (%completion-shell-quote offer-condition)
                      (%completion-shell-quote name)
                      (%completion-shell-quote description)))))
        (dolist (command visible)
          (let ((seen (%fish-command-seen-condition command)))
            (%render-fish-option-lines app (command-options command) seen stream)
            (%render-fish-command-values app command seen stream))
          (%render-fish-command-tree app
                                     (cons command reversed-path)
                                     (command-subcommands command)
                                     stream))))))

(defun render-fish-completion (app &optional stream)
  "Render a fish completion script.

With no STREAM, return the completion script as a string. With a STREAM,
write the script to it and return no values. Subcommand names complete at every
level of a nested command tree, and options/positionals complete once their
command is on the line."
  (unless stream
    (return-from render-fish-completion
      (with-output-to-string (string-stream)
        (render-fish-completion app string-stream))))
  (let ((app-name (app-name app)))
    (format stream "complete -c ~A -f~%" (%completion-shell-quote app-name))
    (%render-fish-option-lines app (app-global-options app) nil stream)
    (let ((root-positional-values (%completion-app-positional-values app)))
      (when root-positional-values
        (format stream "complete -c ~A -a ~A~%"
                (%completion-shell-quote app-name)
                (%completion-shell-quote
                 (%completion-space-joined root-positional-values)))))
    (when (%completion-app-positional-hint-p app :dir)
      (format stream "complete -c ~A -a '(__fish_complete_directories)'~%"
              (%completion-shell-quote app-name)))
    (%render-fish-command-tree app nil (app-commands app) stream)
    (values)))
