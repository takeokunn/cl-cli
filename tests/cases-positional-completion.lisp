(in-package :cl-cli/tests)

(defun positional-completion-app ()
  (make-app
   :name "tool"
   :positionals (list (make-positional :key :env :choices '("dev" "prod")))
   :commands (list (make-command
                    :name "deploy"
                    :positionals (list (make-positional
                                        :key :target
                                        :completion-candidates '("staging" "production")))))))

(describe-sequential "positional completion"
  (it "offers root positional values in every shell"
    (let ((app (positional-completion-app)))
      (dolist (shell '("bash" "zsh" "fish" "powershell" "nushell" "elvish"))
        (let ((text (render-completion app shell)))
          (expect (search "dev" text))
          (expect (search "prod" text))))))

  (it "offers command positional values in bash, zsh, and fish"
    (let ((app (positional-completion-app)))
      (dolist (shell '("bash" "zsh" "fish"))
        (let ((text (render-completion app shell)))
          (expect (search "staging" text))
          (expect (search "production" text))))))

  (it "accepts :completion-candidates on a positional"
    (let ((p (make-positional :key :x :completion-candidates '(("a" . "First")))))
      (expect (equal (cl-cli::positional-spec-completion-candidates p)
                     '(("a" . "First"))))))

  (it "exposes positional candidates and choices in json"
    (let ((text (with-string-output (s) (render-json (positional-completion-app) s))))
      (assert-searches text "\"choices\":[\"dev\",\"prod\"]"
                       "\"completionCandidates\":[\"staging\",\"production\"]")))

  (it "rejects an empty positional completion candidate"
    (signals-invalid-specification
      (make-positional :key :x :completion-candidates '("")))))
