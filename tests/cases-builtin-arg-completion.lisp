(in-package :cl-cli/tests)

(defun builtin-arg-app ()
  (make-app :name "demo"
            :commands (make-standard-commands :include-completion-p t
                                              :include-docs-p t)))

(describe-sequential "built-in command arg completion"
  (it "offers shell names after the completion command in bash"
    (let ((text (render-completion (builtin-arg-app) "bash")))
      (expect (search "bash" text))
      (expect (search "zsh" text))
      (expect (search "elvish" text))))

  (it "offers documentation formats after the docs command in bash"
    (let ((text (render-completion (builtin-arg-app) "bash")))
      (expect (search "markdown" text))
      (expect (search "json" text))))

  (it "offers shell names in the fish completion"
    (let ((text (render-completion (builtin-arg-app) "fish")))
      (expect (search "powershell" text))
      (expect (search "nushell" text))))

  (it "keeps the completion command accepting shell aliases"
    (let ((app (builtin-arg-app)))
      ;; pwsh / nu are aliases the parser accepts even though the completion
      ;; candidates list only the canonical names.
      (with-parsed-argv (inv app '("demo" "completion" "pwsh"))
        (expect (string= (positional-value inv :shell) "powershell")))
      (with-parsed-argv (inv app '("demo" "completion" "nu"))
        (expect (string= (positional-value inv :shell) "nushell")))))

  (it "keeps the docs command accepting format aliases"
    (let ((app (builtin-arg-app)))
      (with-parsed-argv (inv app '("demo" "docs" "md"))
        (expect (string= (positional-value inv :format) "markdown")))
      (with-parsed-argv (inv app '("demo" "docs" "roff"))
        (expect (string= (positional-value inv :format) "man"))))))
