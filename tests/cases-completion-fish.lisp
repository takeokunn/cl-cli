(in-package :cl-cli/tests)

(describe-sequential "completion fish"
  (it "includes visible commands and options"
    (let ((app (completion-visible-commands-and-options-fixture)))
      (assert-completion-searches (app "fish")
        "complete -c 'demo' -f"
        ;; Command names are offered before a subcommand is chosen
        ;; (__fish_use_subcommand), not after it is seen.
        "complete -c 'demo' -n '__fish_use_subcommand; and not __fish_seen_subcommand_from compile build' -a 'compile' -d 'Compile sources.'"
        "complete -c 'demo' -n '__fish_use_subcommand; and not __fish_seen_subcommand_from compile build' -a 'build' -d 'Compile sources.'"
        "complete -c 'demo' -l verbose -s v -f"
        "complete -c 'demo' -l output -s o -n '__fish_seen_subcommand_from compile build' -r")))

  (it "includes choice values"
    (let ((app (completion-choice-values-fixture)))
      ;; -f (exclusive) keeps fish from also offering files for a closed choice set.
      (assert-completion-searches (app "fish")
        "complete -c 'demo' -l profile -n '__fish_seen_subcommand_from compile' -r -f -a 'dev prod'")))

  (it "renders candidate descriptions"
    (let ((app (completion-candidate-descriptions-fixture)))
      (assert-completion-searches (app "fish")
        "complete -c 'demo' -l profile -n '__fish_seen_subcommand_from compile' -r -f -a 'dev' -d 'Local development'"
        "complete -c 'demo' -l profile -n '__fish_seen_subcommand_from compile' -r -f -a 'prod' -d 'Production release'")))

  (it "includes negated boolean options"
    (let ((app (completion-negated-boolean-options-fixture)))
      (assert-completion-searches (app "fish")
        " -l threads" " -l no-threads" " -f"))))
