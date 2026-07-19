(in-package :cl-cli/tests)

(describe-sequential "validation specification"
  (it "maps invalid option parser errors to usage errors"
    (let* ((positive (make-option
                      :name "count"
                      :kind :value
                      :parser (lambda (value)
                                (let ((number (parse-integer value)))
                                  (unless (plusp number)
                                    (error "Expected positive integer."))
                                  number))))
           (app (make-app :name "trade" :global-options (list positive))))
      (signals cli-invalid-option-value
        (parse-argv app '("trade" "--count" "0")))))

  (it "rejects duplicate option names"
    (let ((left (make-option :name "verbose" :short #\v))
          (right (make-option :name "version" :short #\v)))
      (signals-invalid-specification
        (make-app :name "demo" :global-options (list left right)))))

  (it "rejects options whose keys collide despite distinct case-sensitive short names"
    ;; OPTION-KEYWORD downcases its argument, so single-character names "-a"
    ;; and "-A" (deliberately case-sensitive as CLI tokens) both resolve to
    ;; the same :A key -- without this check the two specs would silently
    ;; share one storage slot instead of being rejected as a spec error.
    (let ((left (make-option :short #\a :kind :flag))
          (right (make-option :short #\A :kind :flag)))
      (signals-invalid-specification
        (make-app :name "demo" :global-options (list left right)))))

  (it "rejects a user option that reuses the reserved :help key"
    ;; BUILT-IN-OPTION-P/BUILT-IN-OPTION-ACTION key off OPTION-KEY's value
    ;; alone, so an ordinary option given :key :help would hijack dispatch
    ;; into the help action regardless of its own :kind.
    (signals-invalid-specification
      (make-app :name "demo"
                :global-options (list (make-option :key :help
                                                   :name "output"
                                                   :kind :value)))))

  (it "rejects a user option that reuses the reserved :version key"
    (signals-invalid-specification
      (make-app :name "demo"
                :version "1.0.0"
                :global-options (list (make-option :key :version
                                                   :name "output"
                                                   :kind :value)))))

  (it "rejects duplicate command names"
    (let ((left (make-command :name "build"))
          (right (make-command :name "build")))
      (signals-invalid-specification
        (make-app :name "demo" :commands (list left right)))))

  (it "rejects duplicate command aliases"
    (let ((left (make-command :name "build"
                              :aliases '("compile")))
          (right (make-command :name "release"
                               :aliases '("compile"))))
      (signals-invalid-specification
        (make-app :name "demo" :commands (list left right)))))

  (it "requires non-empty app names"
    (signals-invalid-specification
      (make-app)
      (make-app :name "")))

  (it "requires non-empty command names"
    (signals-invalid-specification
      (make-command)
      (make-command :name "")))

  (it "requires non-empty positional name when key is omitted"
    (signals-invalid-specification
      (make-positional :name "")))

  (it "requires non-empty option names"
    (signals-invalid-specification
      (make-option :name "")
      (make-option :aliases '(""))))

  (it "requires non-empty option value names"
    (signals-invalid-specification
      (make-option :name "output"
                   :kind :value
                   :value-name "")))

  (it "requires non-empty option env vars"
    (signals-invalid-specification
      (make-option :name "profile"
                   :kind :value
                   :env-var "")
      (make-option :name "profile"
                   :kind :value
                   :env-vars '("PRIMARY_PROFILE" ""))))

  (it "requires non-empty option choices"
    (signals-invalid-specification
      (make-option :name "mode"
                   :kind :value
                   :choices '("dev" ""))))

  (it "requires non-empty completion candidates"
    (signals-invalid-specification
      (make-option :name "mode"
                   :kind :value
                   :completion-candidates '(""))
      (make-option :name "mode"
                   :kind :value
                   :completion-candidates '(("dev" . "")))))

  (it "requires non-empty command aliases"
    (signals-invalid-specification
      (make-command :name "build" :aliases '(""))))

  (it "requires non-empty command groups and examples"
    (signals-invalid-specification
      (make-command :name "build"
                    :group "")
      (make-command :name "build"
                    :examples '("build src" ""))
      (make-app :name "demo"
                :examples '("demo build" ""))))

  (it "requires root rest positional to be last"
    (signals-invalid-specification
      (make-app :name "demo"
                :positionals (list (make-positional :key :args :rest-p t)
                                   (make-positional :key :target :required-p t)))))

  (it "requires command rest positional to be last"
    (signals-invalid-specification
      (make-app :name "demo"
                :commands (list (make-command
                                 :name "run"
                                 :positionals (list (make-positional :key :args :rest-p t)
                                                    (make-positional :key :target :required-p t)))))))

  (it "rejects a required root positional following an optional one"
    ;; Positionals are assigned tokens greedily in declared order with no
    ;; backtracking, so a required positional after an optional one could
    ;; never receive a value even when one was supplied.
    (signals-invalid-specification
      (make-app :name "demo"
                :positionals (list (make-positional :key :first)
                                   (make-positional :key :second :required-p t)))))

  (it "rejects a required command positional following an optional one"
    (signals-invalid-specification
      (make-app :name "demo"
                :commands (list (make-command
                                 :name "run"
                                 :positionals (list (make-positional :key :first)
                                                    (make-positional :key :second :required-p t)))))))

  (it "rejects duplicate root positional keys"
    (signals-invalid-specification
      (make-app :name "demo"
                :positionals (list (make-positional :key :target)
                                   (make-positional :key :target)))))

  (it "rejects duplicate command positional keys"
    (signals-invalid-specification
      (make-app :name "demo"
                :commands (list (make-command
                                 :name "run"
                                 :positionals (list (make-positional :key :target)
                                                    (make-positional :key :target)))))))

  (it "requires default command to resolve to a known command"
    (caught-signal= (cli-invalid-specification condition)
        (make-app :name "demo"
                  :commands (list (make-command :name "build"))
                  :default-command "deploy")
      (:searches cli-error-message "Unknown :default-command for demo: deploy")))

  (it "rejects command options colliding with global options"
    (let ((verbose (make-option :name "verbose" :short #\v))
          (build (make-command :name "build"
                               :options (list (make-option :name "verbose")))))
      (signals-invalid-specification
        (make-app :name "demo"
                  :global-options (list verbose)
                  :commands (list build)))))

  (it "rejects shell-unsafe app names"
    (signals-invalid-specification
      (make-app :name "foo; touch pwned #")
      (make-app :name "foo$(id)")
      (make-app :name "foo bar")))

  (it "rejects shell-unsafe option names"
    (signals-invalid-specification
      (make-option :name "foo; rm -rf ~" :kind :flag)
      (make-option :name "bad name" :kind :value)
      (make-option :name "x`id`" :kind :flag)))

  (it "rejects shell-unsafe command names and aliases"
    (signals-invalid-specification
      (make-command :name "foo) ; touch pwned ;#")
      (make-command :name "ok" :aliases '("a$(id)"))))

  (it "accepts conventional identifier names"
    (let ((app (make-app
                :name "cl-cc.v2"
                :global-options (list (make-option :name "dry_run" :kind :flag))
                :commands (list (make-command :name "build"
                                              :aliases '("b"))))))
      (expect (string= "cl-cc.v2" (app-name app))))))
