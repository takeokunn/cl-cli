(in-package :cl-cli/tests)

(describe-sequential "choice suggestions"
  (it "suggests the nearest option choice"
    (let ((app (make-app :name "tool"
                         :global-options (list (make-option :name "mode" :kind :value
                                                            :choices '("dev" "prod"))))))
      (caught-signal= (cli-invalid-option-value condition)
          (parse-argv app '("tool" "--mode" "prd"))
        (:searches cli-error-message "Did you mean" "prod"))))

  (it "suggests the nearest positional choice"
    (let ((app (make-app :name "tool"
                         :positionals (list (make-positional :key :env
                                                            :choices '("dev" "prod"))))))
      (caught-signal= (cli-invalid-positional-value condition)
          (parse-argv app '("tool" "prd"))
        (:searches cli-error-message "Did you mean" "prod")))))
