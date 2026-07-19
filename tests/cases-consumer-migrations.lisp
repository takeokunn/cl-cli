(in-package :cl-cli/tests)

(deftest-queries consumer-migration-contracts
    ((consumer-migration-rulebase))
  ("cl-cc exposes compile"
   (command cl-cc compile)
   :succeeds)
  ("cl-cc compile keeps build alias"
   (command-alias cl-cc compile build)
   :succeeds)
  ("cl-cc compile requires input positional"
   (command-positional-required cl-cc compile input)
   :succeeds)
  ("cl-cc script option stops parsing"
   (global-option-stop-parsing cl-cc script)
   :succeeds)
  ("cl-tmux keeps attach as default command"
   (default-command cl-tmux attach)
   :succeeds)
  ("cl-tmux display command forwards tail verbatim"
   (command-option-stop-parsing cl-tmux display command)
   :succeeds)
  ("private-trade-fx instrument remains required"
   (global-option-required private-trade-fx instrument)
   :succeeds)
  ("private-trade-fx config depends on profile"
   (global-option-requires private-trade-fx config profile)
   :succeeds)
  ("private-trade-fx profile keeps env binding"
   (global-option-env-var private-trade-fx profile fx_profile)
   :succeeds)
  ("private-trade-fx instrument choices remain explicit"
   (global-option-choice private-trade-fx instrument ?choice)
   :set
   (((?choice . usd_jpy))
    ((?choice . eur_usd))))
  ("nshell command option stops parsing"
   (global-option-stop-parsing nshell command)
   :succeeds)
  ("nshell keeps optional script mode and argv tail"
   (app-positional nshell script)
   :succeeds)
  ("nshell script stays optional"
   (app-positional-required nshell script)
   :fails)
  ("nshell keeps script argv rest positional"
   (app-positional-rest nshell script-argv)
   :succeeds))
