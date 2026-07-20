(in-package :cl-cli/tests)

(describe-sequential "completion bash"
  (it "consumes a pending expect_value into candidate completion"
    ;; Regression: the `case "$prev"` scan set expect_value / value_source but
    ;; nothing turned them into COMPREPLY, so `--opt <TAB>` completed nothing.
    (let* ((app (make-app :name "demo"
                          :global-options (list (make-option :name "mode" :kind :value
                                                             :choices '("dev" "prod")))))
           (text (render-completion app "bash")))
      (assert-searches text
                       "_init_completion -s"
                       "expect_value"
                       "if [[ -n \"$expect_value\" || -n \"$expect_optional_value\" ]]; then"
                       "COMPREPLY=( $(compgen -W \"$value_source\" -- \"$cur\") )")))

  (it "completes nested subcommands and their option scope"
    (let* ((app (make-app :name "demo"
                          :global-options (list (make-option :name "verbose" :kind :flag))
                          :commands (list (make-command
                                           :name "remote"
                                           :options (list (make-option :name "porcelain" :kind :flag))
                                           :subcommands (list (make-command :name "add")
                                                              (make-command :name "remove"))))))
           (text (render-completion app "bash")))
      (assert-searches text
                       ;; nested subcommand names offered at the next word
                       "case \"${words[2]}\" in"
                       "compgen -W 'add remove'"
                       ;; the leaf 'add' scope includes global + parent options
                       "case \"remote/add:$cur\" in"
                       ;; global-option fallback is guarded so it does not shadow
                       ;; subcommand option completion
                       "case \"${words[1]}\" in")))

  (it "includes visible commands and options"
    (let ((app (completion-visible-commands-and-options-fixture)))
      (assert-completion-searches (app)
        "_demo_completion()"
        "complete -o default -F _demo_completion 'demo'"
        "compgen -W '--verbose -v -h --help -V --version'"
        "compgen -W 'compile build'"
        "compgen -W '--verbose -v --output -o -h --help -V --version'")))

  (it "hides version when app version is missing"
    (let ((app (make-completion-fixture
                :global-options (list (make-option :name "verbose"
                                                   :short #\v
                                                   :kind :flag)))))
      (assert-completion-searches (app)
        "compgen -W '--verbose -v -h --help'")
      (assert-completion-not-searches (app)
        "-V --version")))

  (it "includes command and option aliases"
    (let ((app (make-completion-fixture
                :global-options (list (make-option :name "verbose"
                                                   :aliases '("chatty")
                                                   :kind :flag))
                :command-aliases '("build" "c")
                :command-description "Compile sources."
                :command-options (list (make-option :name "output"
                                                    :short #\o
                                                    :aliases '("out")
                                                    :kind :value
                                                    :choices '("bin" "obj"))))))
      (assert-completion-searches (app)
        "compgen -W 'compile build c'"
        "--verbose --chatty"
        "--output -o --out"
        "'compile:--output'|'compile:-o'|'compile:--out') expect_value=1 value_source='bin obj' ;;"
        "--chatty")))

  (it "allows command aliases to enable command option completion"
    (let ((app (make-completion-fixture
                :command-aliases '("build" "c")
                :command-options (list (make-option :name "output"
                                                    :short #\o
                                                    :aliases '("out")
                                                    :kind :value
                                                    :choices '("bin" "obj"))))))
      (assert-completion-searches (app)
        "'compile'|'build'|'c')"
        "'compile:--output=*'|'compile:-o=*'|'compile:--out=*'")))

  (it "includes choice values"
    (let ((app (completion-choice-values-fixture)))
      (assert-completion-searches (app)
        "value_source='dev prod'"
        "compgen -W \"$value_source\" -- \"$cur\""
        "'compile:--profile=*'")))

  (it "uses completion candidates without choices"
    (let ((app (completion-candidate-descriptions-fixture)))
      (assert-completion-searches (app)
        "value_source='dev prod'"
        "'compile:--profile=*'")))

  (it "includes negated boolean options"
    (let ((app (completion-negated-boolean-options-fixture)))
      (assert-completion-searches (app)
        "--threads --no-threads -h --help" "'compile'")))

  (it "hides hidden commands and options"
    (let ((app (completion-hidden-commands-and-options-fixture)))
      (assert-completion-searches (app) "visible" "--visible-flag")
      (assert-completion-not-searches (app) "secret" "--secret-flag")))

  (it "matches command-scoped attached-value candidates against the command-prefixed current word"
    ;; The value_source case labels for a command option are rendered as
    ;; "command:--option=*", so the case statement selecting on them must
    ;; switch on "command:$cur", not the bare "$cur" -- otherwise the labels
    ;; can never match and attached-value completion silently never fires.
    (let ((app (make-completion-fixture
                :command-options (list (make-option :name "output"
                                                    :short #\o
                                                    :kind :value
                                                    :choices '("bin" "obj"))))))
      (assert-completion-searches (app)
        "case \"compile:$cur\" in"))))
