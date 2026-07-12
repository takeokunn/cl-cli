(in-package :cl-cli/tests)

(deftest help-includes-option-metadata
  (let ((app (make-app
              :name "demo"
              :global-options
              (list (make-option :name "profile"
                                 :kind :value
                                 :description "Runtime profile."
                                 :multiple-p t
                                 :default "dev"
                                 :env-var "APP_PROFILE"
                                 :choices '("dev" "prod")
                                 :required-p t)))))
    (with-app-help-text (text app)
      (assert-searches text "Runtime profile. (repeatable; required; default: dev; env: APP_PROFILE; choices: dev | prod)"))
    t))

(deftest help-includes-option-relationship-metadata
  (let ((app (make-app
              :name "demo"
              :global-options
              (list (make-option :name "profile"
                                 :kind :value)
                    (make-option :name "config"
                                 :kind :value
                                 :description "Config file."
                                 :requires '(:profile)
                                 :conflicts-with '("token"))
                    (make-option :name "token"
                                 :kind :value)))))
    (with-app-help-text (text app)
      (assert-searches text "Config file. (requires: --profile; conflicts: --token)"))
    t))

(deftest help-hides-hidden-option-relationship-targets
  (let ((app (make-app
              :name "demo"
              :global-options
              (list (make-option :name "profile"
                                 :kind :value)
                    (make-option :name "internal-token"
                                 :kind :value
                                 :hidden-p t)
                    (make-option :name "config"
                                 :kind :value
                                 :description "Config file."
                                 :requires '(:profile :internal-token)
                                 :conflicts-with '("internal-token"))))))
    (with-app-help-text (text app)
      (assert-searches text "Config file. (requires: --profile)")
      (assert-not-searches text "internal-token" "conflicts:"))
    t))

(deftest help-renders-negated-boolean-option-names
  (let ((app (make-app
              :name "demo"
              :global-options
              (list (make-option :name "threads"
                                 :kind :boolean)))))
    (with-app-help-text (text app)
      (assert-searches text "--threads, --no-threads"))
    t))

(deftest help-surfaces-command-aliases-and-option-aliases
  (let* ((command (make-command :name "compile"
                                :aliases '("build" "c")
                                :description "Compile sources."))
         (app (make-app
               :name "demo"
               :global-options
               (list (make-option :name "verbose"
                                  :aliases '("chatty")
                                  :kind :flag))
               :commands (list command))))
    (with-app-help-text (text app)
      (assert-searches text "compile (build, c)" "--verbose, --chatty"))
    t))

(deftest help-command-respects-run-app-stdout
  (let* ((help-command (make-help-command))
         (app (make-app :name "demo"
                        :summary "Demo app."
                        :commands (list help-command)))
         (exit-code nil)
         (text (with-string-output (stdout)
                 (setf exit-code (run-app app :argv '("demo" "help") :stdout stdout)))))
    (is (zerop exit-code))
    (assert-searches text "Usage: demo <command> [args]")
    t))

(deftest command-usage-errors-preserve-command-context
  (let* ((command (make-command
                   :name "run"
                   :options (list (make-option :name "config"
                                               :kind :value
                                               :required-p t))))
         (app (make-app :name "demo"
                        :commands (list command))))
    (caught-signal= (cli-missing-option-value condition)
        (parse-argv app '("demo" "run"))
      (:eq cli-usage-error-app app)
      (:eq cli-usage-error-command command))
    t))

(deftest run-app-prints-command-help-for-command-usage-errors
  (let* ((command (make-command
                   :name "run"
                   :options (list (make-option :name "config"
                                               :kind :value
                                               :required-p t))))
         (app (make-app :name "demo" :commands (list command)))
         (exit-code nil)
         (text (with-string-output (stderr)
                 (setf exit-code (run-app app
                                          :argv '("demo" "run")
                                          :stderr stderr
                                          :stdout (make-string-output-stream))))))
    (is (= exit-code 64))
    (assert-searches text "Missing required option" "Usage: demo run [options]")
    t))

(deftest run-app-parses-aliases-without-warnings
  (let* ((app (make-app
               :name "demo"
               :global-options
               (list (make-option :name "verbose"
                                  :aliases '("chatty")
                                  :kind :flag))))
         (exit-code nil)
         (text (with-string-output (stderr)
                 (setf exit-code (run-app app
                                          :argv '("demo" "--chatty")
                                          :stderr stderr
                                          :stdout (make-string-output-stream))))))
    (is (zerop exit-code))
    (is (string= text ""))
    t))

(deftest run-app-returns-70-for-unhandled-handler-errors
  (let* ((app (make-app :name "demo"
                        :handler (lambda (invocation)
                                   (declare (ignore invocation))
                                   (error "boom"))))
         (exit-code nil)
         (text (with-string-output (stderr)
                 (setf exit-code (run-app app
                                          :argv '("demo")
                                          :stderr stderr
                                          :stdout (make-string-output-stream))))))
    (is (= exit-code 70))
    (assert-searches text "Internal error: boom")
    t))

(deftest app-help-hides-version-when-app-version-is-missing
  (let ((app (make-app :name "demo")))
    (with-app-help-text (text app)
      (assert-searches text "Global Options:" "-h, --help")
      (assert-not-searches text "-V, --version"))
    t))

(deftest app-help-hides-version-for-whitespace-version-string
  (let ((app (make-app :name "demo" :version "   ")))
    (with-app-help-text (text app)
      (assert-not-searches text "-V, --version"))
    t))

(deftest app-help-shows-command-aliases
  (let* ((command (make-command :name "compile"
                                :aliases '("build" "c")
                                :description "Compile sources."))
         (app (make-app :name "demo"
                        :version "1.0.0"
                        :commands (list command))))
    (with-app-help-text (text app)
      (assert-searches text "compile (build, c)" "-V, --version"))
    t))

(deftest app-help-groups-commands-by-category
  (let* ((compile (make-command :name "compile"
                                :group "Build"
                                :description "Compile sources."))
         (test (make-command :name "test"
                             :group "Build"
                             :description "Run tests."))
         (doctor (make-command :name "doctor"
                               :group "Diagnostics"
                               :aliases '("diag")
                               :description "Inspect the environment."))
         (help (make-command :name "help"
                             :description "Show help."))
         (app (make-app :name "demo"
                        :commands (list compile test doctor help))))
    (with-app-help-text (text app)
      (assert-searches text "Commands:" "Build:" "Diagnostics:" "compile" "doctor (diag)")
      (assert-search-order text "  help" "Build:" "Diagnostics:"))
    t))

(deftest app-help-renders-examples-section
  (let ((app (make-app :name "demo"
                       :examples '("demo compile src/main.lisp"
                                   "demo test --filter smoke"))))
    (with-app-help-text (text app)
      (assert-searches text "Examples:" "  demo compile src/main.lisp" "  demo test --filter smoke"))
    t))

(deftest command-help-renders-examples-section
  (let* ((command (make-command
                   :name "run"
                   :examples '("demo run target.lisp"
                               "demo run target.lisp --verbose")))
         (app (make-app :name "demo"
                        :commands (list command))))
    (with-command-help-text (text app command)
      (assert-searches text "Examples:" "  demo run target.lisp" "  demo run target.lisp --verbose"))
    t))

(deftest command-help-usage-includes-options-token
  (let* ((command (make-command
                   :name "run"
                   :options (list (make-option :name "config"
                                               :kind :value))
                   :positionals (list (make-positional :key :target :required-p t))))
         (app (make-app :name "demo"
                        :global-options (list (make-option :name "verbose" :short #\v))
                        :commands (list command))))
    (with-command-help-text (text app command)
      (assert-searches text "Usage: demo run [options] TARGET"))
    t))

(deftest help-command-construction
  (let* ((help-command (make-help-command))
         (app (make-app :name "demo" :commands (list help-command)))
         (inv (parse-argv app '("demo" "help"))))
    (is (string= (command-name (invocation-command inv)) "help"))
    t))

(deftest command-by-name-resolves-primary-names-and-aliases
  (let* ((build (make-command :name "build"
                              :aliases '("compile" "C")))
         (doctor (make-command :name "doctor"
                               :hidden-p t))
         (app (make-app :name "demo"
                        :commands (list build doctor))))
    (is (eq (command-by-name app "build") build))
    (is (eq (command-by-name app "COMPILE") build))
    (is (eq (command-by-name app "c") build))
    (is (eq (command-by-name app "doctor") doctor))
    (is (null (command-by-name app "release")))
    t))
