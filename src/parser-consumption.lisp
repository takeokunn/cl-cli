(in-package :cl-cli)

(defun parse-options-prefix (app tokens option-specs)
  (multiple-value-bind (validated-specs table)
      (prepare-option-parser-state app option-specs)
    (let ((values nil)
          (remaining tokens)
          (action :dispatch)
          (literal-separator-seen-p nil))
      (labels ((scan ()
                 (cond
                   ((null remaining)
                    (values values remaining action literal-separator-seen-p))
                   ((string= (first remaining) "--")
                    (setf literal-separator-seen-p t
                          remaining (rest remaining))
                    (values values remaining action literal-separator-seen-p))
                   (t
                    (multiple-value-bind (new-values new-remaining new-action
                                             done-p consumed-p)
                        (consume-argument-option-token (first remaining)
                                                       validated-specs
                                                       table
                                                       values
                                                       action
                                                       remaining)
                      (if consumed-p
                          (progn
                            (setf values new-values
                                  remaining new-remaining
                                  action new-action)
                            (if done-p
                                (values values remaining action
                                        literal-separator-seen-p)
                                (scan)))
                          (values values remaining action
                                  literal-separator-seen-p)))))))
        (scan)))))

(defun parse-mixed-arguments (app tokens option-specs positional-specs
                               &optional initial-option-values
                               &key command)
  (multiple-value-bind (validated-specs table)
      (prepare-option-parser-state app option-specs)
    (let* ((option-values initial-option-values)
           (positional-values nil)
           (remaining tokens)
           (pending positional-specs)
           (action :dispatch)
           (literal-mode-p nil))
      (labels ((consume-positional-token ()
                 (cond
                   ((null pending)
                    (signal-unexpected-positionals remaining))
                   (t
                    (let ((spec (first pending)))
                      (multiple-value-bind (new-values new-remaining)
                          (apply-positional-spec spec
                                                 positional-values
                                                 remaining)
                        (setf positional-values new-values
                              remaining new-remaining
                              pending (if (positional-spec-rest-p spec)
                                          nil
                                          (rest pending)))))))))
        (loop while remaining
              for token = (first remaining)
              do (cond
                   ((and (not literal-mode-p)
                         (string= token "--"))
                    (setf literal-mode-p t
                          remaining (rest remaining)))
                   ((not literal-mode-p)
                    (multiple-value-bind (new-values new-remaining new-action done-p
                                          consumed-p)
                        (consume-argument-option-token token validated-specs table
                                                       option-values action
                                                       remaining)
                      (if consumed-p
                          (progn
                            (setf option-values new-values
                                  remaining new-remaining
                                  action new-action)
                            (when done-p
                              (setf literal-mode-p t)))
                          (consume-positional-token))))
                   (t
                    (consume-positional-token)))))
      (unless (member action '(:help :version))
        (setf positional-values
              (finalize-pending-positionals pending positional-values)))
      (setf option-values (apply-option-defaults option-values validated-specs))
      (unless (member action '(:help :version))
        (validate-required-options option-values validated-specs)
        (validate-option-relationships
         option-values validated-specs
         (if command
             (gethash command (app-command-relation-rulebases app))
             (app-global-relation-rulebase app)))
        (validate-required-option-groups option-values validated-specs))
      (values option-values positional-values action))))
