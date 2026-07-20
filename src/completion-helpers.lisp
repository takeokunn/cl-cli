(in-package :cl-cli)

(defun %completion-visible-commands (app)
  (remove-if #'command-hidden-p (app-commands app)))

(defun %completion-function-name (app)
  ;; The result is emitted as a raw shell function name (e.g. `_demo_completion()`
  ;; and `complete -F ...`), which cannot be quoted. App names are already
  ;; validated to a safe identifier set, but map every non-word character to `_`
  ;; anyway so this never produces a name that could break the function header.
  (format nil "_~A_completion"
          (map 'string
               (lambda (char)
                 (if (or (alphanumericp char) (char= char #\_))
                     char
                     #\_))
               (app-name app))))

(defun %completion-option-items-for-specs (options names-fn item-fn)
  (let (items)
    (dolist (option options (nreverse items))
      (dolist (name (funcall names-fn option))
        (push (funcall item-fn option name) items)))))

(defun %completion-option-tokens-for-specs (options)
  (%completion-option-items-for-specs
   options
   #'%completion-all-option-names
   (lambda (option name)
     (declare (ignore option))
     (option-token-display-name name))))

(defun %completion-option-items-for-options (options names-fn item-fn)
  (%completion-option-items-for-specs
   (remove-if #'option-hidden-p options)
   names-fn
   item-fn))

(defun %completion-visible-option-tokens (options)
  (%completion-option-items-for-options
   options
   #'%completion-all-option-names
   (lambda (option name)
     (declare (ignore option))
     (option-token-display-name name))))

(defun %completion-command-names (command)
  (cons (command-name command)
        (command-aliases command)))

(defun %completion-all-option-names (option)
  (append (option-names option)
          (option-negated-names option)))

(defun %completion-recognized-option-names (option)
  (remove-duplicates
   (%completion-all-option-names option)
   :test #'string=))

(defun %completion-visible-command-tokens (app)
  (let (tokens)
    (dolist (command (%completion-visible-commands app) (nreverse tokens))
      (push (command-name command) tokens)
      (dolist (alias (command-aliases command))
        (push alias tokens)))))

(defun %completion-control-safe-string (value)
  "Return VALUE as a single printable completion protocol field."
  (let ((string (if value (princ-to-string value) "")))
    (with-output-to-string (out)
      (loop for char across string
            for code = (char-code char)
            do (cond
                 ((or (char= char #\Newline)
                      (char= char #\Return)
                      (char= char #\Tab))
                  (write-char #\Space out))
                 ((or (< code 32)
                      (= code 127)
                      (and (>= code 128) (< code 160)))
                  nil)
                 (t
                  (write-char char out)))))))

(defun %completion-zsh-describe-field (value)
  "Return VALUE as one safe `_describe` NAME or DESCRIPTION field."
  (with-output-to-string (out)
    (loop for char across (%completion-control-safe-string value)
          do (write-char (if (char= char #\:) #\Space char) out))))

(defun %completion-shell-quote (string)
  (with-output-to-string (out)
    (write-char #\' out)
    (loop for char across (%completion-control-safe-string string)
          do (if (char= char #\')
                 (write-string "'\"'\"'" out)
                 (write-char char out)))
    (write-char #\' out)))

(defun %completion-space-joined (strings)
  (format nil "~{~A~^ ~}"
          (remove-duplicates strings :test #'string=)))

(defun %completion-bash-array-literal (strings)
  (format nil "(~{~A~^ ~})"
          (mapcar #'%completion-shell-quote
                  (remove-duplicates strings :test #'string=))))

(defun %completion-case-labels (strings)
  (format nil "~{~A~^|~}"
          (mapcar #'%completion-shell-quote strings)))

(defun %completion-option-candidates (option)
  (or (option-completion-candidates option)
      (mapcar (lambda (choice)
                (cons choice nil))
              (option-choices option))))

(defun %completion-option-candidate-values (option)
  (mapcar #'car (%completion-option-candidates option)))

(defun %completion-positional-candidates (positional)
  (or (positional-spec-completion-candidates positional)
      (mapcar (lambda (choice) (cons choice nil))
              (positional-spec-choices positional))))

(defun %completion-positional-candidate-values (positional)
  (mapcar #'car (%completion-positional-candidates positional)))

(defun %completion-app-positional-values (app)
  (let (values)
    (dolist (positional (app-positionals app) (nreverse values))
      (dolist (value (%completion-positional-candidate-values positional))
        (push value values)))))

(defun %completion-command-positional-values (command)
  (let (values)
    (dolist (positional (command-positionals command) (nreverse values))
      (dolist (value (%completion-positional-candidate-values positional))
        (push value values)))))

(defun %completion-positionals-hint-p (positionals hint)
  "True when any positional in POSITIONALS declares :value-hint HINT."
  (some (lambda (positional) (eq (positional-spec-value-hint positional) hint))
        positionals))

(defun %completion-app-positional-hint-p (app hint)
  (%completion-positionals-hint-p (app-positionals app) hint))

(defun %completion-command-positional-hint-p (command hint)
  (%completion-positionals-hint-p (command-positionals command) hint))

(defun %completion-option-value-source (option)
  (%completion-option-candidate-values option))

(defun %completion-option-token-patterns (option &key command-name attached-p)
  "Case-label patterns matching OPTION's tokens (optionally command-scoped)."
  (loop for name in (%completion-recognized-option-names option)
        for token = (option-token-display-name name)
        collect (if command-name
                    (format nil "~A:~A~A"
                            command-name
                            token
                            (if attached-p "=*" ""))
                    (format nil "~A~A"
                            token
                            (if attached-p "=*" "")))))

(defun %completion-option-value-patterns (option &key command-name attached-p)
  (when (%completion-option-candidates option)
    (%completion-option-token-patterns option
                                       :command-name command-name
                                       :attached-p attached-p)))

(defun %completion-option-scan-rules (options &key command-name)
  (with-output-to-string (out)
    (dolist (option options)
      (unless (option-hidden-p option)
        (let ((kind (option-kind option)))
          (when (or (eq kind :value)
                    (and (eq kind :optional-value)
                         (option-consume-optional-value-p option)))
            (let* ((value-source (%completion-option-value-source option))
                   (dir-hint-p (eq (option-value-hint option) :dir))
                   (dynamic-p (and (option-complete option) t))
                   ;; Emit a case for candidates, a :dir hint (explicit compgen
                   ;; -d), or a :complete function (runtime callback). A :file
                   ;; hint / plain value option instead falls through to `complete
                   ;; -o default` filename completion. An empty case label (`)`)
                   ;; is a bash syntax error, so nothing is emitted otherwise.
                   (emit-p (or value-source dir-hint-p dynamic-p))
                   (expect (if (eq kind :value)
                               "expect_value=1"
                               "expect_optional_value=1")))
              (when emit-p
                (format out "      ~A) ~A ;;~%"
                        (%completion-case-labels
                         (%completion-option-token-patterns option
                                                            :command-name command-name))
                        (cond
                          (dynamic-p
                           (format nil "~A comp_dynamic=~A" expect
                                   (%completion-shell-quote
                                    (string-downcase (symbol-name (option-key option))))))
                          (value-source (format nil "~A value_source=~A" expect
                                                (%completion-bash-array-literal value-source)))
                          (dir-hint-p (format nil "~A comp_dir=1" expect))))))))))))
