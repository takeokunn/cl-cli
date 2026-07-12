(in-package :cl-cli)

(defun validate-option-relationships (values specs)
  (dolist (spec specs values)
    (when (plist-has-key-p values (option-key spec))
      (dolist (target (option-requires spec))
        (let ((dependency (resolve-related-option-spec specs target)))
          (unless (plist-has-key-p values (option-key dependency))
            (signal-cli-error 'cli-missing-dependent-option
                              (format nil "Option ~A requires ~A."
                                      (%option-display-name spec)
                                      (public-option-display-name dependency))
                              :option (option-key spec)
                              :dependency (option-key dependency)))))
      (dolist (target (option-conflicts-with spec))
        (let ((other (resolve-related-option-spec specs target)))
          (when (plist-has-key-p values (option-key other))
            (signal-cli-error 'cli-conflicting-options
                              (format nil "Option ~A conflicts with ~A."
                                      (%option-display-name spec)
                                      (public-option-display-name other))
                              :left-option (option-key spec)
                              :right-option (option-key other))))))))

(defun option-table-from-specs (specs)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (spec specs table)
      (dolist (entry (%option-table-entries spec))
        (destructuring-bind (name negated-p) entry
          (let ((key (canonical-option-name name)))
            (%register-table-entry table
                                   key
                                    (list :spec spec
                                          :name key
                                          :negated-p negated-p)
                                    "option name"
                                    (option-token-display-name key))))))))

(defun command-table-from-specs (commands)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (command commands table)
      (%register-table-entry table
                             (command-name command)
                             (list :command command
                                   :name (command-name command))
                             "command name"
                             (command-name command))
      (dolist (alias (command-aliases command))
        (%register-table-entry table
                               alias
                               (list :command command
                                     :name alias)
                               "command name"
                               alias)))))

(defun public-option-candidate-p (spec)
  (or (not (option-hidden-p spec))
      (built-in-option-p spec)))

(defun public-command-candidate-p (command)
  (not (command-hidden-p command)))

(defun option-candidate-names (specs &key short-only-p long-only-p)
  (let ((candidates nil))
    (dolist (spec specs (nreverse candidates))
      (when (public-option-candidate-p spec)
        (dolist (name (option-names spec))
          (when (or (and short-only-p (= (length name) 1))
                    (and long-only-p (> (length name) 1))
                    (and (not short-only-p) (not long-only-p)))
            (push (option-token-display-name name)
                  candidates)))))))

(defun command-candidate-names (app)
  (let ((candidates nil))
    (dolist (command (app-commands app) (nreverse candidates))
      (when (public-command-candidate-p command)
        (push (command-name command) candidates)
        (dolist (alias (command-aliases command))
          (push alias candidates))))))

(defun unknown-option-message (raw-name candidates)
  (format nil "Unknown option: ~A~A"
          raw-name
          (format-suggestion-suffix raw-name candidates)))

(defun unknown-command-message (app command-name)
  (format nil "Unknown command: ~A~A"
          command-name
          (format-suggestion-suffix command-name
                                    (command-candidate-names app))))

(defun resolve-option-entry (table name)
  (gethash (canonical-option-name name) table))

(defun resolve-long-option-entry (name table specs)
  (or (resolve-option-entry table name)
      (signal-cli-error 'cli-unknown-option
                        (unknown-option-message (format nil "--~A" name)
                                                (option-candidate-names specs
                                                                        :long-only-p t))
                        :option name)))

(defun option-entry-spec (entry)
  (getf entry :spec))

(defun option-entry-negated-p (entry)
  (getf entry :negated-p))

(defun resolve-command-spec (table name)
  (gethash (canonical-name name) table))

(defun short-option-candidates (specs)
  (option-candidate-names specs :short-only-p t))

(defun signal-unknown-short-option (name specs)
  (signal-cli-error 'cli-unknown-option
                    (unknown-option-message (format nil "-~A" name)
                                            (short-option-candidates specs))
                    :option name))
