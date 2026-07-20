(in-package :cl-cli/tests)

(defun variadic-app (count)
  (make-app :name "tool"
            :global-options (list (make-option :name "files" :short #\f
                                               :kind :value :value-count count))
            :positionals (list (make-positional :key :rest :rest-p t))))

(describe-sequential "variadic options"
  (it "greedily consumes one-or-more values until the next option"
    (with-parsed-argv (inv (variadic-app :+) '("tool" "--files" "a" "b" "c"))
      (expect (equal (option-value inv :files) '("a" "b" "c")))))

  (it "stops at the next option-like token"
    (with-parsed-argv (inv (make-app
                            :name "tool"
                            :global-options (list (make-option :name "files"
                                                               :kind :value :value-count :+)
                                                  (make-option :name "verbose" :kind :flag)))
                          '("tool" "--files" "a" "b" "--verbose"))
      (expect (equal (option-value inv :files) '("a" "b")))
      (expect (eq (option-value inv :verbose) t))))

  (it "requires at least one value for :+"
    (signals cli-missing-option-value
      (parse-argv (variadic-app :+) '("tool" "--files"))))

  (it "allows zero values for :*"
    (with-parsed-argv (inv (variadic-app :*) '("tool" "--files"))
      (expect (null (option-value inv :files)))))

  (it "leaves trailing tokens for positionals"
    ;; A following option-like token ends the greedy run; a bare positional does
    ;; not, so the greedy option consumes to the end here.
    (with-parsed-argv (inv (variadic-app :+) '("tool" "--files" "a" "b"))
      (expect (equal (option-value inv :files) '("a" "b")))))

  (it "shows an ellipsis token in help"
    (with-app-help-text (text (variadic-app :+))
      (assert-searches text "<FILES>...")))

  (it "reports the variadic marker in json"
    (let ((text (with-string-output (s) (render-json (variadic-app :+) s))))
      (assert-searches text "\"valueCount\":\"+\"")))

  (it "rejects an invalid value-count designator"
    (signals-invalid-specification
      (make-option :name "x" :kind :value :value-count :many))))
