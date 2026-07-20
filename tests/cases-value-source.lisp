(in-package :cl-cli/tests)

;;;; OPTION-VALUE-SOURCE provenance: distinguishing an explicit argv value from
;;;; an environment, config, or literal-default fallback -- the analogue of
;;;; clap's ArgMatches::value_source. Environment is stubbed via
;;;; *ENVIRONMENT-VARIABLE-READER* so the cases are deterministic; note the
;;;; parser treats an empty-string env var as PRESENT, so "no env" is a reader
;;;; that returns NIL, never one that returns "".

(defun %source-app ()
  (make-app
   :name "srctool"
   :global-options
   (list (make-option :name "output" :kind :value :default "out.txt"
                      :env-var "SRCTOOL_OUTPUT")
         (make-option :name "mode" :kind :value)
         (make-option :name "level" :kind :value))))

(defun %no-env () (constantly nil))

(defun %env-reading (pairs)
  "A reader returning the value for a name in PAIRS (a plist of NAME -> value)."
  (lambda (name) (cadr (member name pairs :test #'string=))))

(describe-sequential "option value provenance"
  (it "reports :command-line for a value passed on the argv"
    (with-environment-variable-reader ((%no-env))
      (let ((inv (parse-argv (%source-app) '("srctool" "--output" "cli.txt"))))
        (expect (string= "cli.txt" (option-value inv :output)))
        (expect (eq :command-line (option-value-source inv :output))))))

  (it "reports :env when the value comes from an environment variable"
    (with-environment-variable-reader ((%env-reading '("SRCTOOL_OUTPUT" "from-env.txt")))
      (let ((inv (parse-argv (%source-app) '("srctool"))))
        (expect (string= "from-env.txt" (option-value inv :output)))
        (expect (eq :env (option-value-source inv :output))))))

  (it "reports :default when neither argv nor env nor config supplied a value"
    (with-environment-variable-reader ((%no-env))
      (let ((inv (parse-argv (%source-app) '("srctool"))))
        (expect (string= "out.txt" (option-value inv :output)))
        (expect (eq :default (option-value-source inv :output))))))

  (it "reports :config when the value comes from the config layer"
    (with-environment-variable-reader ((%no-env))
      (let ((inv (parse-argv (%source-app) '("srctool")
                             :config '(:mode "prod"))))
        (expect (string= "prod" (option-value inv :mode)))
        (expect (eq :config (option-value-source inv :mode))))))

  (it "lets argv override env, and reports :command-line for the winner"
    (with-environment-variable-reader ((%env-reading '("SRCTOOL_OUTPUT" "from-env.txt")))
      (let ((inv (parse-argv (%source-app) '("srctool" "--output" "cli.txt"))))
        (expect (string= "cli.txt" (option-value inv :output)))
        (expect (eq :command-line (option-value-source inv :output))))))

  (it "lets argv override config, and reports :command-line for the winner"
    (with-environment-variable-reader ((%no-env))
      (let ((inv (parse-argv (%source-app) '("srctool" "--mode" "dev")
                             :config '(:mode "prod"))))
        (expect (string= "dev" (option-value inv :mode)))
        (expect (eq :command-line (option-value-source inv :mode))))))

  (it "returns NIL for an option that was never set and has no default"
    (with-environment-variable-reader ((%no-env))
      (let ((inv (parse-argv (%source-app) '("srctool"))))
        (expect (null (option-value inv :level)))
        (expect (null (option-value-source inv :level))))))

  (it "distinguishes a defaulted option from an explicitly-passed one in one parse"
    (with-environment-variable-reader ((%no-env))
      (let ((inv (parse-argv (%source-app) '("srctool" "--mode" "dev"))))
        ;; mode was passed; output fell back to its literal default.
        (expect (eq :command-line (option-value-source inv :mode)))
        (expect (eq :default (option-value-source inv :output))))))

  (it "orders provenance env over config over default"
    ;; With all three available and no argv, env must win.
    (with-environment-variable-reader ((%env-reading '("SRCTOOL_OUTPUT" "e.txt")))
      (let ((inv (parse-argv (%source-app) '("srctool")
                             :config '(:output "c.txt"))))
        (expect (string= "e.txt" (option-value inv :output)))
        (expect (eq :env (option-value-source inv :output))))))

  (it "exposes the raw source map via invocation-option-sources"
    (with-environment-variable-reader ((%no-env))
      (let ((inv (parse-argv (%source-app) '("srctool"))))
        ;; Only non-argv fills are recorded; :output defaulted here.
        (expect (eq :default (getf (invocation-option-sources inv) :output)))))))
