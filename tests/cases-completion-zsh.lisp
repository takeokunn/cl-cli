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

  (it "quotes shell-sensitive descriptions and candidates"
    (let ((app (make-completion-fixture
                :command-description "Don't $(run)"
                :command-options (list (make-option :name "profile"
                                                    :kind :value
                                                    :completion-candidates
                                                    '(("dev's" . "Bob's $(danger)")))))))
      (assert-completion-searches (app "zsh")
        (cl-cli::%completion-shell-quote "compile:Don't $(run)")
        (cl-cli::%completion-shell-quote "dev's:Bob's $(danger)"))
      (assert-completion-not-searches (app "zsh")
        "compile:Don't $(run)"
        "dev's:Bob's $(danger)")))

  (it "normalizes zsh candidate descriptions"
    (let* ((escape (string #\Escape))
           (description (format nil "Bob:close]run~A[31m" escape))
           (app (make-completion-fixture
                 :command-options (list (make-option :name "profile"
                                                     :kind :value
                                                     :completion-candidates
                                                     `(("dev" . ,description)))))))
      (assert-completion-searches (app "zsh")
        (cl-cli::%completion-shell-quote
         (format nil "dev:~A"
                 (cl-cli::%completion-zsh-describe-field description))))
      (assert-completion-not-searches (app "zsh")
        "dev:Bob:close]run"
        escape)))

  (it "normalizes zsh command description records"
    (let* ((escape (string #\Escape))
           (app (make-app
                 :name "demo"
                 :commands (list (make-command
                                  :name "compile"
                                  :aliases '("build")
                                  :description (format nil "group:one~A[31m" escape)))))
           (text (render-completion app "zsh")))
      (assert-searches text
                       (cl-cli::%completion-shell-quote "compile:group one[31m")
                       (cl-cli::%completion-shell-quote "build:alias for compile"))
      (assert-not-searches text
                           "compile:group:one"
                           escape)))

  (it "normalizes zsh option spec fields"
    (let* ((escape (string #\Escape))
           (description (format nil "close]group:one~A[31m" escape))
           (placeholder "VAL:UE]NAME")
           (app (make-app
                 :name "demo"
                 :global-options (list (make-option :name "profile"
                                                     :kind :value
                                                     :description description
                                                     :value-name placeholder))))
           (text (render-completion app "zsh")))
      (assert-searches text
                       (cl-cli::%completion-shell-quote
                        (format nil "--profile[~A]:~A:"
                                (cl-cli::%completion-zsh-arguments-field
                                 description)
                                (cl-cli::%completion-zsh-arguments-field
                                 placeholder))))
      (assert-not-searches text
                           "close]group:one"
                           "VAL:UE]NAME"
                           escape)))

  (it "includes negated boolean options"
    (let ((app (completion-negated-boolean-options-fixture)))
      (assert-completion-searches (app "zsh")
        "--threads"
        "--no-threads"))))
