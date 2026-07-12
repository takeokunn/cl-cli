(in-package :cl-cli/tests)

(deftest completion-command-prints-script
  (let* ((command (make-completion-command))
         (app (make-app :name "demo"
                        :commands (list command))))
    (assert-completion-searches-for-shells (app)
      ("bash"
       "#!/usr/bin/env bash"
       "# bash completion for demo"
       "_demo_completion() {"
       "complete -F _demo_completion 'demo'")
      ("zsh"
       "#compdef demo"
       "_demo_completion() {"
       "compdef _demo_completion demo")
      ("fish"
       "complete -c 'demo' -f"))
    t))

(deftest completion-command-rejects-unsupported-shell
  (let* ((app (make-app :name "demo"
                        :commands (list (make-completion-command)))))
    (signals cli-invalid-positional-value
      (parse-argv app '("demo" "completion" "pwsh"))))
  t)

(deftest make-standard-commands-defaults-to-help-and-version
  (let ((commands (make-standard-commands)))
    (is (= 2 (length commands)))
    (is (string= "help" (command-name (first commands))))
    (is (string= "version" (command-name (second commands)))))
  t)

(deftest make-standard-commands-can-include-completion
  (let* ((commands (make-standard-commands :include-completion-p t))
         (names (mapcar #'command-name commands)))
    (is (equal '("help" "version" "completion") names)))
  t)

(deftest make-standard-commands-can-disable-individual-entries
  (let ((commands (make-standard-commands :include-help-p nil
                                          :include-version-p nil
                                          :include-completion-p t)))
    (is (= 1 (length commands)))
    (is (string= "completion" (command-name (first commands)))))
  t)

(deftest make-standard-commands-supports-app-dispatch
  (let* ((app (make-app :name "demo"
                        :version "1.2.3"
                        :commands (append
                                   (make-standard-commands :include-completion-p t)
                                   (list (make-command :name "serve")))))
         (version-exit-code nil)
         (version-text (with-string-output (stdout)
                         (setf version-exit-code (run-app app
                                                          :argv '("demo" "version")
                                                          :stdout stdout))))
         (completion-text (with-string-output (completion-output)
                            (render-completion app "bash" completion-output))))
    (is (zerop version-exit-code))
    (assert-searches version-text "demo 1.2.3")
    (assert-searches completion-text "completion"))
  t)

(deftest version-command-without-app-version-prints-app-name-only
  (let* ((app (make-app :name "demo"
                        :commands (list (make-version-command))))
         (exit-code nil)
         (text (with-string-output (stdout)
                 (setf exit-code (run-app app
                                          :argv '("demo" "version")
                                          :stdout stdout)))))
    (is (zerop exit-code))
    (is (string= (concatenate 'string "demo" (string #\Newline)) text)))
  t)

(deftest render-completion-rejects-unsupported-shell
  (signals cli-invalid-positional-value
    (render-completion (make-app :name "demo") "pwsh"))
  t)
