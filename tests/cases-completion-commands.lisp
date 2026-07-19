(in-package :cl-cli/tests)

(describe-sequential "completion commands"
  (it "prints completion scripts"
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
         "complete -c 'demo' -f"))))

  (it "rejects unsupported shells"
    (let ((app (make-app :name "demo"
                         :commands (list (make-completion-command)))))
      (signals cli-invalid-positional-value
        (parse-argv app '("demo" "completion" "pwsh")))))

  (it "standard commands default to help and version"
    (let ((commands (make-standard-commands)))
      (expect (= 2 (length commands)))
      (expect (string= "help" (command-name (first commands))))
      (expect (string= "version" (command-name (second commands))))))

  (it "standard commands can include completion"
    (let* ((commands (make-standard-commands :include-completion-p t))
           (names (mapcar #'command-name commands)))
      (expect (equal '("help" "version" "completion") names))))

  (it "standard commands can disable individual entries"
    (let ((commands (make-standard-commands :include-help-p nil
                                            :include-version-p nil
                                            :include-completion-p t)))
      (expect (= 1 (length commands)))
      (expect (string= "completion" (command-name (first commands))))))

  (it "standard commands support app dispatch"
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
      (expect (zerop version-exit-code))
      (assert-searches version-text "demo 1.2.3")
      (assert-searches completion-text "completion")))

  (it "version without app version prints only the app name"
    (let* ((app (make-app :name "demo"
                          :commands (list (make-version-command))))
           (exit-code nil)
           (text (with-string-output (stdout)
                   (setf exit-code (run-app app
                                            :argv '("demo" "version")
                                            :stdout stdout)))))
      (expect (zerop exit-code))
      (expect (string= (concatenate 'string "demo" (string #\Newline)) text))))

  (it "render-completion rejects unsupported shells"
    (signals cli-invalid-positional-value
      (render-completion (make-app :name "demo") "pwsh"))))
