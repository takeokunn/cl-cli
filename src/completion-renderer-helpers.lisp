(in-package :cl-cli)

(defun %completion-dynamic-option-alist (app)
  "Alist of (option-token . key-name) for every visible dynamic option in APP.

Covers global options and the options of every command (including nested
subcommands), so a flat completer -- powershell, nushell, elvish -- can shell
out to `app __complete KEY` when the word before the cursor is a dynamic option.
A token that appears on two options resolves to whichever comes first, the same
single-pool ambiguity the flat completers already accept for their candidate
lists. KEY-NAME is the downcased option key, matching RENDER-COMPLETE-REPLY."
  (labels ((collect-command-options (commands)
             (let (specs)
               (labels ((walk (items)
                          (dolist (command items)
                            (dolist (option (command-options command))
                              (push option specs))
                            (walk (command-subcommands command)))))
                 (walk commands)
                 (nreverse specs)))))
    (let ((specs (collect-command-options (app-commands app)))
          (alist nil))
      (dolist (option (reverse (app-global-options app)))
        (push option specs))
      (dolist (option specs (nreverse alist))
        (when (and (option-complete option)
                   (not (option-hidden-p option)))
          (let ((key (string-downcase (symbol-name (option-key option)))))
            (dolist (name (%completion-recognized-option-names option))
              (push (cons (option-token-display-name name) key) alist))))))))

