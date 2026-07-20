(in-package :cl-cli/tests)

(describe-sequential "options"
  (it "supports optional value options"
    (with-parsed-invocations (app (make-app
                                   :name "cc"
                                   :global-options (list (optional-value-option "coverage")))
                                 (plain '("cc" "--coverage"))
                                 (mcdc '("cc" "--coverage=mcdc")))
      (invocation-values= plain
        (:option :coverage t))
      (invocation-values= mcdc
        (:option :coverage "mcdc"))))

  (it "optional value does not consume separated value by default"
    (with-parsed-argv (inv (make-app
                            :name "cc"
                            :global-options (list (optional-value-option "coverage"))
                            :positionals (list (make-positional :key :file :required-p nil)))
                          '("cc" "--coverage" "main.lisp"))
      (invocation-values= inv
        (:option :coverage t)
        (:positional :file "main.lisp"))))

  (it "optional value can consume separated value when enabled"
    (with-parsed-invocations (app (make-app
                                   :name "cc"
                                   :global-options (list (optional-value-option "coverage"
                                                                                 :consume-optional-value-p t)))
                                 (plain '("cc" "--coverage"))
                                 (attached '("cc" "--coverage=mcdc"))
                                 (separated '("cc" "--coverage" "true"))
                                 (before-help '("cc" "--coverage" "--help")))
      (invocation-values= plain (:option :coverage t))
      (invocation-values= attached (:option :coverage "mcdc"))
      (invocation-values= separated (:option :coverage "true"))
      (invocation-values= before-help (:option :coverage t))
      (expect (eq (invocation-action before-help) :help))))

  (it "short optional value can consume separated value when enabled"
    (with-parsed-argv (inv (make-app :name "cc"
                                     :global-options (list (optional-value-option "coverage"
                                                                                   :short #\c
                                                                                   :consume-optional-value-p t)))
                          '("cc" "-c" "true"))
      (option-values= inv :coverage "true")))

  (it "stop parsing option preserves remaining arguments"
    (with-parsed-invocations (app (make-app
                                   :name "nshell"
                                   :global-options (list (stop-parsing-option "command"
                                                                               :short #\c))
                                   :positionals (list (make-positional :key :args :rest-p t)))
                                 (long '("nshell" "--command" "echo $argv"
                                         "--flag-like" "value"))
                                 (short '("nshell" "-c" "echo $argv"
                                          "--flag-like" "value")))
      (invocation-values= long
        (:option :command "echo $argv")
        (:positional :args '("--flag-like" "value")))
      (invocation-values= short
        (:option :command "echo $argv")
        (:positional :args '("--flag-like" "value")))))

  (it "supports stop parsing short attached value"
    (with-parsed-argv (inv (make-app
                            :name "nshell"
                            :global-options (list (stop-parsing-option "command" :short #\c))
                            :positionals (list (make-positional :key :args :rest-p t)))
                          '("nshell" "-cecho" "--flag-like"))
      (option-values= inv :command "echo")
      (positional-values= inv :args '("--flag-like"))))

  (it "short value option accepts attached value"
    (with-parsed-argv (inv (make-app :name "cl-tmux"
                                     :global-options (list (make-option :name "socket"
                                                                         :short #\S
                                                                         :kind :value)))
                          '("cl-tmux" "-S/tmp/tmux.sock"))
      (option-values= inv :socket "/tmp/tmux.sock")))

  (it "stop parsing script mode can normalize opaque tail"
    (with-parsed-argv (inv (make-app
                            :name "cl-cc"
                            :global-options (list (stop-parsing-option "script"))
                            :positionals (list (make-positional :key :script-argv :rest-p t)))
                          '("cl-cc" "--script" "ci/build.lisp"
                            "--" "--target" "release"))
      (expect (string= (option-value inv :script) "ci/build.lisp"))
      (expect (equal (positional-value inv :script-argv)
                     '("--" "--target" "release")))
      (expect (equal (strip-argv-separators (positional-value inv :script-argv))
                     '("--target" "release")))))

  (it "rest positional uses default when argv is empty"
    (with-parsed-argv (inv (make-app
                            :name "tool"
                            :positionals (list (make-positional :key :args
                                                                :rest-p t
                                                                :default '("src" "tests"))))
                          '("tool"))
      (expect (equal (positional-value inv :args) '("src" "tests")))))

  (it "preserves explicit nil option default"
    (let ((app (make-app
                :name "tool"
                :global-options (list (make-option :name "mode"
                                                   :kind :value
                                                   :default nil)))))
      (with-parsed-argv (inv app '("tool"))
        (expect (member :mode (invocation-global-options inv)))
        (expect (null (option-value inv :mode)))
        (with-app-help-text (text app)
          (assert-searches text "default: NIL")))))

  (it "supports optional command positional"
    (with-parsed-invocations (app (make-app
                                   :name "cl-tmux"
                                   :commands (list (make-command
                                                    :name "server"
                                                    :positionals (list (make-positional :key :name
                                                                                        :required-p nil)))))
                                 (without-name '("cl-tmux" "server"))
                                 (with-name '("cl-tmux" "server" "main")))
      (expect (null (positional-value without-name :name)))
      (expect (string= (positional-value with-name :name) "main"))))

  (it "command rest positional uses default when command argv is empty"
    (with-parsed-argv (inv (make-app
                            :name "tool"
                            :commands (list (make-command
                                             :name "run"
                                             :positionals (list (make-positional :key :args
                                                                                 :rest-p t
                                                                                 :default '("src" "tests"))))))
                          '("tool" "run"))
      (expect (string= (command-name (invocation-command inv)) "run"))
      (expect (equal (positional-value inv :args) '("src" "tests")))))

  (it "preserves explicit nil positional default"
    (with-parsed-argv (inv (make-app
                            :name "tool"
                            :positionals (list (make-positional :key :mode
                                                                :default nil)))
                          '("tool"))
      (expect (member :mode (invocation-positionals inv)))
      (expect (null (positional-value inv :mode)))))

  (it "uses parser for string positional defaults"
    (with-parsed-argv (inv (make-app
                            :name "tool"
                            :positionals (list (make-positional :key :port
                                                                :default "8080"
                                                                :parser #'parse-integer)))
                          '("tool"))
      (expect (= (positional-value inv :port) 8080))))

  (it "validates choices for string positional defaults"
    (signals cli-invalid-positional-value
      (parse-argv (make-app
                   :name "tool"
                   :positionals (list (make-positional :key :mode
                                                       :choices '("dev" "prod")
                                                       :default "staging")))
                  '("tool"))))

  (it "uses parser for scalar rest positional defaults"
    (with-parsed-argv (inv (make-app
                            :name "tool"
                            :positionals (list (make-positional :key :ports
                                                                :rest-p t
                                                                :default "8080"
                                                                :parser #'parse-integer)))
                          '("tool"))
      (expect (equal (positional-value inv :ports) '(8080)))))

  (it "dispatches default command without command token"
    (with-parsed-argv (inv (make-app :name "tool"
                                     :commands (list (make-command
                                                      :name "run"
                                                      :positionals (list (make-positional :key :args
                                                                                          :rest-p t))))
                                     :default-command "run")
                          '("tool"))
      (expect (string= (command-name (invocation-command inv)) "run"))
      (expect (equal (positional-value inv :args) nil))))

  (it "allows default command to target a command alias"
    (with-parsed-argv (inv (make-app :name "tool"
                                     :commands (list (make-command
                                                      :name "run"
                                                      :aliases '("r")
                                                      :positionals (list (make-positional :key :args
                                                                                          :rest-p t))))
                                     :default-command "r")
                          '("tool"))
      (expect (string= (command-name (invocation-command inv)) "run"))
      (expect (equal (positional-value inv :args) nil))))

  (it "parses cl-cc compile consumer example"
    (with-parsed-argv (inv (make-example-app "MAKE-CL-CC-APP")
                           '("cl-cc" "compile" "src/main.lisp"
                             "--output" "main.fasl"
                             "--coverage=mcdc"
                             "--threads"))
      (expect (string= (command-name (invocation-command inv)) "compile"))
      (positional-values= inv
        (:input "src/main.lisp"))
      (option-values= inv
        (:output "main.fasl")
        (:coverage "mcdc")
        (:threads t))))

  (it "parses cl-cc script mode consumer example"
    (with-parsed-argv (inv (make-example-app "MAKE-CL-CC-APP")
                           '("cl-cc" "--script" "ci/build.lisp"
                             "--" "--target" "release"))
      (option-values= inv
        (:script "ci/build.lisp"))
      (positional-values= inv
        (:script-argv '("--" "--target" "release")))
      (expect (equal (strip-argv-separators (positional-value inv :script-argv))
                     '("--target" "release")))))

  (it "parses cl-tmux launcher and default command consumer example"
    (let ((argv (application-argv
                 :argv '("sbcl" "--core" "cl-tmux.core"
                         "--no-userinit" "-Lmain" "-S/tmp/tmux.sock" "dev"))))
      (with-parsed-argv (inv (make-example-app "MAKE-CL-TMUX-APP")
                             (cons "cl-tmux" argv))
        (expect (string= (command-name (invocation-command inv)) "attach"))
        (option-values= inv
          (:label "main")
          (:socket "/tmp/tmux.sock"))
        (positional-values= inv
          (:target "dev")))))

  (it "parses private-trade-fx example and preserves tail"
    (with-parsed-argv (inv (make-example-app "MAKE-PRIVATE-TRADE-FX-APP")
                           '("private-trade-fx" "--instrument" "USD_JPY"
                             "--" "--risk" "tight"))
      (option-values= inv
        (:instrument "USD_JPY"))
      (positional-values= inv
        (:strategy-argv '("--risk" "tight"))))
    (signals cli-invalid-option-value
      (parse-argv (make-example-app "MAKE-PRIVATE-TRADE-FX-APP")
                  '("private-trade-fx" "--instrument" "USD_JPY" "--count" "0"))))

  (it "parses nshell command and script mode consumer examples"
    (with-parsed-invocations (app (make-example-app "MAKE-NSHELL-APP")
                                 (command-inv '("nshell" "-c" "echo"
                                                "--" "--json"))
                                 (script-inv '("nshell" "build.ns" "arg1" "arg2")))
      (let ((command-tail (strip-argv-separators
                           (remove nil
                                   (cons (positional-value command-inv :script)
                                         (positional-value command-inv :script-argv)))
                           :separator "--")))
        (option-values= command-inv
          (:command "echo"))
        (expect (equal command-tail '("--json")))
        (positional-values= script-inv
          (:script "build.ns")
          (:script-argv '("arg1" "arg2")))))))
