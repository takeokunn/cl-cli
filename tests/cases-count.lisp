(in-package :cl-cli/tests)

(defun count-option-app (&rest option-args)
  (make-app :name "tool"
            :global-options (list (apply #'make-option :name "verbose" :short #\v
                                         :kind :count option-args))))

(describe-sequential "count flags"
  (it "counts a repeated short cluster"
    (with-parsed-argv (inv (count-option-app) '("tool" "-vvv"))
      (expect (eql (option-value inv :verbose) 3))))

  (it "counts repeated long occurrences"
    (with-parsed-argv (inv (count-option-app) '("tool" "--verbose" "--verbose"))
      (expect (eql (option-value inv :verbose) 2))))

  (it "counts across split short clusters"
    (with-parsed-argv (inv (count-option-app) '("tool" "-vv" "-v"))
      (expect (eql (option-value inv :verbose) 3))))

  (it "defaults an absent count to zero"
    (with-parsed-argv (inv (count-option-app) '("tool"))
      (expect (eql (option-value inv :verbose) 0))))

  (it "honors an explicit default when the flag is absent"
    (with-parsed-argv (inv (count-option-app :default 5) '("tool"))
      (expect (eql (option-value inv :verbose) 5))))

  (it "starts counting from zero once the flag is supplied"
    (with-parsed-argv (inv (count-option-app :default 5) '("tool" "-vv"))
      (expect (eql (option-value inv :verbose) 2))))

  (it "counts alongside other options in one cluster"
    (with-parsed-argv (inv (make-app
                            :name "tool"
                            :global-options (list (make-option :name "verbose"
                                                               :short #\v
                                                               :kind :count)
                                                  (make-option :name "output"
                                                               :short #\o
                                                               :kind :value)))
                          '("tool" "-vvo" "out.bin"))
      (expect (eql (option-value inv :verbose) 2))
      (expect (string= (option-value inv :output) "out.bin"))))

  (it "accumulates a global count split across a command boundary"
    ;; The occurrences before and after the command name must sum: mixed
    ;; parsing seeds its option values from the prefix, so store-count-option
    ;; increments from the already-parsed count rather than restarting at 0.
    (let ((app (make-app
                :name "tool"
                :global-options (list (make-option :name "verbose"
                                                   :short #\v
                                                   :kind :count))
                :commands (list (make-command :name "run"
                                              :handler (lambda (inv)
                                                         (declare (ignore inv))
                                                         0))))))
      (with-parsed-argv (inv app '("tool" "-v" "run" "-vv"))
        (expect (eql (option-value inv :verbose) 3)))))

  (it "rejects an attached value on a long count option"
    (signals cli-usage-error
      (parse-argv (count-option-app) '("tool" "--verbose=3"))))

  (it "rejects combining :count with :multiple-p"
    (signals-invalid-specification
      (make-option :name "verbose" :kind :count :multiple-p t)))

  (it "renders count metadata without a value token"
    (let ((app (count-option-app)))
      (with-app-help-text (text app)
        (assert-searches text "--verbose" "count")
        (assert-not-searches text "default: 0" "verbose <" "verbose[="))))

  (it "shows a non-zero starting count in help"
    (let ((app (count-option-app :default 2)))
      (with-app-help-text (text app)
        (assert-searches text "default: 2")))))
