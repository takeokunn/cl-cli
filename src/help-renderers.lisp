(in-package :cl-cli)

(defun %command-display-name (command)
  (if (command-aliases command)
      (format nil "~A (~{~A~^, ~})"
              (command-name command)
              (command-aliases command))
      (command-name command)))

(defun %usage-options-token (label)
  (format nil "[~A]" label))

(defun %join-help-metadata (parts)
  (if parts
      (format nil " (~{~A~^; ~})" parts)
      ""))

(defun %public-relation-targets (option options relation-targets)
  (let ((targets nil))
    (dolist (target relation-targets (nreverse targets))
      (let ((resolved (resolve-related-option-spec options target)))
        (when (and resolved
                   (not (eq (option-key resolved) (option-key option)))
                   (public-option-candidate-p resolved))
          (push target targets))))))

(defun %option-group-member-names (option options)
  "Public display names of the members of OPTION's exclusive group, or NIL."
  (let ((group (option-group option)))
    (when group
      (loop for key in (option-group-members group)
            for spec = (resolve-related-option-spec options key)
            when (and spec (public-option-candidate-p spec))
              collect (option-token-display-name (first (option-names spec)))))))

(defun %option-intra-group-conflict-p (option options target)
  "True when TARGET is another member of OPTION's own exclusive group."
  (let ((group (option-group option)))
    (and group
         (let ((resolved (resolve-related-option-spec options target)))
           (and resolved
                (member (option-key resolved)
                        (option-group-members group)))))))

(defun %option-metadata-parts (option options)
  (let ((parts nil))
    (when (option-multiple-p option)
      (push "repeatable" parts))
    (when (option-required-p option)
      (push "required" parts))
    (when (option-default-present-p option)
      (push (format nil "default: ~A" (option-default option)) parts))
    (when (option-env-vars option)
      (push (format nil "env: ~{~A~^, ~}" (option-env-vars option)) parts))
    (when (option-choices option)
      (push (format nil "choices: ~{~A~^ | ~}" (option-choices option)) parts))
    (let ((group-members (%option-group-member-names option options)))
      (when group-members
        (push (format nil "~A one of: ~{~A~^ | ~}"
                      (if (option-group-required-p (option-group option))
                          "exactly"
                          "at most")
                      group-members)
              parts)))
    (let ((visible-requires (%public-relation-targets option options
                                                      (option-requires option))))
      (when visible-requires
        (push (format nil "requires: ~{~A~^, ~}"
                      (mapcar #'option-relation-target-display-name
                              visible-requires))
              parts)))
    ;; Conflicts among members of this option's own group are already conveyed by
    ;; the "one of" line above; only surface conflicts with options outside it.
    (let ((visible-conflicts
            (remove-if (lambda (target)
                         (%option-intra-group-conflict-p option options target))
                       (%public-relation-targets option options
                                                 (option-conflicts-with option)))))
      (when visible-conflicts
        (push (format nil "conflicts: ~{~A~^, ~}"
                      (mapcar #'option-relation-target-display-name
                              visible-conflicts))
              parts)))
    (nreverse parts)))

(defun %option-metadata-string (option options)
  (%join-help-metadata (%option-metadata-parts option options)))

(defun %option-display-string (option)
  (with-output-to-string (out)
    (loop for name in (append (option-names option)
                              (option-negated-names option))
          for index from 0
          do (when (> index 0)
               (write-string ", " out))
             (write-string (option-token-display-name name) out))
    (when (and (option-kind option)
               (not (member (option-kind option) '(:flag :boolean))))
      (let ((value-name (or (option-value-name option)
                            (symbol-name (option-key option)))))
        (if (eq (option-kind option) :optional-value)
            (format out "[=<~A>]" value-name)
            (format out " <~A>" value-name))))))

(defun %option-description-string (option options)
  (concatenate 'string
               (or (option-description option) "")
               (%option-metadata-string option options)))

(defun %print-option-row (stream option options)
  (format stream "  ~24A ~A~%"
          (%option-display-string option)
          (%option-description-string option options)))

(defun %usage-positionals-string (positionals)
  (with-output-to-string (out)
    (dolist (positional positionals)
      (format out " ~A" (%format-positional-token positional)))))

(defun %format-root-usage (app)
  (with-output-to-string (out)
    (format out "Usage: ~A" (app-name app))
    (when (app-global-options app)
      (format out " ~A" (%usage-options-token "global-options")))
    (cond
      ((app-positionals app)
       (write-string (%usage-positionals-string (app-positionals app)) out))
      ((app-handler app)
       (format out " ~A" (%usage-options-token "args"))))
    (terpri out)))

(defun %format-positional-token (positional)
  (let ((name (symbol-name (positional-spec-key positional))))
    (cond
      ((positional-spec-rest-p positional)
       (if (positional-spec-required-p positional)
           (format nil "~A..." name)
           (format nil "[~A...]" name)))
      ((positional-spec-required-p positional)
       name)
      (t
       (format nil "[~A]" name)))))

(defun %visible-commands (commands)
  (stable-sort-copy (remove-if #'command-hidden-p commands)
                    #'string<
                    :key #'command-name))

(defun %command-sections (commands)
  (let ((ungrouped nil)
        (group-order nil)
        (group-table (make-hash-table :test #'equal)))
    (dolist (command commands)
      (let ((group (command-group command)))
        (if group
            (progn
              (unless (gethash group group-table)
                (setf (gethash group group-table) nil)
                (push group group-order))
              (push command (gethash group group-table)))
            (push command ungrouped))))
    (nconc (when ungrouped
             (list (cons nil (nreverse ungrouped))))
           (mapcar (lambda (group)
                     (cons group (nreverse (gethash group group-table))))
                   (nreverse group-order)))))

(defun %print-command-row (stream command)
  (format stream "  ~24A ~A~%"
          (%command-display-name command)
          (or (command-description command) "")))

(defun %format-command-dispatch-usage (app)
  (format nil "Usage: ~A <command> [args]~%" (app-name app)))

(defun %print-commands (stream commands)
  (let ((sections (%command-sections (%visible-commands commands))))
    (when sections
      (format stream "~&Commands:~%")
      (dolist (section sections)
        (when (car section)
          (format stream "~&~A:~%" (car section)))
        (dolist (command (cdr section))
          (%print-command-row stream command))))))

(defun %print-positional-row (stream positional)
  (format stream "  ~24A ~A~%"
          (%format-positional-token positional)
          (or (positional-spec-description positional) "")))

(defun %print-examples (stream examples)
  (when examples
    (format stream "~&Examples:~%")
    (dolist (example examples)
      (format stream "  ~A~%" example))))
