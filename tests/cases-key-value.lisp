(in-package :cl-cli/tests)

(defun key-value-app ()
  (make-app :name "cc"
            :global-options (list (make-option :name "define" :short #\D :kind :key-value
                                               :description "Define a macro."))))

(describe-sequential "key-value options"
  (it "accumulates separated pairs into an alist"
    (with-parsed-argv (inv (key-value-app) '("cc" "-D" "a=1" "-D" "b=2"))
      (expect (equal (option-value inv :define) '(("a" . "1") ("b" . "2"))))))

  (it "accepts an attached short form"
    (with-parsed-argv (inv (key-value-app) '("cc" "-Da=1"))
      (expect (equal (option-value inv :define) '(("a" . "1"))))))

  (it "accepts the long form"
    (with-parsed-argv (inv (key-value-app) '("cc" "--define" "x=y"))
      (expect (equal (option-value inv :define) '(("x" . "y"))))))

  (it "splits only on the first equals sign"
    (with-parsed-argv (inv (key-value-app) '("cc" "-D" "path=/a=b"))
      (expect (equal (option-value inv :define) '(("path" . "/a=b"))))))

  (it "records a bare key as value T"
    (with-parsed-argv (inv (key-value-app) '("cc" "-D" "NDEBUG"))
      (expect (equal (option-value inv :define) '(("NDEBUG" . t))))))

  (it "signals a missing value"
    (signals cli-missing-option-value
      (parse-argv (key-value-app) '("cc" "-D"))))

  (it "rejects combining :key-value with :multiple-p"
    (signals-invalid-specification
      (make-option :name "d" :kind :key-value :multiple-p t)))

  (it "shows the KEY=VALUE token in help"
    (with-app-help-text (text (key-value-app))
      (assert-searches text "--define" "<KEY=VALUE>")))

  (it "reports the kind in json"
    (let ((text (with-string-output (s) (render-json (key-value-app) s))))
      (assert-searches text "\"kind\":\"key-value\""))))
