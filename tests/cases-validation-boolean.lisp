(in-package :cl-cli/tests)

(deftest boolean-option-supports-positive-and-negated-long-forms
  (let* ((threads (make-option :name "threads"
                               :short #\t
                               :kind :boolean))
         (app (make-app :name "demo"
                        :global-options (list threads))))
    (is (eq (option-value (parse-argv app '("demo" "--threads")) :threads) t))
    (is (eq (option-value (parse-argv app '("demo" "--no-threads")) :threads) nil))
    (is (eq (option-value (parse-argv app '("demo" "-t")) :threads) t)))
  t)

(deftest boolean-option-rejects-attached-values
  (let* ((threads (make-option :name "threads"
                               :kind :boolean))
         (app (make-app :name "demo"
                        :global-options (list threads))))
    (signals cli-usage-error
      (parse-argv app '("demo" "--threads=false"))))
  t)

(deftest boolean-option-parser-rejects-invalid-designators
  (let ((threads (make-option :name "threads"
                              :kind :boolean)))
    (is (eq (funcall (option-parser threads) "t") t))
    (is (eq (funcall (option-parser threads) "nil") nil))
    (signals cli-invalid-option-value
      (funcall (option-parser threads) "maybe")))
  t)

(deftest boolean-option-parses-environment-defaults
  (let ((threads (make-option :name "threads"
                              :kind :boolean
                              :env-var "CC_THREADS")))
    (with-parsed-argv-with-environment-variable-reader
        (inv (make-app :name "demo"
                       :global-options (list threads))
             '("demo")
             (lambda (name)
               (if (string= name "CC_THREADS")
                   "t"
                   nil)))
      (is (eq (option-value inv :threads) t))))
  t)

(deftest boolean-option-rejects-invalid-environment-values
  (let* ((threads (make-option :name "threads"
                               :kind :boolean
                               :env-var "CC_THREADS"))
         (app (make-app :name "demo"
                        :global-options (list threads))))
    (with-environment-variable-reader
        ((lambda (name)
           (if (string= name "CC_THREADS")
               "maybe"
               nil)))
      (signals cli-invalid-option-value
        (parse-argv app '("demo")))))
  t)
