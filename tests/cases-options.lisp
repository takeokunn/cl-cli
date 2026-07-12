(in-package :cl-cli/tests)

(deftest optional-value-option
  (with-parsed-invocations (app (make-app
                                 :name "cc"
                                 :global-options (list (optional-value-option "coverage")))
                               (plain '("cc" "--coverage"))
                               (mcdc '("cc" "--coverage=mcdc")))
    (invocation-values= plain
      (:option :coverage t))
    (invocation-values= mcdc
      (:option :coverage "mcdc")))
  t)

(deftest optional-value-does-not-consume-separated-value-by-default
  (with-parsed-argv (inv (make-app
                          :name "cc"
                          :global-options (list (optional-value-option "coverage"))
                          :positionals (list (make-positional :key :file :required-p nil)))
                        '("cc" "--coverage" "main.lisp"))
    (invocation-values= inv
      (:option :coverage t)
      (:positional :file "main.lisp")))
  t)

(deftest optional-value-can-consume-separated-value-when-enabled
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
    (is (eq (invocation-action before-help) :help)))
  t)

(deftest short-optional-value-can-consume-separated-value-when-enabled
  (with-parsed-argv (inv (make-app :name "cc"
                                   :global-options (list (optional-value-option "coverage"
                                                                                 :short #\c
                                                                                 :consume-optional-value-p t)))
                        '("cc" "-c" "true"))
    (option-values= inv :coverage "true"))
  t)

(deftest stop-parsing-option-preserves-remaining-arguments
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
      (:positional :args '("--flag-like" "value"))))
  t)

(deftest stop-parsing-short-attached-value
  (with-parsed-argv (inv (make-app
                          :name "nshell"
                          :global-options (list (stop-parsing-option "command" :short #\c))
                          :positionals (list (make-positional :key :args :rest-p t)))
                        '("nshell" "-cecho" "--flag-like"))
    (option-values= inv :command "echo")
    (positional-values= inv :args '("--flag-like")))
  t)

(deftest short-value-option-accepts-attached-value
  (with-parsed-argv (inv (make-app :name "cl-tmux"
                                   :global-options (list (make-option :name "socket"
                                                                       :short #\S
                                                                       :kind :value)))
                        '("cl-tmux" "-S/tmp/tmux.sock"))
    (option-values= inv :socket "/tmp/tmux.sock"))
  t)

(deftest stop-parsing-script-mode-can-normalize-opaque-tail
  (with-parsed-argv (inv (make-app
                          :name "cl-cc"
                          :global-options (list (stop-parsing-option "script"))
                          :positionals (list (make-positional :key :script-argv :rest-p t)))
                        '("cl-cc" "--script" "ci/build.lisp"
                          "--" "--target" "release"))
    (is (string= (option-value inv :script) "ci/build.lisp"))
    (is (equal (positional-value inv :script-argv)
               '("--" "--target" "release")))
    (is (equal (strip-argv-separators (positional-value inv :script-argv))
               '("--target" "release"))))
  t)

(deftest rest-positional-uses-default-when-argv-is-empty
  (with-parsed-argv (inv (make-app
                          :name "tool"
                          :positionals (list (make-positional :key :args
                                                              :rest-p t
                                                              :default '("src" "tests"))))
                        '("tool"))
    (is (equal (positional-value inv :args) '("src" "tests"))))
  t)

(deftest explicit-nil-option-default-is-preserved
  (let ((app (make-app
              :name "tool"
              :global-options (list (make-option :name "mode"
                                                  :kind :value
                                                  :default nil)))))
    (with-parsed-argv (inv app '("tool"))
      (is (member :mode (invocation-global-options inv)))
      (is (null (option-value inv :mode)))
      (with-app-help-text (text app)
        (assert-searches text "default: NIL")))
    )
  t)

(deftest optional-command-positional
  (with-parsed-invocations (app (make-app
                                 :name "cl-tmux"
                                 :commands (list (make-command
                                                  :name "server"
                                                  :positionals (list (make-positional :key :name
                                                                                      :required-p nil)))))
                               (without-name '("cl-tmux" "server"))
                               (with-name '("cl-tmux" "server" "main")))
    (is (null (positional-value without-name :name)))
    (is (string= (positional-value with-name :name) "main")))
  t)

(deftest command-rest-positional-uses-default-when-command-argv-is-empty
  (with-parsed-argv (inv (make-app
                          :name "tool"
                          :commands (list (make-command
                                           :name "run"
                                           :positionals (list (make-positional :key :args
                                                                               :rest-p t
                                                                               :default '("src" "tests"))))))
                        '("tool" "run"))
    (is (string= (command-name (invocation-command inv)) "run"))
    (is (equal (positional-value inv :args) '("src" "tests"))))
  t)

(deftest explicit-nil-positional-default-is-preserved
  (with-parsed-argv (inv (make-app
                          :name "tool"
                          :positionals (list (make-positional :key :mode
                                                              :default nil)))
                        '("tool"))
    (is (member :mode (invocation-positionals inv)))
    (is (null (positional-value inv :mode))))
  t)

(deftest string-positional-default-uses-parser
  (with-parsed-argv (inv (make-app
                          :name "tool"
                          :positionals (list (make-positional :key :port
                                                              :default "8080"
                                                              :parser #'parse-integer)))
                        '("tool"))
    (is (= (positional-value inv :port) 8080)))
  t)

(deftest default-command-dispatches-without-command-token
  (with-parsed-argv (inv (make-app :name "tool"
                                   :commands (list (make-command
                                                    :name "run"
                                                    :positionals (list (make-positional :key :args
                                                                                        :rest-p t))))
                                   :default-command "run")
                        '("tool"))
    (is (string= (command-name (invocation-command inv)) "run"))
    (is (equal (positional-value inv :args) nil)))
  t)

(deftest default-command-can-target-a-command-alias
  (with-parsed-argv (inv (make-app :name "tool"
                                   :commands (list (make-command
                                                    :name "run"
                                                    :aliases '("r")
                                                    :positionals (list (make-positional :key :args
                                                                                        :rest-p t))))
                                   :default-command "r")
                        '("tool"))
    (is (string= (command-name (invocation-command inv)) "run"))
    (is (equal (positional-value inv :args) nil)))
  t)

(deftest consumer-example-cl-cc-compile-command
  (with-parsed-argv (inv (make-example-app "MAKE-CL-CC-APP")
                         '("cl-cc" "compile" "src/main.lisp"
                           "--output" "main.fasl"
                           "--coverage=mcdc"
                           "--threads"))
    (is (string= (command-name (invocation-command inv)) "compile"))
    (positional-values= inv
      (:input "src/main.lisp"))
    (option-values= inv
      (:output "main.fasl")
      (:coverage "mcdc")
      (:threads t)))
  t)

(deftest consumer-example-cl-cc-script-mode
  (with-parsed-argv (inv (make-example-app "MAKE-CL-CC-APP")
                         '("cl-cc" "--script" "ci/build.lisp"
                           "--" "--target" "release"))
    (option-values= inv
      (:script "ci/build.lisp"))
    (positional-values= inv
      (:script-argv '("--" "--target" "release")))
    (is (equal (strip-argv-separators (positional-value inv :script-argv))
               '("--target" "release"))))
  t)

(deftest consumer-example-cl-tmux-launcher-and-default-command
  (let ((argv (application-argv
               :argv '("sbcl" "--core" "cl-tmux.core"
                       "--no-userinit" "-Lmain" "-S/tmp/tmux.sock" "dev"))))
    (with-parsed-argv (inv (make-example-app "MAKE-CL-TMUX-APP")
                           (cons "cl-tmux" argv))
      (is (string= (command-name (invocation-command inv)) "attach"))
      (option-values= inv
        (:label "main")
        (:socket "/tmp/tmux.sock"))
      (positional-values= inv
        (:target "dev"))))
  t)

(deftest consumer-example-private-trade-fx-validates-and-preserves-tail
  (with-parsed-argv (inv (make-example-app "MAKE-PRIVATE-TRADE-FX-APP")
                         '("private-trade-fx" "--instrument" "USD_JPY"
                           "--" "--risk" "tight"))
    (option-values= inv
      (:instrument "USD_JPY"))
    (positional-values= inv
      (:strategy-argv '("--risk" "tight"))))
  (signals cli-invalid-option-value
    (parse-argv (make-example-app "MAKE-PRIVATE-TRADE-FX-APP")
                '("private-trade-fx" "--instrument" "USD_JPY" "--count" "0")))
  t)

(deftest consumer-example-nshell-command-and-script-modes
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
      (is (equal command-tail '("--json")))
      (positional-values= script-inv
        (:script "build.ns")
        (:script-argv '("arg1" "arg2")))))
  t)
