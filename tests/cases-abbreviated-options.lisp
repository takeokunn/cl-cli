(in-package :cl-cli/tests)

(defun abbrev-app (&key (allow t) (options nil))
  (make-app :name "tool"
            :allow-abbreviated-options allow
            :global-options
            (or options
                (list (make-option :name "verbose" :kind :flag)
                      (make-option :name "output" :kind :value)))))

(describe-sequential "abbreviated options"
  (it "resolves a unique long-option prefix"
    (with-parsed-argv (inv (abbrev-app) '("tool" "--verb"))
      (expect (eq (option-value inv :verbose) t))))

  (it "resolves an abbreviated value option with a separated value"
    (with-parsed-argv (inv (abbrev-app) '("tool" "--out" "main.o"))
      (expect (string= (option-value inv :output) "main.o"))))

  (it "resolves an abbreviated value option with an attached value"
    (with-parsed-argv (inv (abbrev-app) '("tool" "--out=main.o"))
      (expect (string= (option-value inv :output) "main.o"))))

  (it "prefers an exact match over a longer option sharing the prefix"
    (let ((app (abbrev-app :options (list (make-option :name "ver" :kind :flag)
                                          (make-option :name "verbose" :kind :flag)))))
      (with-parsed-argv (inv app '("tool" "--ver"))
        (expect (eq (option-value inv :ver) t))
        (expect (null (option-value inv :verbose))))))

  (it "signals an ambiguity when a prefix matches several options"
    (let ((app (abbrev-app :options (list (make-option :name "verbose" :kind :flag)
                                          (make-option :name "verify" :kind :flag)))))
      (caught-signal= (cli-unknown-option condition)
          (parse-argv app '("tool" "--ver"))
        (:searches cli-error-message "Ambiguous option --ver" "verbose" "verify"))))

  (it "abbreviates a built-in option too"
    (with-parsed-argv (inv (abbrev-app) '("tool" "--hel"))
      (expect (eq (invocation-action inv) :help))))

  (it "stays strict when abbreviation is disabled"
    (signals cli-unknown-option
      (parse-argv (abbrev-app :allow nil) '("tool" "--verb"))))

  (it "still rejects a prefix that matches nothing"
    (signals cli-unknown-option
      (parse-argv (abbrev-app) '("tool" "--zzz")))))
