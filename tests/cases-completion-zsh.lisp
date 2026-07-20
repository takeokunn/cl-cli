(in-package :cl-cli/tests)

(describe-sequential "completion zsh"
  (it "completes nested subcommands with accumulated option scope"
    (let* ((app (make-app :name "demo"
                          :global-options (list (make-option :name "verbose" :kind :flag))
                          :commands (list (make-command
                                           :name "remote"
                                           :options (list (make-option :name "porcelain" :kind :flag))
                                           :subcommands (list (make-command :name "add")
                                                              (make-command :name "remove"))))))
           (text (render-completion app "zsh")))
      (assert-searches text
                       "case \"${words[3]}\" in"
                       "_describe 'commands' subcommand_specs"
                       ;; the add clause carries the accumulated option scope
                       "--verbose"
                       "--porcelain")))

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
