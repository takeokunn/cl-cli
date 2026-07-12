(in-package :cl-cli/tests)

(deftest-with-fixture bash-completion-includes-visible-commands-and-options
    (app (completion-visible-commands-and-options-fixture))
  (assert-completion-searches (app)
    "_demo_completion()"
    "complete -F _demo_completion 'demo'"
    "compgen -W '--verbose -v -h --help -V --version'"
    "compgen -W 'compile build'"
    "compgen -W '--verbose -v --output -o -h --help -V --version'"))

(deftest-with-fixture bash-completion-hides-version-when-app-version-is-missing
    (app (make-completion-fixture
          :global-options (list (make-option :name "verbose"
                                             :short #\v
                                             :kind :flag))))
  (assert-completion-searches (app)
    "compgen -W '--verbose -v -h --help'")
  (assert-completion-not-searches (app)
    "-V --version"))

(deftest-with-fixture completion-includes-command-and-option-aliases
    (app (make-completion-fixture
          :global-options (list (make-option :name "verbose"
                                             :aliases '("chatty")
                                             :kind :flag))
          :command-aliases '("build" "c")
          :command-description "Compile sources."
          :command-options (list (make-option :name "output"
                                               :short #\o
                                               :aliases '("out")
                                               :kind :value
                                               :choices '("bin" "obj")))))
  (assert-completion-searches (app)
    "compgen -W 'compile build c'"
    "--verbose --chatty"
    "--output -o --out"
    "'compile:--output'|'compile:-o'|'compile:--out') expect_value=1 value_source='bin obj' ;;"
    "--chatty"))

(deftest-with-fixture bash-completion-command-aliases-enable-command-option-completion
    (app (make-completion-fixture
          :command-aliases '("build" "c")
          :command-options (list (make-option :name "output"
                                               :short #\o
                                               :aliases '("out")
                                               :kind :value
                                               :choices '("bin" "obj")))))
  (assert-completion-searches (app)
    "'compile'|'build'|'c')"
    "'compile:--output=*'|'compile:-o=*'|'compile:--out=*'"))

(deftest-with-fixture bash-completion-includes-choice-values
    (app (completion-choice-values-fixture))
  (assert-completion-searches (app)
    "value_source='dev prod'"
    "compgen -W \"$value_source\" -- \"$cur\""
    "'compile:--profile=*'"))

(deftest-with-fixture bash-completion-can-use-completion-candidates-without-choices
    (app (completion-candidate-descriptions-fixture))
  (assert-completion-searches (app)
    "value_source='dev prod'"
    "'compile:--profile=*'"))

(deftest-with-fixture bash-completion-includes-negated-boolean-options
    (app (completion-negated-boolean-options-fixture))
  (assert-completion-searches (app)
    "--threads --no-threads -h --help" "'compile'"))

(deftest-with-fixture bash-completion-hides-hidden-commands-and-options
    (app (completion-hidden-commands-and-options-fixture))
  (assert-completion-searches (app) "visible" "--visible-flag")
  (assert-completion-not-searches (app) "secret" "--secret-flag"))
