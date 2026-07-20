(in-package :cl-cli/tests)

(defun required-if-app ()
  (make-app :name "tool"
            :global-options (list (make-option :name "profile" :kind :value)
                                  (make-option :name "config" :kind :value
                                               :required-if '(:profile)))))

(defun required-unless-app ()
  (make-app :name "tool"
            :global-options (list (make-option :name "token" :kind :value)
                                  (make-option :name "user" :kind :value
                                               :required-unless '(:token)))))

(describe-sequential "conditional requirements"
  (it "requires an option when its trigger is present"
    (signals cli-missing-option-value
      (parse-argv (required-if-app) '("tool" "--profile" "dev"))))

  (it "accepts the option when supplied alongside its trigger"
    (with-parsed-argv (inv (required-if-app) '("tool" "--profile" "dev" "--config" "c"))
      (expect (string= (option-value inv :config) "c"))))

  (it "does not require the option when the trigger is absent"
    (with-parsed-argv (inv (required-if-app) '("tool"))
      (expect (null (option-value inv :config)))))

  (it "names the trigger in the required-if error"
    (caught-signal= (cli-missing-option-value condition)
        (parse-argv (required-if-app) '("tool" "--profile" "dev"))
      (:searches cli-error-message "required when" "--profile")))

  (it "requires the option when no alternative is present"
    (signals cli-missing-option-value
      (parse-argv (required-unless-app) '("tool"))))

  (it "does not require the option when an alternative is present"
    (with-parsed-argv (inv (required-unless-app) '("tool" "--token" "t"))
      (expect (null (option-value inv :user)))))

  (it "accepts the option itself under required-unless"
    (with-parsed-argv (inv (required-unless-app) '("tool" "--user" "u"))
      (expect (string= (option-value inv :user) "u"))))

  (it "renders the conditions in help"
    (with-app-help-text (text (required-if-app))
      (assert-searches text "required if: --profile")))

  (it "rejects a required-if target that does not exist"
    (signals-invalid-specification
      (make-app :name "tool"
                :global-options (list (make-option :name "config" :kind :value
                                                   :required-if '(:nope)))))))
