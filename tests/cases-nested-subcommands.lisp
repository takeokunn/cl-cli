(in-package :cl-cli/tests)

(defun nested-app ()
  (make-app
   :name "git"
   :global-options (list (make-option :name "verbose" :short #\v :kind :count))
   :commands
   (list (make-command
          :name "remote"
          :description "Manage remotes."
          :options (list (make-option :name "porcelain" :kind :flag))
          :subcommands
          (list (make-command
                 :name "add"
                 :aliases '("a")
                 :positionals (list (make-positional :key :name :required-p t)
                                    (make-positional :key :url :required-p t))
                 :handler (lambda (inv) (declare (ignore inv)) 0))
                (make-command
                 :name "remove"
                 :deprecated "use rm"
                 :handler (lambda (inv) (declare (ignore inv)) 0))))
         (make-command
          :name "stash"
          :subcommands
          (list (make-command
                 :name "push"
                 :subcommands
                 (list (make-command :name "force"
                                     :handler (lambda (inv) (declare (ignore inv)) 0)))))))))

(describe-sequential "nested subcommands"
  (it "dispatches to a nested subcommand handler"
    (with-parsed-argv (inv (nested-app) '("git" "remote" "add" "origin" "http://x"))
      (expect (string= (command-name (invocation-command inv)) "add"))
      (positional-values= inv (:name "origin") (:url "http://x"))))

  (it "exposes the full command path"
    (with-parsed-argv (inv (nested-app) '("git" "remote" "add" "o" "u"))
      (expect (equal (mapcar #'command-name (invocation-command-path inv))
                     '("remote" "add")))))

  (it "keeps an ancestor command's option visible at the leaf"
    (with-parsed-argv (inv (nested-app) '("git" "remote" "--porcelain" "add" "o" "u"))
      (expect (eq (option-value inv :porcelain) t))))

  (it "accumulates a global count across the whole path"
    (with-parsed-argv (inv (nested-app) '("git" "-v" "remote" "-v" "add" "o" "u"))
      (expect (eql (option-value inv :verbose) 2))))

  (it "resolves a nested subcommand alias"
    (with-parsed-argv (inv (nested-app) '("git" "remote" "a" "o" "u"))
      (expect (string= (command-name (invocation-command inv)) "add"))))

  (it "dispatches three levels deep"
    (with-parsed-argv (inv (nested-app) '("git" "stash" "push" "force"))
      (expect (equal (mapcar #'command-name (invocation-command-path inv))
                     '("stash" "push" "force")))))

  (it "signals an unknown subcommand with a suggestion"
    (caught-signal= (cli-unknown-command condition)
        (parse-argv (nested-app) '("git" "remote" "addd"))
      (:searches cli-error-message "Unknown subcommand of remote" "add")))

  (it "runs a parent's own help when no subcommand token is given"
    (let ((text (with-string-output (stdout)
                  (run-app (nested-app) :argv '("git" "remote")
                           :stdout stdout :stderr (make-string-output-stream)))))
      (assert-searches text "Usage: git remote" "<command>" "add" "remove")))

  (it "shows nested help with the full path in usage"
    (let ((text (with-string-output (stdout)
                  (run-app (nested-app) :argv '("git" "remote" "add" "--help")
                           :stdout stdout :stderr (make-string-output-stream)))))
      (assert-searches text "Usage: git remote add")))

  (it "warns when a deprecated nested subcommand is dispatched"
    (let ((err (with-string-output (stderr)
                 (run-app (nested-app) :argv '("git" "remote" "remove")
                          :stdout (make-string-output-stream) :stderr stderr))))
      (assert-searches err "warning" "'remove'" "deprecated: use rm")))

  (it "lists subcommands in the man page with path-qualified names"
    (let ((text (with-string-output (s) (render-manpage (nested-app) s))))
      (assert-searches text ".B remote add" ".B stash push force")))

  (it "nests subcommands in markdown headings"
    (let ((text (with-string-output (s) (render-markdown (nested-app) s))))
      (assert-searches text "### `remote add" "### `stash push force`")))

  (it "nests subcommands in json"
    (let ((text (with-string-output (s) (render-json (nested-app) s))))
      (assert-searches text "\"subcommands\":[" "\"name\":\"add\"" "\"name\":\"force\"")))

  (it "treats an unknown token as a positional when the command takes one"
    (let ((app (make-app :name "tool"
                         :commands (list (make-command
                                          :name "run"
                                          :positionals (list (make-positional :key :script))
                                          :subcommands (list (make-command :name "sub"))
                                          :handler (lambda (inv) (declare (ignore inv)) 0))))))
      (with-parsed-argv (inv app '("tool" "run" "build.sh"))
        (expect (string= (positional-value inv :script) "build.sh")))))

  (it "rejects duplicate nested subcommand names at make time"
    (signals-invalid-specification
      (make-app :name "tool"
                :commands (list (make-command
                                 :name "parent"
                                 :subcommands (list (make-command :name "dup")
                                                    (make-command :name "dup")))))))

  (it "rejects a nested option key colliding with an ancestor option"
    (signals-invalid-specification
      (make-app :name "tool"
                :global-options (list (make-option :name "shared" :kind :value))
                :commands (list (make-command
                                 :name "parent"
                                 :subcommands (list (make-command
                                                     :name "child"
                                                     :options (list (make-option :name "shared"
                                                                                 :kind :flag))))))))))
