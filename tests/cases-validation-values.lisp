(in-package :cl-cli/tests)

(describe-sequential "validation values"
  (it "applies environment defaults before literal defaults"
    (let ((count (value-option "count"
                               :env-var "COUNT"
                               :default "1")))
      (with-parsed-argv-with-environment-variable-reader
          (inv (make-app :name "demo" :global-options (list count))
               '("demo")
               (lambda (name)
                 (declare (ignore name))
                 "3"))
        (expect (string= (option-value inv :count) "3")))))

  (it "prefers cli values over environment defaults"
    (let ((count (value-option "count"
                               :env-var "COUNT"
                               :default "1")))
      (with-parsed-argv-with-environment-variable-reader
          (inv (make-app :name "demo" :global-options (list count))
               '("demo" "--count" "9")
               (lambda (name)
                 (declare (ignore name))
                 "3"))
        (expect (string= (option-value inv :count) "9")))))

  (it "uses the option parser for environment defaults"
    (let ((count (value-option "count"
                               :env-vars '("PRIMARY_COUNT" "FALLBACK_COUNT")
                               :parser #'parse-integer)))
      (with-parsed-argv-with-environment-variable-reader
          (inv (make-app :name "demo" :global-options (list count))
               '("demo")
               (lambda (name)
                 (cond
                   ((string= name "PRIMARY_COUNT") nil)
                   ((string= name "FALLBACK_COUNT") "42")
                   (t nil))))
        (expect (= (option-value inv :count) 42)))))

  (it "uses the option parser for string defaults"
    (let ((count (value-option "count"
                               :default "42"
                               :parser #'parse-integer)))
      (with-parsed-argv (inv (make-app :name "demo" :global-options (list count))
                             '("demo"))
        (expect (= (option-value inv :count) 42)))))

  (it "uses the option parser for repeated string defaults"
    (let ((ports (value-option "port"
                               :multiple-p t
                               :default '("8080" "9090")
                               :parser #'parse-integer)))
      (with-parsed-argv (inv (make-app :name "demo" :global-options (list ports))
                             '("demo"))
        (expect (equal (option-value inv :port) '(8080 9090))))))

  (it "accumulates repeated value options in order"
    (let ((include (value-option "include"
                                 :short #\I
                                 :multiple-p t)))
      (with-parsed-argv (inv (make-app :name "demo"
                                       :global-options (list include))
                             '("demo" "-I" "src" "--include=tests" "-Ilib"))
        (expect (equal (option-value inv :include)
                       '("src" "tests" "lib"))))))

  (it "uses list defaults without nesting for repeated values"
    (let ((include (value-option "include"
                                 :multiple-p t
                                 :default '("src" "tests"))))
      (with-parsed-argv (inv (make-app :name "demo"
                                       :global-options (list include))
                             '("demo"))
        (expect (equal (option-value inv :include)
                       '("src" "tests"))))))

  (it "rejects repeated value options on flag-like kinds"
    (signals-invalid-specification
      (make-option :name "verbose"
                   :kind :flag
                   :multiple-p t)
      (make-option :name "threads"
                   :kind :boolean
                   :multiple-p t)))

  (it "restricts values to declared choices"
    (let ((mode (value-option "mode"
                              :choices '("dev" "prod"))))
      (signals cli-invalid-option-value
        (with-parsed-argv (inv (make-app :name "demo" :global-options (list mode))
                               '("demo" "--mode" "staging"))
          inv)))))
