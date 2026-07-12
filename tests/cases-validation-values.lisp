(in-package :cl-cli/tests)

(deftest env-var-defaults-are-applied-before-literal-defaults
  (let ((count (value-option "count"
                             :env-var "COUNT"
                             :default "1")))
    (with-parsed-argv-with-environment-variable-reader
        (inv (make-app :name "demo" :global-options (list count))
             '("demo")
             (lambda (name)
               (declare (ignore name))
               "3"))
      (is (string= (option-value inv :count) "3"))))
  t)

(deftest cli-values-win-over-env-var-defaults
  (let ((count (value-option "count"
                             :env-var "COUNT"
                             :default "1")))
    (with-parsed-argv-with-environment-variable-reader
        (inv (make-app :name "demo" :global-options (list count))
             '("demo" "--count" "9")
             (lambda (name)
               (declare (ignore name))
               "3"))
      (is (string= (option-value inv :count) "9"))))
  t)

(deftest env-var-defaults-use-option-parser
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
      (is (= (option-value inv :count) 42))))
  t)

(deftest string-defaults-use-option-parser
  (let ((count (value-option "count"
                             :default "42"
                             :parser #'parse-integer)))
    (with-parsed-argv (inv (make-app :name "demo" :global-options (list count))
                          '("demo"))
      (is (= (option-value inv :count) 42))))
  t)

(deftest repeated-string-defaults-use-option-parser
  (let ((ports (value-option "port"
                             :multiple-p t
                             :default '("8080" "9090")
                             :parser #'parse-integer)))
    (with-parsed-argv (inv (make-app :name "demo" :global-options (list ports))
                          '("demo"))
      (is (equal (option-value inv :port) '(8080 9090)))))
  t)

(deftest repeated-value-options-accumulate-in-order
  (let ((include (value-option "include"
                               :short #\I
                               :multiple-p t)))
    (with-parsed-argv (inv (make-app :name "demo"
                                     :global-options (list include))
                          '("demo" "-I" "src" "--include=tests" "-Ilib"))
      (is (equal (option-value inv :include)
                 '("src" "tests" "lib")))))
  t)

(deftest repeated-value-options-use-list-defaults-without-nesting
  (let ((include (value-option "include"
                               :multiple-p t
                               :default '("src" "tests"))))
    (with-parsed-argv (inv (make-app :name "demo"
                                     :global-options (list include))
                          '("demo"))
      (is (equal (option-value inv :include)
                 '("src" "tests")))))
  t)

(deftest repeated-value-options-reject-flag-like-kinds
  (signals-invalid-specification
    (flag-option "verbose")
    (make-option :name "threads"
                 :kind :boolean
                 :multiple-p t))
  t)

(deftest option-choices-restrict-allowed-values
  (let ((mode (value-option "mode"
                            :choices '("dev" "prod"))))
    (signals cli-invalid-option-value
      (with-parsed-argv (inv (make-app :name "demo" :global-options (list mode))
                            '("demo" "--mode" "staging"))
        inv)))
  t)
