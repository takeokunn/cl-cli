(in-package :cl-cli/tests)

(defun inclusive-app ()
  (make-app :name "tool"
            :global-options (inclusive-group
                             (make-option :name "host" :kind :value)
                             (make-option :name "port" :kind :value))))

(describe-sequential "inclusive group"
  (it "accepts none of the members"
    (with-parsed-argv (inv (inclusive-app) '("tool"))
      (expect (null (option-value inv :host)))
      (expect (null (option-value inv :port)))))

  (it "accepts all of the members"
    (with-parsed-argv (inv (inclusive-app) '("tool" "--host" "h" "--port" "5"))
      (expect (string= (option-value inv :host) "h"))
      (expect (string= (option-value inv :port) "5"))))

  (it "rejects some but not all of the members"
    (signals cli-missing-dependent-option
      (parse-argv (inclusive-app) '("tool" "--host" "h"))))

  (it "names the missing member in the error"
    (caught-signal= (cli-missing-dependent-option condition)
        (parse-argv (inclusive-app) '("tool" "--host" "h"))
      (:searches cli-error-message "must be used together" "--port")))

  (it "renders the group as all-or-none in help"
    (with-app-help-text (text (inclusive-app))
      (assert-searches text "all or none of:" "--host" "--port")))

  (it "does not add conflicts between members"
    ;; Supplying both must succeed (an exclusive group would reject it).
    (with-parsed-argv (inv (inclusive-app) '("tool" "--host" "h" "--port" "5"))
      (expect (string= (option-value inv :host) "h")))))
