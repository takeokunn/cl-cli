(in-package :cl-cli/tests)

(defun arity-app (&rest positional-args)
  (make-app :name "tool"
            :positionals (list (apply #'make-positional :key :args :rest-p t
                                      positional-args))))

(describe-sequential "rest positional arity"
  (it "accepts a count at or above the minimum"
    (with-parsed-argv (inv (arity-app :min-count 1) '("tool" "a" "b"))
      (expect (equal (positional-value inv :args) '("a" "b")))))

  (it "rejects too few values"
    (signals cli-missing-positional
      (parse-argv (arity-app :min-count 2) '("tool" "a"))))

  (it "rejects zero values under a positive minimum"
    (signals cli-missing-positional
      (parse-argv (arity-app :min-count 1) '("tool"))))

  (it "accepts a count at or below the maximum"
    (with-parsed-argv (inv (arity-app :max-count 3) '("tool" "a" "b"))
      (expect (equal (positional-value inv :args) '("a" "b")))))

  (it "rejects too many values"
    (signals cli-unexpected-argument
      (parse-argv (arity-app :max-count 2) '("tool" "a" "b" "c"))))

  (it "accepts a count inside a range"
    (with-parsed-argv (inv (arity-app :min-count 1 :max-count 3) '("tool" "a" "b"))
      (expect (equal (positional-value inv :args) '("a" "b")))))

  (it "shows the arity in help"
    (with-app-help-text (text (arity-app :min-count 1 :max-count 3))
      (assert-searches text "1..3 values")))

  (it "shows a lone minimum in help"
    (with-app-help-text (text (arity-app :min-count 2))
      (assert-searches text "at least 2 values")))

  (it "emits the counts in json"
    (let ((text (with-string-output (s) (render-json (arity-app :min-count 1 :max-count 3) s))))
      (assert-searches text "\"minCount\":1" "\"maxCount\":3")))

  (it "rejects :min-count without :rest-p"
    (signals-invalid-specification
      (make-positional :key :x :min-count 1)))

  (it "rejects a negative count"
    (signals-invalid-specification
      (make-positional :key :x :rest-p t :min-count -1)))

  (it "rejects an inverted min/max count"
    (signals-invalid-specification
      (make-positional :key :x :rest-p t :min-count 3 :max-count 1))))
