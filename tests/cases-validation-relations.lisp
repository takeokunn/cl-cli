(in-package :cl-cli/tests)

(deftest option-requires-dependent-option
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
    (:searches cli-error-message "Option --config requires --profile."))
  t)

(deftest option-requires-respects-environment-defaults
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
    (is (string= (option-value inv :profile) "dev"))
    (is (string= (option-value inv :config) "dev.toml")))
  t)

(deftest option-requires-hidden-target-without-leaking-its-name
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
    (:not-searches cli-error-message "--internal-token"))
  t)

(deftest option-conflicts-with-other-option
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
    (:searches cli-error-message "Option --password conflicts with --token."))
  t)

(deftest option-conflicts-with-hidden-target-without-leaking-its-name
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
    (:not-searches cli-error-message "--internal-token"))
  t)

(deftest option-relations-reject-unknown-target
  (let* ((config (make-option :name "config"
                              :kind :value
                              :requires '(:profile))))
    (signals-invalid-specification
      (make-app :name "demo"
                :global-options (list config))))
  t)

(deftest option-relations-reject-self-reference
  (signals-invalid-specification
    (make-app :name "demo"
              :global-options (list (make-option :name "config"
                                                 :kind :value
                                                 :requires '(:config)))))
  (signals-invalid-specification
    (make-app :name "demo"
              :global-options (list (make-option :name "token"
                                                 :kind :value
                                                 :conflicts-with '("token")))))
  t)

(deftest option-relations-resolve-alias-targets
  (with-parsed-argv (inv (make-app :name "demo"
                                   :global-options (list (make-option :name "profile"
                                                                      :aliases '("p")
                                                                      :kind :value)
                                                         (make-option :name "config"
                                                                      :kind :value
                                                                      :requires '("p"))))
                         '("demo" "--config" "dev.toml" "--p" "dev"))
    (is (string= (option-value inv :profile) "dev"))
    (is (string= (option-value inv :config) "dev.toml")))
  t)
