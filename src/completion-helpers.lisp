(in-package :cl-cli)

(defun %completion-visible-commands (app)
  (remove-if #'command-hidden-p (app-commands app)))

(defun %completion-option-items-for-specs (options names-fn item-fn)
  (loop for option in options append
        (loop for name in (funcall names-fn option)
              collect (funcall item-fn option name))))

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
  (loop for command in (%completion-visible-commands app)
        append (%completion-command-names command)))

(defun %completion-shell-quote (string)
  (with-output-to-string (out)
    (write-char #\' out)
    (loop for char across string
          do (if (char= char #\')
                 (write-string "'\"'\"'" out)
                 (write-char char out)))
    (write-char #\' out)))

(defun %completion-space-joined (strings)
  (format nil "~{~A~^ ~}"
          (remove-duplicates strings :test #'string=)))

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

(defun %completion-option-value-source (option)
  (let ((values (%completion-option-candidate-values option)))
    (and values
         (%completion-shell-quote
          (%completion-space-joined values)))))

(defun %completion-option-value-patterns (option &key command-name attached-p)
  (when (%completion-option-candidates option)
    (loop for name in (%completion-recognized-option-names option)
          for token = (option-token-display-name name)
          collect (if command-name
                      (format nil "~A:~A~A"
                              command-name
                              token
                              (if attached-p "=*" ""))
                      (format nil "~A~A"
                              token
                              (if attached-p "=*" ""))))))

(defun %completion-option-scan-rules (options &key command-name)
  (with-output-to-string (out)
    (dolist (option options)
      (unless (option-hidden-p option)
        (let ((kind (option-kind option)))
          (when (or (eq kind :value)
                    (and (eq kind :optional-value)
                         (option-consume-optional-value-p option)))
            (let ((labels (%completion-option-value-patterns option
                                                             :command-name command-name))
                  (value-source (%completion-option-value-source option)))
              (format out "      ~A) ~A ;;~%"
                      (%completion-case-labels labels)
                      (format nil "~A~@[ value_source=~A~]"
                              (if (eq kind :value)
                                  "expect_value=1"
                                  "expect_optional_value=1")
                              value-source)))))))))
