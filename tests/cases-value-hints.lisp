(in-package :cl-cli/tests)

(defun value-hint-app ()
  (make-app
   :name "tool"
   :global-options (list (make-option :name "config" :kind :value
                                      :value-hint :file
                                      :description "Config file."))
   :positionals (list (make-positional :key :dir :value-hint :dir))))

(describe-sequential "value hints"
  (it "stores the hint on options and positionals"
    (let ((app (value-hint-app)))
      (expect (eq (option-value-hint (first (app-global-options app))) :file))
      (expect (eq (cl-cli::positional-spec-value-hint (first (app-positionals app))) :dir))))

  (it "emits file/directory completion in bash"
    (let ((text (render-completion (value-hint-app) "bash")))
      (expect (search "compgen -d" text))))

  (it "wires an option :dir hint through the expect-value path in bash"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "outdir" :kind :value
                                                             :value-hint :dir))))
           (text (render-completion app "bash")))
      ;; the option's value slot sets comp_dir and the consumer runs compgen -d;
      ;; -o default gives plain / :file value options filename fallback.
      (assert-searches text
                       "comp_dir=1"
                       "if [[ -n \"$comp_dir\" ]]; then"
                       "compgen -d -- \"$cur\""
                       "complete -o default -F")))

  (it "emits file completion in bash for a file positional"
    (let* ((app (make-app :name "tool"
                          :positionals (list (make-positional :key :f :value-hint :file))))
           (text (render-completion app "bash")))
      (expect (search "compgen -f" text))))

  (it "emits _files in zsh"
    (let* ((app (make-app :name "tool"
                          :positionals (list (make-positional :key :f :value-hint :file))))
           (text (render-completion app "zsh")))
      (expect (search "_files" text))))

  (it "wires option file/dir hints through the zsh value cases"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "config" :kind :value
                                                             :value-hint :file)
                                                (make-option :name "outdir" :kind :value
                                                             :value-hint :dir))))
           (text (render-completion app "zsh")))
      ;; the value case for the option runs _files (file) / _files -/ (dir)
      (assert-searches text (format nil "_files~%        return 0") "_files -/")))

  (it "emits a directory completer in fish"
    (let ((text (render-completion (value-hint-app) "fish")))
      (expect (search "__fish_complete_directories" text))))

  (it "surfaces the hint in help"
    (with-app-help-text (text (value-hint-app))
      (assert-searches text "expects a file" "expects a directory")))

  (it "exposes the hint in json"
    (let ((text (with-string-output (s) (render-json (value-hint-app) s))))
      (assert-searches text "\"valueHint\":\"file\"" "\"valueHint\":\"dir\"")))

  (it "rejects a value hint on a flag"
    (signals-invalid-specification
      (make-option :name "x" :kind :flag :value-hint :file)))

  (it "rejects an unknown value hint"
    (signals-invalid-specification
      (make-positional :key :x :value-hint :socket)))

  (it "does not emit an empty bash case label for a candidate-less value option"
    ;; Regression: a :value option with no :choices / :completion-candidates must
    ;; not produce a bare `)` case label, which is a bash syntax error.
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "output" :kind :value))))
           (text (render-completion app "bash")))
      (expect (null (search (format nil "~%      ) " text) text))))))
