(in-package :cl-cli/tests)

(defun delimited-option-app (&rest option-args)
  (make-app :name "tool"
            :global-options (list (apply #'make-option :name "tags" :kind :value
                                         :value-delimiter #\, option-args))))

(describe-sequential "delimited values"
  (it "splits a single occurrence into a list"
    (with-parsed-argv (inv (delimited-option-app) '("tool" "--tags" "a,b,c"))
      (expect (equal (option-value inv :tags) '("a" "b" "c")))))

  (it "splits an attached value form"
    (with-parsed-argv (inv (delimited-option-app) '("tool" "--tags=a,b"))
      (expect (equal (option-value inv :tags) '("a" "b")))))

  (it "drops empty pieces from doubled or edge delimiters"
    (with-parsed-argv (inv (delimited-option-app) '("tool" "--tags" "a,,b,"))
      (expect (equal (option-value inv :tags) '("a" "b")))))

  (it "accumulates across occurrences"
    (with-parsed-argv (inv (delimited-option-app :multiple-p t)
                          '("tool" "--tags" "a,b" "--tags" "c"))
      (expect (equal (option-value inv :tags) '("a" "b" "c")))))

  (it "parses each piece with the declared type"
    (with-parsed-argv (inv (make-app
                            :name "tool"
                            :global-options (list (make-option :name "ports"
                                                               :kind :value
                                                               :type :integer
                                                               :value-delimiter #\,)))
                          '("tool" "--ports" "80,443,8080"))
      (expect (equal (option-value inv :ports) '(80 443 8080)))))

  (it "rejects an out-of-range piece under a typed delimiter"
    (signals cli-invalid-option-value
      (parse-argv (make-app
                   :name "tool"
                   :global-options (list (make-option :name "ports"
                                                      :kind :value
                                                      :type :integer
                                                      :min 1
                                                      :value-delimiter #\,)))
                  '("tool" "--ports" "80,0"))))

  (it "uses a list default when absent"
    (with-parsed-argv (inv (delimited-option-app :default '("x" "y"))
                          '("tool"))
      (expect (equal (option-value inv :tags) '("x" "y")))))

  (it "splits a string default when absent"
    (with-parsed-argv (inv (delimited-option-app :default "x,y,z")
                          '("tool"))
      (expect (equal (option-value inv :tags) '("x" "y" "z")))))

  (it "splits an environment-variable value"
    (with-parsed-argv-with-environment-variable-reader
        (inv (delimited-option-app :env-var "TAGS")
             '("tool")
             (lambda (name) (when (string= name "TAGS") "a,b,c")))
      (expect (equal (option-value inv :tags) '("a" "b" "c")))))

  (it "accepts a one-character string delimiter"
    (with-parsed-argv (inv (make-app
                            :name "tool"
                            :global-options (list (make-option :name "tags"
                                                               :kind :value
                                                               :value-delimiter ":")))
                          '("tool" "--tags" "a:b:c"))
      (expect (equal (option-value inv :tags) '("a" "b" "c")))))

  (it "surfaces the delimiter in help output"
    (with-app-help-text (text (delimited-option-app))
      (assert-searches text "list (delimited by ',')")))

  (it "rejects :value-delimiter on a flag option"
    (signals-invalid-specification
      (make-option :name "x" :kind :flag :value-delimiter #\,)))

  (it "rejects a multi-character delimiter"
    (signals-invalid-specification
      (make-option :name "x" :kind :value :value-delimiter ", "))))
