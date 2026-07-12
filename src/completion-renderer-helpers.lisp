(in-package :cl-cli)

(defun %completion-zsh-option-value-case-body (options &key attached-p)
  (with-output-to-string (out)
    (dolist (option options)
      (unless (option-hidden-p option)
        (let ((candidates (%completion-option-candidates option)))
          (when candidates
            (let ((labels (%completion-option-value-patterns option
                                                             :attached-p attached-p)))
              (format out "      ~A)~%" (%completion-case-labels labels))
              (write-string (%completion-zsh-option-candidate-body candidates)
                           out)
              (format out "        return 0~%")
              (format out "        ;;~%"))))))))

(defun %completion-command-option-tokens (app command)
  (append (%completion-visible-option-tokens (app-global-options app))
          (when command
            (%completion-visible-option-tokens (command-options command)))
          (%completion-option-tokens-for-specs (built-in-option-specs app))))

(defun %completion-zsh-command-specs (app)
  (loop for command in (%completion-visible-commands app)
        append (cons (format nil "~A:~A"
                             (command-name command)
                             (or (command-description command) ""))
                     (loop for alias in (command-aliases command)
                           collect (format nil "~A:alias for ~A"
                                           alias
                                           (command-name command))))))

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

(defun %completion-zsh-option-spec (option name)
  (let* ((token (option-token-display-name name))
         (kind (option-kind option)))
    (format nil "~A[~A]~A"
            token
            (or (option-description option)
                token)
            (case kind
              (:value
               (format nil ":~A:"
                       (%completion-zsh-option-placeholder option)))
              (:optional-value
               (if (option-consume-optional-value-p option)
                   (format nil "::~A:"
                           (%completion-zsh-option-placeholder option))
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
                           (or (cdr candidate) "")))))
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
      (when (member kind '(:value :optional-value))
        (format out " -r"))
      (when (member kind '(:flag :boolean))
        (format out " -f")))
    (when (option-description option)
      (format out " -d ~A"
              (%completion-shell-quote (option-description option))))))

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
        (format stream "complete -c ~A~A~@[ -a ~A~]~%"
                (%completion-shell-quote (app-name app))
                arguments
                (and candidates
                     (%completion-shell-quote
                      (%completion-space-joined
                       (%completion-option-candidate-values option))))))))
