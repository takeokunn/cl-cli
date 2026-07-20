(in-package :cl-cli/tests)

;;;; Dynamic (runtime __complete) completion for the three flat completers --
;;;; powershell, nushell, elvish. Previously only bash/zsh/fish shelled out to
;;;; the program's __complete callback; these three offered only a static pool.
;;;; The generated scripts here were verified against real pwsh / nu / elvish.

(defun flat-dynamic-app ()
  (make-app
   :name "dyntool"
   :global-options (list (make-option :name "branch" :kind :value
                                      :complete (lambda (p) (declare (ignore p))
                                                  '("main" "dev")))
                         (make-option :name "verbose" :short #\v :kind :flag))
   :commands (make-standard-commands :include-dynamic-p t)))

(defun flat-static-app ()
  "An app with no :complete option -- no dynamic block should be emitted."
  (make-app
   :name "statictool"
   :global-options (list (make-option :name "mode" :kind :value :choices '("a" "b")))
   :commands (make-standard-commands)))

(describe-sequential "flat-shell dynamic completion"
  ;; --- PowerShell ---------------------------------------------------------
  (it "powershell shells out to __complete for a dynamic option"
    (let ((script (render-powershell-completion (flat-dynamic-app))))
      (assert-searches script
                       "$dynamicOptions = @{"
                       "'--branch' = 'branch'"
                       "__complete"
                       "$dynamicOptions.ContainsKey($prevToken)"
                       "return")))

  (it "powershell omits the dynamic block when no option is dynamic"
    (let ((script (render-powershell-completion (flat-static-app))))
      (assert-not-searches script "$dynamicOptions" "__complete")))

  ;; --- Nushell ------------------------------------------------------------
  (it "nushell attaches a custom completer to a dynamic flag and defines it"
    (let ((script (render-nushell-completion (flat-dynamic-app))))
      (assert-searches script
                       "def \"nu-complete dyntool branch\" []"
                       "--branch: string@\"nu-complete dyntool branch\""
                       "^dyntool __complete branch")))

  (it "nushell leaves a non-dynamic value flag as a plain string"
    ;; The subcommand completer (command?: string@"nu-complete ... command") is
    ;; always present; only the value FLAG must stay a bare `: string`.
    (let ((script (render-nushell-completion (flat-static-app))))
      (assert-searches script "--mode: string")
      (assert-not-searches script "nu-complete statictool mode" "--mode: string@")))

  ;; --- Elvish -------------------------------------------------------------
  (it "elvish branches to __complete when the previous word is a dynamic option"
    (let ((script (render-elvish-completion (flat-dynamic-app))))
      (assert-searches script
                       "use str"
                       "var dynamic = ["
                       "&'--branch'='branch'"
                       "has-key $dynamic $prev"
                       "__complete $dynamic[$prev]"
                       "} else {")))

  (it "elvish emits only the static pool when no option is dynamic"
    (let ((script (render-elvish-completion (flat-static-app))))
      (assert-not-searches script "has-key $dynamic" "__complete")
      ;; The static candidates must still be present.
      (assert-searches script "put $@commands"))))
