(in-package :cl-cli/tests)

(deftest-with-fixture zsh-completion-includes-visible-commands-and-options
    (app (completion-visible-commands-and-options-fixture))
  (assert-completion-searches (app "zsh")
    "#compdef demo"
    "_demo_completion() {"
    "_describe 'commands' command_specs"
    "option_specs=("
    "command_option_specs=("
    "--verbose"
    "-v"
    "--output"
    "-o"
    "'compile:Compile sources.'"
    "'build:alias for compile'"))

(deftest-with-fixture zsh-completion-includes-choice-values
    (app (completion-choice-values-fixture))
  (assert-completion-searches (app "zsh")
    "case \"$previous_word\" in"
    "case \"$current_word\" in"
    "'--profile')"
    "'--profile=*')"
    "compadd -Q -S '' -- 'dev' 'prod'"))

(deftest-with-fixture zsh-completion-can-render-candidate-descriptions
    (app (completion-candidate-descriptions-fixture))
  (assert-completion-searches (app "zsh")
    "_describe 'values' value_candidates"
    "'dev:Local development'"
    "'prod:Production release'"))

(deftest-with-fixture zsh-completion-includes-negated-boolean-options
    (app (completion-negated-boolean-options-fixture))
  (assert-completion-searches (app "zsh")
    "--threads"
    "--no-threads"))
