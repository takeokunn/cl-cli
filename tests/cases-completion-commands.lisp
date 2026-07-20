(in-package :cl-cli/tests)

(describe-sequential "completion commands"
  (it "prints completion scripts"
    (let* ((command (make-completion-command))
           (app (make-app :name "demo"
                          :commands (list command))))
      (assert-completion-searches-for-shells (app)
        ("bash"
         "#!/usr/bin/env bash"
         "# bash completion for demo"
         "_demo_completion() {"
         "complete -o default -F _demo_completion 'demo'")
        ("zsh"
         "#compdef demo"
         "_demo_completion() {"
         "compdef _demo_completion 'demo'")
        ("fish"
         "complete -c 'demo' -f")
        ("powershell"
         "# PowerShell completion for demo"
         "Register-ArgumentCompleter -Native -CommandName 'demo'")
        ("pwsh"
         "# PowerShell completion for demo")
        ("nushell"
         "# Nushell completion for demo"
         "export extern \"demo\" [")
        ("nu"
         "# Nushell completion for demo")
        ("elvish"
         "# Elvish completion for demo"
         "set edit:completion:arg-completer['demo'] ="))))

  (it "rejects unsupported shells"
    (let ((app (make-app :name "demo"
                         :commands (list (make-completion-command)))))
      (signals cli-invalid-positional-value
        (parse-argv app '("demo" "completion" "tcsh")))))

  (it "standard commands default to help and version"
    (let ((commands (make-standard-commands)))
      (expect (= 2 (length commands)))
      (expect (string= "help" (command-name (first commands))))
      (expect (string= "version" (command-name (second commands))))))

  (it "standard commands can include completion"
    (let* ((commands (make-standard-commands :include-completion-p t))
           (names (mapcar #'command-name commands)))
      (expect (equal '("help" "version" "completion") names))))

  (it "standard commands can disable individual entries"
    (let ((commands (make-standard-commands :include-help-p nil
                                            :include-version-p nil
                                            :include-completion-p t)))
      (expect (= 1 (length commands)))
      (expect (string= "completion" (command-name (first commands))))))

  (it "standard commands support app dispatch"
    (let* ((app (make-app :name "demo"
                          :version "1.2.3"
                          :commands (append
                                     (make-standard-commands :include-completion-p t)
                                     (list (make-command :name "serve")))))
           (version-exit-code nil)
           (version-text (with-string-output (stdout)
                           (setf version-exit-code (run-app app
                                                            :argv '("demo" "version")
                                                            :stdout stdout))))
           (completion-text (with-string-output (completion-output)
                              (render-completion app "bash" completion-output))))
      (expect (zerop version-exit-code))
      (assert-searches version-text "demo 1.2.3")
      (assert-searches completion-text "completion")))

  (it "version without app version prints only the app name"
    (let* ((app (make-app :name "demo"
                          :commands (list (make-version-command))))
           (exit-code nil)
           (text (with-string-output (stdout)
                   (setf exit-code (run-app app
                                            :argv '("demo" "version")
                                            :stdout stdout)))))
      (expect (zerop exit-code))
      (expect (string= (concatenate 'string "demo" (string #\Newline)) text))))

  (it "render-completion rejects unsupported shells"
    (signals cli-invalid-positional-value
      (render-completion (make-app :name "demo") "tcsh")))

  (it "renders a PowerShell native argument completer"
    (let* ((app (make-app :name "demo"
                          :global-options (list (make-option :name "verbose"
                                                             :short #\v
                                                             :kind :count))
                          :commands (list (make-command
                                           :name "compile"
                                           :aliases '("build")
                                           :options (list (make-option :name "output"
                                                                       :short #\o
                                                                       :kind :value))))))
           (text (render-powershell-completion app)))
      (assert-searches text
                       "Register-ArgumentCompleter -Native -CommandName 'demo'"
                       "$commands = @('compile', 'build')"
                       "'--verbose'"
                       "$commandOptions = @{"
                       "'compile' = @('--output', '-o')"
                       "'build' = @('--output', '-o')"
                       "$_.StartsWith($wordToComplete, [System.StringComparison]::Ordinal)"
                       "CompletionResult")))

  (it "does not treat PowerShell completion prefixes as wildcard patterns"
    (let ((text (render-powershell-completion (make-app :name "demo"))))
      (assert-searches text "$_.StartsWith($wordToComplete, [System.StringComparison]::Ordinal)")
      (assert-not-searches text "-like \"$wordToComplete*\"")))

  (it "omits hidden entities from the PowerShell completer"
    (let* ((app (make-app :name "demo"
                          :global-options (list (flag-option "secret" :hidden-p t))
                          :commands (list (make-command :name "ghost" :hidden-p t))))
           (text (render-powershell-completion app)))
      (assert-not-searches text "secret" "ghost")))

  (it "renders a Nushell extern with commands and global flags"
    (let* ((app (make-app :name "demo"
                          :global-options (list (make-option :name "verbose"
                                                             :short #\v
                                                             :kind :flag
                                                             :description "Be loud.")
                                                (make-option :name "output"
                                                             :short #\o
                                                             :kind :value))
                          :commands (list (make-command :name "compile")
                                          (make-command :name "test"))))
           (text (render-nushell-completion app)))
      (assert-searches text
                       "def \"nu-complete demo command\" []"
                       "\"compile\", \"test\""
                       "export extern \"demo\" ["
                       "command?: string@\"nu-complete demo command\""
                       "--verbose(-v)  # Be loud."
                       "--output(-o): string"
                       "--help(-h)")))

  (it "omits hidden entities from the Nushell completer"
    (let* ((app (make-app :name "demo"
                          :global-options (list (flag-option "secret" :hidden-p t))
                          :commands (list (make-command :name "ghost" :hidden-p t))))
           (text (render-nushell-completion app)))
      (assert-not-searches text "secret" "ghost")))

  (it "renders an Elvish arg-completer with commands and options"
    (let* ((app (make-app :name "demo"
                          :global-options (list (make-option :name "verbose"
                                                             :short #\v
                                                             :kind :flag))
                          :commands (list (make-command :name "compile")
                                          (make-command :name "test"))))
           (text (render-elvish-completion app)))
      (assert-searches text
                       "set edit:completion:arg-completer['demo'] = {|@words|"
                       "var commands = ['compile' 'test']"
                       "'--verbose'"
                       "put $@commands"
                       "put $@options")))

  (it "omits hidden entities from the Elvish completer"
    (let* ((app (make-app :name "demo"
                          :global-options (list (flag-option "secret" :hidden-p t))
                          :commands (list (make-command :name "ghost" :hidden-p t))))
           (text (render-elvish-completion app)))
      (assert-not-searches text "secret" "ghost")))

  (it "strips controls from flat shell completion static fields"
    (let* ((bad-candidate (format nil "bad~Cvalue" #\Newline))
           (bad-description (format nil "first~Csecond~Cdone" #\Tab #\Esc))
           (app (make-app :name "demo"
                          :global-options
                          (list (make-option :name "verbose"
                                             :kind :flag
                                             :description bad-description))
                          :positionals
                          (list (make-positional :key :target
                                                 :completion-candidates
                                                 (list bad-candidate)))
                          :commands (list (make-command :name "run"))))
           (powershell (render-powershell-completion app))
           (nushell (render-nushell-completion app))
           (elvish (render-elvish-completion app)))
      (dolist (text (list powershell nushell elvish))
        (assert-not-searches text bad-candidate bad-description))
      (assert-searches powershell "'bad value'")
      (assert-searches nushell "\"bad value\"" "first seconddone")
      (assert-searches elvish "'bad value'")))

  (it "renderers return the script as a string when no stream is given"
    (let ((app (make-app :name "demo"
                         :global-options (list (make-option :name "verbose" :kind :flag))
                         :commands (list (make-command :name "serve")))))
      ;; With no stream, each renderer returns exactly what the stream form
      ;; writes, so the documented `(write-string (render-completion ...))`
      ;; pattern works instead of returning no values.
      (dolist (shell '("bash" "zsh" "fish" "powershell" "nushell" "elvish"))
        (let ((returned (render-completion app shell))
              (written (with-string-output (out) (render-completion app shell out))))
          (expect (stringp returned))
          (expect (plusp (length returned)))
          (expect (string= returned written))))
      (expect (string= (render-bash-completion app)
                       (with-string-output (out) (render-bash-completion app out))))
      (expect (string= (render-zsh-completion app)
                       (with-string-output (out) (render-zsh-completion app out))))
      (expect (string= (render-fish-completion app)
                       (with-string-output (out) (render-fish-completion app out))))
      (expect (string= (render-powershell-completion app)
                       (with-string-output (out) (render-powershell-completion app out))))
      (expect (string= (render-nushell-completion app)
                       (with-string-output (out) (render-nushell-completion app out))))
      (expect (string= (render-elvish-completion app)
                       (with-string-output (out) (render-elvish-completion app out)))))))
