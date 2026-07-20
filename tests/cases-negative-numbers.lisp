(in-package :cl-cli/tests)

(defun negatives-app (&key (allow t))
  (make-app :name "calc"
            :allow-negative-numbers allow
            :global-options (list (make-option :name "scale" :short #\s :kind :value))
            :positionals (list (make-positional :key :n :type :number))))

(describe-sequential "negative-number positionals"
  (it "accepts a negative integer positional"
    (with-parsed-argv (inv (negatives-app) '("calc" "-5"))
      (expect (eql (positional-value inv :n) -5))))

  (it "accepts a negative decimal positional"
    (with-parsed-argv (inv (negatives-app) '("calc" "-1.5"))
      (expect (= (positional-value inv :n) -3/2))))

  (it "still parses real short options"
    (with-parsed-argv (inv (negatives-app) '("calc" "-s" "2" "-7"))
      (expect (string= (option-value inv :scale) "2"))
      (expect (eql (positional-value inv :n) -7))))

  (it "treats a negative number as an option value"
    (with-parsed-argv (inv (negatives-app) '("calc" "--scale" "-3" "10"))
      (expect (string= (option-value inv :scale) "-3"))
      (expect (eql (positional-value inv :n) 10))))

  (it "treats -5 as an option cluster when the feature is disabled"
    (signals cli-unknown-option
      (parse-argv (negatives-app :allow nil) '("calc" "-5")))))
