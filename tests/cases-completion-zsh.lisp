(in-package :cl-cli/tests)

(describe-sequential "completion zsh"
  (it "includes visible commands and options"
    (let ((app (completion-visible-commands-and-options-fixture)))
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
        "'build:alias for compile'")))

  (it "includes choice values"
    (let ((app (completion-choice-values-fixture)))
      (assert-completion-searches (app "zsh")
        "case \"$previous_word\" in"
        "case \"$current_word\" in"
        "'--profile')"
        "'--profile=*')"
        "compadd -Q -S '' -- 'dev' 'prod'")))

  (it "renders candidate descriptions"
    (let ((app (completion-candidate-descriptions-fixture)))
      (assert-completion-searches (app "zsh")
        "_describe 'values' value_candidates"
        "'dev:Local development'"
        "'prod:Production release'")))

  (it "includes negated boolean options"
    (let ((app (completion-negated-boolean-options-fixture)))
      (assert-completion-searches (app "zsh")
        "--threads"
        "--no-threads"))))
