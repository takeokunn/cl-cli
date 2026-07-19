(in-package :cl-cli/tests)

(describe-sequential "parse"
  (it "parses a simple flag"
    (with-parsed-argv (inv (demo-app
                            :global-options (list (flag-option "verbose" :short #\v))
                            :commands nil)
                           '("demo" "--verbose"))
      (expect (eq (invocation-action inv) :dispatch))
      (expect (getf (invocation-global-options inv) :verbose))
      (expect (null (invocation-positionals inv)))))

  (it "parses command and positionals"
    (let* ((option-specs (list (value-option "output" :short #\o)))
           (positional-specs (list (make-positional :key :input :required-p t)))
           (app (make-app :name "demo")))
      (multiple-value-bind (option-values positional-values action)
          (cl-cli::parse-mixed-arguments app
                                         '("-o" "out.bin" "input.lisp")
                                         option-specs
                                         positional-specs)
        (expect (eq action :dispatch))
        (expect (equal (getf option-values :output) "out.bin"))
        (expect (equal (getf positional-values :input) "input.lisp")))))

  (it "allows command options after positionals"
    (let* ((run-command (make-command
                         :name "run"
                         :options (list (value-option "lang")
                                        (flag-option "stdlib"))
                         :positionals (list (make-positional :key :script :required-p t))))
           (app (make-app :name "cc"
                          :commands (list run-command)))
           (inv (parse-argv app '("cc" "run" "script.php" "--lang=php" "--stdlib"))))
      (expect (string= (command-name (invocation-command inv)) "run"))
      (invocation-values= inv
        (:positional :script "script.php")
        (:option :lang "php")
        (:option :stdlib t))))

  (it "allows global options after command and positionals"
    (let* ((run-command (make-command
                         :name "run"
                         :positionals (list (make-positional :key :script :required-p t))))
           (app (make-app :name "cc"
                          :global-options (list (flag-option "verbose" :short #\v))
                          :commands (list run-command)))
           (inv (parse-argv app '("cc" "run" "tool.lisp" "--verbose"))))
      (expect (string= (command-name (invocation-command inv)) "run"))
      (invocation-values= inv
        (:positional :script "tool.lisp")
        (:option :verbose t))))

  (it "parses help flag"
    (with-parsed-argv (inv (demo-app :commands nil) '("demo" "--help"))
      (expect (eq (invocation-action inv) :help))))

  (it "parses short version flag"
    (with-parsed-argv (inv (demo-app :version "1.2.3") '("demo" "-V"))
      (expect (eq (invocation-action inv) :version))))

  (it "requires app version for version flags"
    (let ((app (demo-app)))
      (signals cli-unknown-option
        (parse-argv app '("demo" "-V")))
      (signals cli-unknown-option
        (parse-argv app '("demo" "--version")))))

  (it "errors on unknown options"
    (let ((app (demo-app :commands nil)))
      (signals cli-unknown-option
        (parse-argv app '("demo" "--bogus")))))

  (it "suggests nearest match for unknown options"
    (let ((app (demo-app
                :global-options
                (list (flag-option "verbose"
                                   :short #\v)))))
      (caught-signal= (cli-unknown-option condition)
          (parse-argv app '("demo" "--verbsoe"))
        (:searches cli-error-message "Did you mean: --verbose?"))))

  (it "does not suggest hidden options"
    (let ((app (demo-app
                :global-options
                (list (flag-option "verbose"
                                   :short #\v)
                      (flag-option "internal-debug"
                                   :short #\i
                                   :hidden-p t)))))
      (catching-signal (cli-unknown-option condition)
        (parse-argv app '("demo" "--internal-deubg"))
        (assert-searches (cli-error-message condition)
          "Unknown option: --internal-deubg")
        (assert-not-searches (cli-error-message condition)
          "--internal-debug"))
      (catching-signal (cli-unknown-option condition)
        (parse-argv app '("demo" "-x"))
        (assert-searches (cli-error-message condition)
          "Did you mean: -h?")
        (assert-not-searches (cli-error-message condition)
          "-i"))))

  (it "errors on unexpected positionals"
    (signals cli-unexpected-argument
      (parse-argv (demo-app :commands nil) '("demo" "extra"))))

  (it "errors on missing required options"
    (let* ((command (make-command
                     :name "run"
                     :options (list (make-option :name "config"
                                                 :kind :value
                                                 :required-p t))))
           (app (make-app :name "demo" :commands (list command))))
      (signals cli-missing-option-value
        (parse-argv app '("demo" "run")))))

  (it "uses contextual command help"
    (let* ((command (make-command
                     :name "compile"
                     :options (list (make-option :name "config"
                                                 :kind :value
                                                 :required-p t))
                     :positionals (list (make-positional :key :input :required-p t))))
           (app (make-app :name "demo" :commands (list command))))
      (with-parsed-argv (inv app '("demo" "compile" "--help"))
        (expect (eq (invocation-action inv) :help))
        (expect (string= (command-name (invocation-command inv)) "compile")))))

  (it "suggests nearest match for unknown commands"
    (let* ((command (make-command :name "compile"
                                  :aliases '("build")))
           (app (make-app :name "demo" :commands (list command))))
      (caught-signal= (cli-unknown-command condition)
          (parse-argv app '("demo" "compiel"))
        (:searches cli-error-message "Did you mean: compile?"))))

  (it "does not suggest hidden commands"
    (let* ((public-command (make-command :name "compile"))
           (hidden-command (make-command :name "internal-rebuild"
                                         :aliases '("irebuild")
                                         :hidden-p t))
           (app (make-app :name "demo"
                          :commands (list public-command hidden-command))))
      (catching-signal (cli-unknown-command condition)
        (parse-argv app '("demo" "internal-rebiuld"))
        (assert-searches (cli-error-message condition)
          "Unknown command: internal-rebiuld")
        (assert-not-searches (cli-error-message condition)
          "internal-rebuild"
          "irebuild"))))

  (it "requires option name before boolean parser setup"
    (signals-invalid-specification
      (make-option :kind :boolean)))

  (it "requires positional key or name"
    (signals-invalid-specification
      (make-positional)))

  (it "parses option aliases"
    (with-parsed-argv (inv (make-app :name "demo"
                                     :global-options
                                     (list (make-option :name "verbose"
                                                        :aliases '("chatty")
                                                        :kind :flag)
                                           (make-option :name "threads"
                                                        :aliases '("parallel")
                                                        :kind :boolean)))
                           '("demo" "--chatty" "--no-parallel"))
      (option-values= inv :verbose t :threads nil)))

  (it "resolves command alias"
    (let* ((command (make-command :name "compile"
                                  :aliases '("build")
                                  :description "Compile sources."))
           (app (make-app :name "demo" :commands (list command))))
      (with-parsed-argv (inv app '("demo" "build"))
        (expect (string= (command-name (invocation-command inv)) "compile")))))

  (it "supports root positionals and rest"
    (with-parsed-argv (inv (make-app
                            :name "nshell"
                            :positionals (list (make-positional :key :script :required-p nil)
                                               (make-positional :key :script-args :rest-p t)))
                          '("nshell" "build.ns" "a" "b"))
      (invocation-values= inv
        (:positional :script "build.ns")
        (:positional :script-args '("a" "b")))))

  (it "dispatches root handler"
    (let* ((seen nil)
           (app (make-app :name "tmuxish"
                          :handler (lambda (invocation)
                                     (setf seen invocation)
                                     7)))
           (exit-code (run-app app :argv '("tmuxish"))))
      (expect (= exit-code 7))
      (expect (eq (invocation-app seen) app))))

  (it "extracts application argv after runtime marker"
    (let ((argv '("sbcl" "--core" "cl-tmux.core"
                  "--no-userinit" "attach" "-Lmain")))
      (expect (equal (extract-application-argv
                      :argv argv
                      :runtime-markers '("--no-userinit" "--end-toplevel-options"))
                     '("attach" "-Lmain")))))

  (it "extracts application argv after separator"
    (let ((argv '("nix" "run" ".#simulator" "--" "--seeds" "10")))
      (expect (equal (extract-application-argv :argv argv :separator "--")
                     '("--seeds" "10")))))

  (it "combines runtime marker and separator for application argv extraction"
    (let ((argv '("sbcl" "--script" "runner.lisp"
                  "--end-toplevel-options" "nix" "run" ".#simulator"
                  "--" "--instrument" "USD_JPY")))
      (expect (equal (extract-application-argv
                      :argv argv
                      :runtime-markers '("--no-userinit" "--end-toplevel-options")
                      :separator "--")
                     '("--instrument" "USD_JPY")))))

  (it "does not reinterpret a marker-shaped application argument after the separator"
    ;; Everything after the first separator is opaque application argv --
    ;; a literal token there that happens to match a runtime marker must not
    ;; be treated as a launcher token and dropped along with what precedes it.
    (let ((argv '("sbcl" "--script" "foo.lisp"
                  "--" "--end-toplevel-options" "positional-arg")))
      (expect (equal (extract-application-argv
                      :argv argv
                      :runtime-markers '("--end-toplevel-options")
                      :separator "--")
                     '("--end-toplevel-options" "positional-arg")))))

  (it "returns a fresh default runtime markers list"
    (let ((left (default-runtime-markers))
          (right (default-runtime-markers)))
      (expect (equal left right))
      (expect (not (eq left right)))))

  (it "application-argv uses default runtime markers"
    (let ((argv '("sbcl" "--core" "cl-tmux.core"
                  "--no-userinit" "attach" "-Lmain")))
      (expect (equal (application-argv :argv argv)
                     '("attach" "-Lmain")))))

  (it "application-argv can also extract after separator"
    (let ((argv '("sbcl" "--script" "runner.lisp"
                  "--end-toplevel-options" "nix" "run" ".#simulator"
                  "--" "--instrument" "USD_JPY")))
      (expect (equal (application-argv :argv argv :separator "--")
                     '("--instrument" "USD_JPY")))))

  (it "strip-argv-separators removes literal sentinels"
    (expect (equal (strip-argv-separators '("build.lisp" "--" "--flag" "value"))
                   '("build.lisp" "--flag" "value")))
    (expect (equal (strip-argv-separators '("a" "::" "b") :separator "::")
                   '("a" "b"))))

  (it "treats a bare - as a positional rather than crashing"
    (with-parsed-argv (inv (make-app :name "app"
                                     :positionals (list (make-positional :key :files
                                                                         :rest-p t)))
                           '("app" "-" "b"))
      (expect (equal (positional-value inv :files) '("-" "b")))))

  (it "keeps tokens after -- out of command dispatch"
    (with-parsed-argv (inv (make-app :name "myapp"
                                     :positionals (list (make-positional :key :files
                                                                         :rest-p t))
                                     :commands (list (make-command :name "deploy")))
                           '("myapp" "--" "deploy" "x"))
      (expect (null (invocation-command inv)))
      (expect (equal (positional-value inv :files) '("deploy" "x")))))

  (it "honors stop-parsing on flag options for long and short forms"
    (let ((app (make-app :name "f"
                         :global-options (list (make-option :name "exec" :short #\x
                                                            :kind :flag
                                                            :stop-parsing-p t))
                         :positionals (list (make-positional :key :rest :rest-p t)))))
      (with-parsed-argv (inv app '("f" "--exec" "--bar" "baz"))
        (expect (option-value inv :exec))
        (expect (equal (positional-value inv :rest) '("--bar" "baz"))))
      (with-parsed-argv (inv app '("f" "-x" "--bar" "baz"))
        (expect (option-value inv :exec))
        (expect (equal (positional-value inv :rest) '("--bar" "baz"))))))

  (it "preserves unconsumed short-cluster characters after a mid-cluster stop-parsing flag"
    ;; A stop-parsing flag/boolean has no value of its own to absorb the rest
    ;; of the cluster, unlike :VALUE/:OPTIONAL-VALUE options -- the remainder
    ;; must resurface as literal input instead of being silently dropped.
    (let ((app (make-app :name "f"
                         :global-options (list (make-option :name "exec" :short #\x
                                                            :kind :flag
                                                            :stop-parsing-p t)
                                               (make-option :name "bar" :short #\b
                                                            :kind :flag))
                         :positionals (list (make-positional :key :rest :rest-p t)))))
      (with-parsed-argv (inv app '("f" "-xb" "baz"))
        (expect (option-value inv :exec))
        (expect (null (option-value inv :bar)))
        (expect (equal (positional-value inv :rest) '("-b" "baz"))))))

  (it "consumes a bare - as a separated optional value"
    ;; A bare "-" is the stdin/stdout idiom, not an option token -- an
    ;; optional-value option configured to consume a separated value must be
    ;; able to take it, the same way it takes any other non-option token.
    (let ((app (make-app :name "f"
                         :global-options (list (optional-value-option
                                                "output"
                                                :consume-optional-value-p t)))))
      (with-parsed-argv (inv app '("f" "--output" "-"))
        (expect (equal (option-value inv :output) "-"))))))
