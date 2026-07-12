(in-package :cl-cli/tests)

(deftest invalid-option-parser-errors-are-usage-errors
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
      (parse-argv app '("trade" "--count" "0"))))
  t)

(deftest duplicate-option-names-are-invalid
  (let* ((left (make-option :name "verbose" :short #\v))
         (right (make-option :name "version" :short #\v)))
    (signals-invalid-specification
      (make-app :name "demo" :global-options (list left right))))
  t)

(deftest duplicate-command-names-are-invalid
  (let* ((left (make-command :name "build"))
         (right (make-command :name "build")))
    (signals-invalid-specification
      (make-app :name "demo" :commands (list left right))))
  t)

(deftest duplicate-command-aliases-are-invalid
  (let* ((left (make-command :name "build"
                             :aliases '("compile")))
         (right (make-command :name "release"
                              :aliases '("compile"))))
    (signals-invalid-specification
      (make-app :name "demo" :commands (list left right))))
  t)

(deftest app-name-must-be-present-and-non-empty
  (signals-invalid-specification
    (make-app)
    (make-app :name ""))
  t)

(deftest command-name-must-be-present-and-non-empty
  (signals-invalid-specification
    (make-command)
    (make-command :name ""))
  t)

(deftest positional-name-must-be-non-empty-when-key-is-omitted
  (signals-invalid-specification
    (make-positional :name ""))
  t)

(deftest option-names-must-be-non-empty
  (signals-invalid-specification
    (make-option :name "")
    (make-option :aliases '("")))
  t)

(deftest option-value-name-must-be-non-empty
  (signals-invalid-specification
    (make-option :name "output"
                 :kind :value
                 :value-name ""))
  t)

(deftest option-env-vars-must-be-non-empty
  (signals-invalid-specification
    (make-option :name "profile"
                 :kind :value
                 :env-var "")
    (make-option :name "profile"
                 :kind :value
                 :env-vars '("PRIMARY_PROFILE" "")))
  t)

(deftest option-choices-must-be-non-empty
  (signals-invalid-specification
    (make-option :name "mode"
                 :kind :value
                 :choices '("dev" "")))
  t)

(deftest completion-candidates-must-be-non-empty
  (signals-invalid-specification
    (make-option :name "mode"
                 :kind :value
                 :completion-candidates '(""))
    (make-option :name "mode"
                 :kind :value
                 :completion-candidates '(("dev" . ""))))
  t)

(deftest command-aliases-must-be-non-empty
  (signals-invalid-specification
    (make-command :name "build" :aliases '("")))
  t)

(deftest command-groups-and-examples-must-be-non-empty
  (signals-invalid-specification
    (make-command :name "build"
                  :group "")
    (make-command :name "build"
                  :examples '("build src" ""))
    (make-app :name "demo"
              :examples '("demo build" "")))
  t)

(deftest root-rest-positional-must-be-last
  (signals-invalid-specification
    (make-app :name "demo"
              :positionals (list (make-positional :key :args :rest-p t)
                                 (make-positional :key :target :required-p t))))
  t)

(deftest command-rest-positional-must-be-last
  (signals-invalid-specification
    (make-app :name "demo"
              :commands (list (make-command
                               :name "run"
                               :positionals (list (make-positional :key :args :rest-p t)
                                                  (make-positional :key :target :required-p t))))))
  t)

(deftest duplicate-root-positional-keys-are-invalid
  (signals-invalid-specification
    (make-app :name "demo"
              :positionals (list (make-positional :key :target)
                                 (make-positional :key :target))))
  t)

(deftest duplicate-command-positional-keys-are-invalid
  (signals-invalid-specification
    (make-app :name "demo"
              :commands (list (make-command
                               :name "run"
                               :positionals (list (make-positional :key :target)
                                                  (make-positional :key :target))))))
  t)

(deftest default-command-must-resolve-to-a-known-command
  (caught-signal= (cli-invalid-specification condition)
      (make-app :name "demo"
                :commands (list (make-command :name "build"))
                :default-command "deploy")
      (:searches cli-error-message "Unknown :default-command for demo: deploy"))
  t)

(deftest command-options-cannot-collide-with-global-options
  (let ((verbose (make-option :name "verbose" :short #\v))
        (build (make-command :name "build"
                             :options (list (make-option :name "verbose")))))
    (signals-invalid-specification
      (make-app :name "demo"
                :global-options (list verbose)
                :commands (list build))))
  t)
