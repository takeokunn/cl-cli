(in-package :cl-cli/tests)

(defun positional-choice-app ()
  (make-app :name "tool"
            :positionals (list (make-positional :key :env
                                                :required-p t
                                                :description "Target env."
                                                :choices '("dev" "prod")))))

(describe-sequential "positional choices"
  (it "accepts a value in the choice set"
    (with-parsed-argv (inv (positional-choice-app) '("tool" "prod"))
      (expect (string= (positional-value inv :env) "prod"))))

  (it "rejects a value outside the choice set"
    (signals cli-invalid-positional-value
      (parse-argv (positional-choice-app) '("tool" "staging"))))

  (it "reports the expected choices in the error"
    (caught-signal= (cli-invalid-positional-value condition)
        (parse-argv (positional-choice-app) '("tool" "staging"))
      (:eq cli-invalid-positional-value-name :env)
      (:searches cli-error-message "expected one of: dev, prod")))

  (it "shows the choices in help output"
    (with-app-help-text (text (positional-choice-app))
      (assert-searches text "choices: dev | prod")))

  (it "emits the choices in json"
    (let ((text (with-string-output (stream)
                  (render-json (positional-choice-app) stream))))
      (assert-searches text "\"choices\":[\"dev\",\"prod\"]"))))

(describe-sequential "command help footer"
  (it "prints the command help footer in command help"
    (let* ((command (make-command :name "run"
                                  :help-footer "Run notes here."))
           (app (make-app :name "tool" :commands (list command))))
      (with-command-help-text (text app command)
        (assert-searches text "Run notes here."))))

  (it "falls back to the app footer when the command has none"
    (let* ((command (make-command :name "run"))
           (app (make-app :name "tool"
                          :help-footer "App footer."
                          :commands (list command))))
      (with-command-help-text (text app command)
        (assert-searches text "App footer."))))

  (it "prefers the command footer over the app footer"
    (let* ((command (make-command :name "run" :help-footer "Command footer."))
           (app (make-app :name "tool"
                          :help-footer "App footer."
                          :commands (list command))))
      (with-command-help-text (text app command)
        (assert-searches text "Command footer.")
        (assert-not-searches text "App footer."))))

  (it "includes the command footer in generated docs"
    (let* ((command (make-command :name "run" :help-footer "See docs online."))
           (app (make-app :name "tool" :commands (list command))))
      (let ((man (with-string-output (s) (render-manpage app s)))
            (markdown (with-string-output (s) (render-markdown app s)))
            (json (with-string-output (s) (render-json app s))))
        (assert-searches man "See docs online.")
        (assert-searches markdown "See docs online.")
        (assert-searches json "\"helpFooter\":\"See docs online.\"")))))
