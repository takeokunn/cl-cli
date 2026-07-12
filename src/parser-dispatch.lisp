(in-package :cl-cli)

(defun make-parser-invocation (app command argv0 raw-argv action
                               global-options command-options positionals)
  (%make-invocation :app app
                    :command command
                    :action action
                    :argv0 argv0
                    :raw-argv raw-argv
                    :global-options global-options
                    :command-options command-options
                    :positionals positionals
                    :stdout nil
                    :stderr nil))

(defun app-global-stop-parsing-p (app global-values)
  (loop for spec in (app-global-options app)
        thereis (and (option-stop-parsing-p spec)
                     (plist-has-key-p global-values
                                      (option-key spec)))))

(defun merge-global-options (app parsed-global-options initial-global-values)
  (apply-option-defaults
   (merge-option-values initial-global-values
                        (app-global-options app)
                        parsed-global-options)
   (app-global-options app)))

(defun finalize-command-options (command parsed-options)
  (collect-option-values (command-options command) parsed-options))

(defun resolve-dispatch-command (app command-table remaining global-stop-parsing-p)
  (cond
    ((and (null remaining)
          (app-default-command app))
     (values (resolve-default-command app command-table) remaining))
    ((and remaining
          (not global-stop-parsing-p)
          (not (command-line-option-p (first remaining))))
     (multiple-value-bind (resolved-command consume-token-p)
         (resolve-command-selection app command-table (first remaining))
       (if resolved-command
           (values resolved-command
                   (if consume-token-p
                       (rest remaining)
                       remaining))
           (values nil remaining))))
    (t
     (values nil remaining))))

(defun parse-command-argv (app command argv0 raw-argv remaining global-values)
  (let ((*cli-error-command* command))
    (multiple-value-bind (combined-option-values parsed-positionals command-action)
        (parse-mixed-arguments app remaining
                                (append (app-global-options app)
                                        (command-options command))
                                (command-positionals command)
                                global-values)
      (let ((resolved-global-options
              (merge-global-options app combined-option-values global-values))
            (resolved-command-options
              (finalize-command-options command combined-option-values)))
        (unless (member command-action '(:help :version))
          (validate-required-options resolved-global-options
                                     (app-global-options app)))
        (make-parser-invocation app command argv0 raw-argv command-action
                                resolved-global-options
                                resolved-command-options
                                parsed-positionals)))))

(defun parse-root-argv (app argv0 raw-argv remaining global-values
                        global-stop-parsing-p global-literal-separator-seen-p)
  (multiple-value-bind (parsed-global-options parsed-positionals parsed-action)
      (if (or global-stop-parsing-p
              global-literal-separator-seen-p)
          (values nil
                  (parse-literal-positionals (app-positionals app) remaining)
                  :dispatch)
          (parse-mixed-arguments app remaining
                                 (app-global-options app)
                                 (app-positionals app)
                                 global-values))
    (let ((resolved-global-options
            (merge-global-options app parsed-global-options global-values)))
      (unless (member parsed-action '(:help :version))
        (validate-required-options resolved-global-options
                                   (app-global-options app)))
      (make-parser-invocation app nil argv0 raw-argv parsed-action
                              resolved-global-options
                              nil
                              parsed-positionals))))

