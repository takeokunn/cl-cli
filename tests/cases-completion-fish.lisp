(in-package :cl-cli/tests)

(describe-sequential "completion fish"
  (it "includes visible commands and options"
    (let ((app (completion-visible-commands-and-options-fixture)))
      (assert-completion-searches (app "fish")
        "complete -c 'demo' -f"
        ;; Command names are offered before a subcommand is chosen
        ;; (__fish_use_subcommand), not after it is seen.
        (format nil "complete -c 'demo' -n ~A -a 'compile' -d 'Compile sources.'"
                (cl-cli::%completion-shell-quote
                 "__fish_use_subcommand; and not __fish_seen_subcommand_from 'compile' 'build'"))
        (format nil "complete -c 'demo' -n ~A -a 'build' -d 'Compile sources.'"
                (cl-cli::%completion-shell-quote
                 "__fish_use_subcommand; and not __fish_seen_subcommand_from 'compile' 'build'"))
        "complete -c 'demo' -l verbose -s v -f"
        (format nil "complete -c 'demo' -l output -s o -n ~A -r"
                (cl-cli::%completion-shell-quote
                 "__fish_seen_subcommand_from 'compile' 'build'")))))

  (it "includes choice values"
    (let ((app (completion-choice-values-fixture)))
      ;; -f (exclusive) keeps fish from also offering files for a closed choice set.
      (assert-completion-searches (app "fish")
        (format nil "complete -c 'demo' -l profile -n ~A -r -f -a 'dev prod'"
                (cl-cli::%completion-shell-quote
                 "__fish_seen_subcommand_from 'compile'")))))

  (it "renders candidate descriptions"
    (let ((app (completion-candidate-descriptions-fixture)))
      (assert-completion-searches (app "fish")
        (format nil "complete -c 'demo' -l profile -n ~A -r -f -a 'dev' -d 'Local development'"
                (cl-cli::%completion-shell-quote
                 "__fish_seen_subcommand_from 'compile'"))
        (format nil "complete -c 'demo' -l profile -n ~A -r -f -a 'prod' -d 'Production release'"
                (cl-cli::%completion-shell-quote
                 "__fish_seen_subcommand_from 'compile'")))))

  (it "quotes shell-sensitive descriptions and candidates"
    (let ((app (make-completion-fixture
                :command-description "Don't $(run)"
                :command-options (list (make-option :name "profile"
                                                    :kind :value
                                                    :completion-candidates
                                                    '(("dev's" . "Bob's $(danger)")))))))
      (assert-completion-searches (app "fish")
        (cl-cli::%completion-shell-quote "Don't $(run)")
        (cl-cli::%completion-shell-quote "dev's")
        (cl-cli::%completion-shell-quote "Bob's $(danger)"))
      (assert-completion-not-searches (app "fish")
        " -a dev's"
        " -d Bob's $(danger)")))

  (it "includes negated boolean options"
    (let ((app (completion-negated-boolean-options-fixture)))
      (assert-completion-searches (app "fish")
        " -l threads" " -l no-threads" " -f"))))
