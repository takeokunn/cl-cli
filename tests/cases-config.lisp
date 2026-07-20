(in-package :cl-cli/tests)

(defun config-app (&rest option-args)
  (make-app :name "tool"
            :global-options (list (apply #'make-option :name "mode" :kind :value
                                         option-args))))

(describe-sequential "config-backed defaults"
  (it "supplies a value from config when the option is absent"
    (let ((inv (parse-argv (config-app) '("tool") :config '(:mode "prod"))))
      (expect (string= (option-value inv :mode) "prod"))))

  (it "lets a CLI value override config"
    (let ((inv (parse-argv (config-app) '("tool" "--mode" "dev")
                           :config '(:mode "prod"))))
      (expect (string= (option-value inv :mode) "dev"))))

  (it "lets config override a literal default"
    (let ((inv (parse-argv (config-app :default "def") '("tool")
                           :config '(:mode "cfg"))))
      (expect (string= (option-value inv :mode) "cfg"))))

  (it "lets an environment variable override config"
    (with-environment-variable-reader
        ((lambda (name) (when (string= name "MODE") "from-env")))
      (let ((inv (parse-argv (config-app :env-var "MODE") '("tool")
                             :config '(:mode "from-config"))))
        (expect (string= (option-value inv :mode) "from-env")))))

  (it "coerces a string config value through the typed parser"
    (let ((inv (parse-argv (config-app :type :integer) '("tool")
                           :config '(:mode "5"))))
      (expect (eql (option-value inv :mode) 5))))

  (it "accepts an already-typed config value"
    (let ((inv (parse-argv (config-app :type :integer) '("tool")
                           :config '(:mode 5))))
      (expect (eql (option-value inv :mode) 5))))

  (it "splits a string config value for a delimited option"
    (let ((inv (parse-argv (make-app
                            :name "tool"
                            :global-options (list (make-option :name "tags"
                                                               :kind :value
                                                               :value-delimiter #\,)))
                           '("tool")
                           :config '(:tags "a,b,c"))))
      (expect (equal (option-value inv :tags) '("a" "b" "c")))))

  (it "accepts a list config value for a delimited option"
    (let ((inv (parse-argv (make-app
                            :name "tool"
                            :global-options (list (make-option :name "tags"
                                                               :kind :value
                                                               :value-delimiter #\,)))
                           '("tool")
                           :config '(:tags ("a" "b")))))
      (expect (equal (option-value inv :tags) '("a" "b")))))

  (it "treats a nil config value as present, overriding the default"
    (let ((inv (parse-argv (config-app :default "def") '("tool")
                           :config '(:mode nil))))
      (expect (null (option-value inv :mode)))
      (expect (member :mode (invocation-global-options inv)))))

  (it "falls back to the literal default when the config key is absent"
    (let ((inv (parse-argv (config-app :default "def") '("tool")
                           :config '(:other "x"))))
      (expect (string= (option-value inv :mode) "def"))))

  (it "supplies config for a command-scoped option"
    (let* ((app (make-app
                 :name "tool"
                 :commands (list (make-command
                                  :name "run"
                                  :options (list (make-option :name "level" :kind :value))
                                  :handler (lambda (inv) (declare (ignore inv)) 0)))))
           (inv (parse-argv app '("tool" "run") :config '(:level "high"))))
      (expect (string= (option-value inv :level) "high"))))

  (it "run-app forwards config to the handler"
    (let* ((seen nil)
           (app (make-app
                 :name "tool"
                 :global-options (list (make-option :name "mode" :kind :value))
                 :handler (lambda (inv) (setf seen (option-value inv :mode)) 0))))
      (run-app app :argv '("tool") :config '(:mode "prod")
               :stdout (make-string-output-stream))
      (expect (string= seen "prod")))))
