(in-package :cl-cli/tests)

(deftest-queries normalized-requires-relations
    ((make-option-relations-rulebase
      (list (make-option :name "profile"
                         :aliases '("p")
                         :kind :value)
            (make-option :name "config"
                         :kind :value
                         :requires '("p")))))
  ("resolves alias dependencies to canonical keys"
   (requires :config ?dependency)
   :ordered
   (((?dependency . :profile))))
   ("does not attach dependencies to unrelated options"
    (requires :profile ?dependency)
    :fails))

(deftest-queries normalized-conflict-relations
    ((make-option-relations-rulebase
      (list (make-option :name "internal-token"
                         :kind :value
                         :hidden-p t)
            (make-option :name "config"
                         :kind :value
                         :conflicts-with '(:internal-token)))))
  ("retains conflicts against hidden targets"
   (conflicts :config ?target)
   :ordered
   (((?target . :internal-token))))
  ("tracks which options are hidden"
   (hidden :internal-token)
   :succeeds))

(describe-sequential "validation relations"
  (it "requires dependent options"
    (with-caught-signal-from-argv
        ((cli-missing-dependent-option condition)
         (app (make-app :name "demo"
                        :global-options (list (make-option :name "profile"
                                                           :kind :value)
                                              (make-option :name "config"
                                                           :kind :value
                                                           :requires '(:profile))))
              '("demo" "--config" "dev.toml")))
      (:eq cli-missing-dependent-option-name :config)
      (:eq cli-missing-dependent-option-dependency :profile)
      (:searches cli-error-message "Option --config requires --profile.")))

  (it "requires respect environment defaults"
    (with-parsed-argv-with-environment-variable-reader
        (inv (make-app :name "demo"
                       :global-options (list (make-option :name "profile"
                                                          :kind :value
                                                          :env-var "APP_PROFILE")
                                             (make-option :name "config"
                                                          :kind :value
                                                          :requires '("profile"))))
             '("demo" "--config" "dev.toml")
             (lambda (name)
               (if (string= name "APP_PROFILE")
                   "dev"
                   nil)))
      (expect (string= (option-value inv :profile) "dev"))
      (expect (string= (option-value inv :config) "dev.toml"))))

  (it "requires hidden target without leaking its name"
    (with-caught-signal-from-argv
        ((cli-missing-dependent-option condition)
         (app (make-app :name "demo"
                        :global-options (list (make-option :name "internal-token"
                                                           :kind :value
                                                           :hidden-p t)
                                              (make-option :name "config"
                                                           :kind :value
                                                           :requires '(:internal-token))))
              '("demo" "--config" "dev.toml")))
      (:eq cli-missing-dependent-option-name :config)
      (:eq cli-missing-dependent-option-dependency :internal-token)
      (:searches cli-error-message "Option --config requires a hidden option.")
      (:not-searches cli-error-message "--internal-token")))

  (it "detects conflicting options"
    (with-caught-signal-from-argv
        ((cli-conflicting-options condition)
         (app (make-app :name "demo"
                        :global-options (list (make-option :name "token"
                                                           :kind :value)
                                              (make-option :name "password"
                                                           :kind :value
                                                           :conflicts-with '(:token))))
              '("demo" "--token" "abc" "--password" "secret")))
      (:eq cli-conflicting-options-left-option :password)
      (:eq cli-conflicting-options-right-option :token)
      (:searches cli-error-message "Option --password conflicts with --token.")))

  (it "detects conflicts with hidden target without leaking its name"
    (with-caught-signal-from-argv
        ((cli-conflicting-options condition)
         (app (make-app :name "demo"
                        :global-options (list (make-option :name "internal-token"
                                                           :kind :value
                                                           :hidden-p t)
                                              (make-option :name "config"
                                                           :kind :value
                                                           :conflicts-with '(:internal-token))))
              '("demo" "--config" "dev.toml" "--internal-token" "secret")))
      (:eq cli-conflicting-options-left-option :config)
      (:eq cli-conflicting-options-right-option :internal-token)
      (:searches cli-error-message "Option --config conflicts with a hidden option.")
      (:not-searches cli-error-message "--internal-token")))

  (it "rejects unknown relation targets"
    (let* ((config (make-option :name "config"
                                :kind :value
                                :requires '(:profile))))
      (signals-invalid-specification
        (make-app :name "demo"
                  :global-options (list config)))))

  (it "rejects self references"
    (signals-invalid-specification
      (make-app :name "demo"
                :global-options (list (make-option :name "config"
                                                   :kind :value
                                                   :requires '(:config)))))
    (signals-invalid-specification
      (make-app :name "demo"
                :global-options (list (make-option :name "token"
                                                   :kind :value
                                                   :conflicts-with '("token"))))))

  (it "resolves alias targets"
    (with-parsed-argv (inv (make-app :name "demo"
                                     :global-options (list (make-option :name "profile"
                                                                        :aliases '("p")
                                                                        :kind :value)
                                                           (make-option :name "config"
                                                                        :kind :value
                                                                        :requires '("p"))))
                           '("demo" "--config" "dev.toml" "--p" "dev"))
      (expect (string= (option-value inv :profile) "dev"))
      (expect (string= (option-value inv :config) "dev.toml"))))

  (it "enforces at most one option from an exclusive group"
    (let ((app (make-app :name "fmt"
                         :global-options (exclusive-group
                                          (make-option :name "json" :kind :flag)
                                          (make-option :name "yaml" :kind :flag)
                                          (make-option :name "table" :kind :flag)))))
      (with-parsed-argv (inv app '("fmt" "--json"))
        (expect (option-value inv :json)))
      (with-parsed-argv (inv app '("fmt"))
        (expect (null (option-value inv :json))))
      (signals cli-conflicting-options
        (parse-argv app '("fmt" "--json" "--yaml")))
      (signals cli-conflicting-options
        (parse-argv app '("fmt" "--table" "--json")))))

  (it "keeps conflicts declared outside an exclusive group"
    (let ((app (make-app :name "demo"
                         :global-options
                         (cons (make-option :name "quiet" :kind :flag
                                            :conflicts-with '(:verbose))
                               (exclusive-group
                                (make-option :name "verbose" :kind :flag)
                                (make-option :name "silent" :kind :flag))))))
      (signals cli-conflicting-options
        (parse-argv app '("demo" "--verbose" "--silent")))
      (signals cli-conflicting-options
        (parse-argv app '("demo" "--quiet" "--verbose")))))

  (it "requires exactly one option from a required exclusive group"
    (let ((app (make-app :name "fmt"
                         :global-options (required-exclusive-group
                                          (make-option :name "json" :kind :flag)
                                          (make-option :name "yaml" :kind :flag)
                                          (make-option :name "table" :kind :flag)))))
      (with-parsed-argv (inv app '("fmt" "--yaml"))
        (expect (option-value inv :yaml)))
      (caught-signal= (cli-missing-option-value condition)
          (parse-argv app '("fmt"))
        (:searches cli-error-message
                   "Exactly one of --json, --yaml, --table is required."))
      (signals cli-conflicting-options
        (parse-argv app '("fmt" "--json" "--table")))))

  (it "applies exclusive groups declared on command options"
    (let ((app (make-app :name "tool"
                         :commands (list (make-command
                                          :name "export"
                                          :options (required-exclusive-group
                                                    (make-option :name "json" :kind :flag)
                                                    (make-option :name "yaml" :kind :flag)))))))
      (with-parsed-argv (inv app '("tool" "export" "--json"))
        (expect (option-value inv :json)))
      (signals cli-missing-option-value
        (parse-argv app '("tool" "export")))
      (signals cli-conflicting-options
        (parse-argv app '("tool" "export" "--json" "--yaml"))))))