(defun %completion-zsh-option-value-case-body (options &key attached-p)
  (with-output-to-string (out)
    (dolist (option options)
      (unless (option-hidden-p option)
        (let ((candidates (%completion-option-candidates option))
              (hint (option-value-hint option))
              (dynamic-p (and (option-complete option) t)))
          (when (or candidates (member hint '(:file :dir)) dynamic-p)
            (format out "      ~A)~%"
                    (%completion-case-labels
                     (%completion-option-token-patterns option :attached-p attached-p)))
            (cond
              (candidates
               (write-string (%completion-zsh-option-candidate-body candidates) out))
              (dynamic-p
               (format out "        local comp_value~%")
               (format out "        while IFS=$'\\t' read -r comp_value _; do~%")
               (format out "          [[ -n \"$comp_value\" && \"$comp_value\" == \"$current_word\"* ]] && compadd -- \"$comp_value\"~%")
               (format out "        done < <(\"${words[1]}\" __complete ~A \"$current_word\" 2>/dev/null)~%"
                       (string-downcase (symbol-name (option-key option)))))
              ((eq hint :dir)
               (format out "        _files -/~%"))
              ((eq hint :file)
               (format out "        _files~%")))
            (format out "        return 0~%")
            (format out "        ;;~%")))))))

(defun %completion-zsh-value-case-body (options)
  (%completion-zsh-option-value-case-body options :attached-p nil))

(defun %completion-zsh-attached-value-case-body (options)
  (%completion-zsh-option-value-case-body options :attached-p t))

(defun %completion-command-option-tokens (app command)
  (append (%completion-visible-option-tokens (app-global-options app))
          (when command
            (%completion-visible-option-tokens (command-options command)))
          (%completion-option-tokens-for-specs (built-in-option-specs app))))

(defun %completion-zsh-command-specs (app)
  (let (specs)
    (dolist (command (%completion-visible-commands app) (nreverse specs))
      (push (format nil "~A:~A"
                    (%completion-zsh-describe-field (command-name command))
                    (%completion-zsh-describe-field (command-description command)))
            specs)
      (dolist (alias (command-aliases command))
        (push (format nil "~A:alias for ~A"
                      (%completion-zsh-describe-field alias)
                      (%completion-zsh-describe-field (command-name command)))
              specs)))))

(defun %completion-zsh-command-specs-source (app)
  (%completion-zsh-assignment-source "command_specs"
                                     (%completion-zsh-command-specs app)))

(defun %completion-zsh-assignment-source (variable-name values)
  (format nil "  ~A=(~{~A~^ ~})~%"
          variable-name
          (mapcar #'%completion-shell-quote values)))

(defun %completion-zsh-option-placeholder (option)
  (or (option-value-name option)
      "value"))

(defun %completion-zsh-arguments-field (value)
  "Return VALUE safe for zsh `_arguments` bracket/placeholder fields."
  (with-output-to-string (out)
    (loop for char across (%completion-control-safe-string value)
          do (write-char (if (find char "[]:\\")
                             #\Space
                             char)
                         out))))

(defun %completion-zsh-option-spec (option name)
  (let* ((token (option-token-display-name name))
         (kind (option-kind option)))
    (format nil "~A[~A]~A"
            token
            (%completion-zsh-arguments-field
             (or (option-description option)
                 token))
            (case kind
              ((:value :key-value)
               (format nil ":~A:"
                       (%completion-zsh-arguments-field
                        (%completion-zsh-option-placeholder option))))
              (:optional-value
               (if (option-consume-optional-value-p option)
                   (format nil "::~A:"
                           (%completion-zsh-arguments-field
                            (%completion-zsh-option-placeholder option)))
                   ""))
              (otherwise "")))))

(defun %completion-zsh-option-specs-for-options (options)
  (%completion-option-items-for-options
   options
   #'%completion-recognized-option-names
   #'%completion-zsh-option-spec))

(defun %completion-zsh-option-specs-for-specs (options)
  (%completion-option-items-for-specs
   options
   #'%completion-recognized-option-names
   #'%completion-zsh-option-spec))

(defun %completion-zsh-built-in-option-specs (app)
  (%completion-zsh-option-specs-for-specs (built-in-option-specs app)))

(defun %completion-zsh-option-specs-source (options variable-name &key app)
  (%completion-zsh-assignment-source
   variable-name
   (append (%completion-zsh-option-specs-for-options options)
           (when app
             (%completion-zsh-built-in-option-specs app)))))

(defun %completion-zsh-option-candidate-body (candidates)
  (if (some #'cdr candidates)
      (with-output-to-string (out)
        (format out "        local -a value_candidates~%")
        (format out "        value_candidates=(~%")
        (dolist (candidate candidates)
          (format out "          ~A~%"
                  (%completion-shell-quote
                   (format nil "~A:~A"
                           (car candidate)
                           (%completion-zsh-describe-field
                            (or (cdr candidate) ""))))))
        (format out "        )~%")
        (format out "        _describe 'values' value_candidates~%"))
      (format nil "        compadd -Q -S '' -- ~{~A~^ ~}~%"
              (mapcar #'%completion-shell-quote
                      (mapcar #'car candidates)))))

(defun %completion-fish-option-arguments (option &key condition)
  (with-output-to-string (out)
    (dolist (name (option-names option))
      (if (= (length name) 1)
          (format out " -s ~A" name)
          (format out " -l ~A" name)))
    (dolist (name (option-negated-names option))
      (format out " -l ~A" name))
    (when condition
      (format out " -n ~A"
              (%completion-shell-quote condition)))
    (let ((kind (option-kind option)))
      (when (member kind '(:value :optional-value :key-value))
        (format out " -r")
        ;; An option with an explicit candidate set completes only those values;
        ;; add -f so fish does not also fall back to file completion (a file path
        ;; is not one of the allowed values).
        (when (%completion-option-candidates option)
          (format out " -f")))
      (when (member kind '(:flag :boolean :count))
        (format out " -f")))
    (when (option-description option)
      (format out " -d ~A"
              (%completion-shell-quote (option-description option))))))

(defun %completion-fish-dynamic-command (app option)
  (format nil "(command ~A __complete ~A (commandline -ct))"
          (%completion-shell-quote (app-name app))
          (string-downcase (symbol-name (option-key option)))))

(defun %completion-fish-option-candidate-lines (app option arguments stream)
  (let ((candidates (%completion-option-candidates option)))
    (if (some #'cdr candidates)
        (dolist (candidate candidates)
          (format stream "complete -c ~A~A -a ~A~@[ -d ~A~]~%"
                  (%completion-shell-quote (app-name app))
                  arguments
                  (%completion-shell-quote (car candidate))
                  (and (cdr candidate)
                       (%completion-shell-quote (cdr candidate)))))
        (cond
          (candidates
           (format stream "complete -c ~A~A -a ~A~%"
                   (%completion-shell-quote (app-name app))
                   arguments
                   (%completion-shell-quote
                    (%completion-space-joined
                     (%completion-option-candidate-values option)))))
          ;; A :complete function is queried at runtime: fish passes the current
          ;; token to `app __complete KEY ...` and offers the lines it prints.
          ((option-complete option)
           (format stream "complete -c ~A~A -f -a ~A~%"
                   (%completion-shell-quote (app-name app))
                   arguments
                   (%completion-shell-quote
                    (%completion-fish-dynamic-command app option))))
          ;; A :dir hint completes directories only (-f suppresses fish's default
          ;; file fallback); a :file hint / plain value option keeps that default.
          ((eq (option-value-hint option) :dir)
           (format stream "complete -c ~A~A -f -a '(__fish_complete_directories)'~%"
                   (%completion-shell-quote (app-name app))
                   arguments))
          (t
           (format stream "complete -c ~A~A~%"
                   (%completion-shell-quote (app-name app))
                   arguments))))))

(defun %render-fish-option-lines (app options condition stream)
  (dolist (option options)
    (unless (option-hidden-p option)
      (let ((arguments (%completion-fish-option-arguments option
                                                           :condition condition)))
        (%completion-fish-option-candidate-lines app option arguments stream)))))
