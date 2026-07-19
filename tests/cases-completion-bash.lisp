(in-package :cl-cli/tests)

(describe-sequential "completion bash"
  (it "includes visible commands and options"
    (let ((app (completion-visible-commands-and-options-fixture)))
      (assert-completion-searches (app)
        "_demo_completion()"
        "complete -F _demo_completion 'demo'"
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
      (assert-completion-not-searches (app) "secret" "--secret-flag"))))
