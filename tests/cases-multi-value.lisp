(in-package :cl-cli/tests)

(defun multi-value-app (&rest option-args)
  (make-app :name "tool"
            :global-options (list (apply #'make-option :name "point" :short #\p
                                         :kind :value :value-count 2 option-args))))

(describe-sequential "multi-value options"
  (it "consumes N separated tokens as a list"
    (with-parsed-argv (inv (multi-value-app :type :integer) '("tool" "--point" "1" "2"))
      (expect (equal (option-value inv :point) '(1 2)))))

  (it "consumes N tokens after a short option"
    (with-parsed-argv (inv (multi-value-app :type :integer) '("tool" "-p" "3" "4"))
      (expect (equal (option-value inv :point) '(3 4)))))

  (it "signals a missing value when too few tokens remain"
    (signals cli-missing-option-value
      (parse-argv (multi-value-app) '("tool" "--point" "1"))))

  (it "rejects an attached value for a multi-value option"
    (signals cli-usage-error
      (parse-argv (multi-value-app) '("tool" "--point=1"))))

  (it "accumulates per-occurrence lists with :multiple-p"
    (with-parsed-argv (inv (multi-value-app :type :integer :multiple-p t)
                          '("tool" "--point" "1" "2" "--point" "3" "4"))
      (expect (equal (option-value inv :point) '((1 2) (3 4))))))

  (it "shows one value token per expected value in help"
    (with-app-help-text (text (multi-value-app))
      (assert-searches text "<POINT> <POINT>")))

  (it "reports the value count in json"
    (let ((text (with-string-output (s) (render-json (multi-value-app) s))))
      (assert-searches text "\"valueCount\":2")))

  (it "rejects :value-count on a flag"
    (signals-invalid-specification
      (make-option :name "x" :kind :flag :value-count 2)))

  (it "rejects a non-positive :value-count"
    (signals-invalid-specification
      (make-option :name "x" :kind :value :value-count 0)))

  (it "rejects combining :value-count with :value-delimiter"
    (signals-invalid-specification
      (make-option :name "x" :kind :value :value-count 2 :value-delimiter #\,))))
