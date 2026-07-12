(in-package :cl-cli/tests)

(deftest-with-fixture fish-completion-includes-visible-commands-and-options
    (app (completion-visible-commands-and-options-fixture))
  (assert-completion-searches (app "fish")
    "complete -c 'demo' -f"
    "complete -c 'demo' -n '__fish_seen_subcommand_from compile build' -a 'compile' -d 'Compile sources.'"
    "complete -c 'demo' -n '__fish_seen_subcommand_from compile build' -a 'build' -d 'Compile sources.'"
    "complete -c 'demo' -l verbose -s v -f"
    "complete -c 'demo' -l output -s o -n '__fish_seen_subcommand_from compile build' -r"))

(deftest-with-fixture fish-completion-includes-choice-values
    (app (completion-choice-values-fixture))
  (assert-completion-searches (app "fish")
    "complete -c 'demo' -l profile -n '__fish_seen_subcommand_from compile' -r -a 'dev prod'"))

(deftest-with-fixture fish-completion-can-render-candidate-descriptions
    (app (completion-candidate-descriptions-fixture))
  (assert-completion-searches (app "fish")
    "complete -c 'demo' -l profile -n '__fish_seen_subcommand_from compile' -r -a 'dev' -d 'Local development'"
    "complete -c 'demo' -l profile -n '__fish_seen_subcommand_from compile' -r -a 'prod' -d 'Production release'"))

(deftest-with-fixture fish-completion-includes-negated-boolean-options
    (app (completion-negated-boolean-options-fixture))
  (assert-completion-searches (app "fish")
    " -l threads" " -l no-threads" " -f"))
