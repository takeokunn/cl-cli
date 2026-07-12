(in-package :cl-cli/tests)

(deftest parse-simple-flag
  (with-parsed-argv (inv (demo-app
                          :global-options (list (flag-option "verbose" :short #\v))
                          :commands nil)
                         '("demo" "--verbose"))
    (is (eq (invocation-action inv) :dispatch))
    (is (getf (invocation-global-options inv) :verbose))
    (is (null (invocation-positionals inv))))
  t)

(deftest parse-command-and-positionals
  (let* ((option-specs (list (value-option "output" :short #\o)))
         (positional-specs (list (make-positional :key :input :required-p t)))
         (app (make-app :name "demo")))
    (multiple-value-bind (option-values positional-values action)
        (cl-cli::parse-mixed-arguments app
                                       '("-o" "out.bin" "input.lisp")
                                       option-specs
                                       positional-specs)
      (is (eq action :dispatch))
      (is (equal (getf option-values :output) "out.bin"))
      (is (equal (getf positional-values :input) "input.lisp"))))
  t)

(deftest command-options-can-follow-positionals
  (let* ((run-command (make-command
                       :name "run"
                       :options (list (value-option "lang")
                                      (flag-option "stdlib"))
                       :positionals (list (make-positional :key :script :required-p t))))
         (app (make-app :name "cc"
                        :commands (list run-command)))
         (inv (parse-argv app '("cc" "run" "script.php" "--lang=php" "--stdlib"))))
    (is (string= (command-name (invocation-command inv)) "run"))
    (invocation-values= inv
      (:positional :script "script.php")
      (:option :lang "php")
      (:option :stdlib t)))
  t)

(deftest global-options-can-follow-command-and-positionals
  (let* ((run-command (make-command
                       :name "run"
                       :positionals (list (make-positional :key :script :required-p t))))
         (app (make-app :name "cc"
                        :global-options (list (flag-option "verbose" :short #\v))
                        :commands (list run-command)))
         (inv (parse-argv app '("cc" "run" "tool.lisp" "--verbose"))))
    (is (string= (command-name (invocation-command inv)) "run"))
    (invocation-values= inv
      (:positional :script "tool.lisp")
      (:option :verbose t)))
  t)

(deftest parse-help-flag
  (with-parsed-argv (inv (demo-app :commands nil) '("demo" "--help"))
    (is (eq (invocation-action inv) :help)))
  t)

(deftest parse-short-version-flag
  (with-parsed-argv (inv (demo-app :version "1.2.3") '("demo" "-V"))
    (is (eq (invocation-action inv) :version)))
  t)

(deftest parse-version-flag-requires-app-version
  (let ((app (demo-app)))
    (signals cli-unknown-option
      (parse-argv app '("demo" "-V")))
    (signals cli-unknown-option
      (parse-argv app '("demo" "--version"))))
  t)

(deftest unknown-option-errors
  (let ((app (demo-app :commands nil)))
    (signals cli-unknown-option
      (parse-argv app '("demo" "--bogus"))))
  t)

(deftest unknown-option-suggests-nearest-match
  (let* ((app (demo-app
               :global-options
               (list (flag-option "verbose"
                                  :short #\v)))))
    (caught-signal= (cli-unknown-option condition)
        (parse-argv app '("demo" "--verbsoe"))
      (:searches cli-error-message "Did you mean: --verbose?")))
  t)

(deftest unknown-option-does-not-suggest-hidden-options
  (let* ((app (demo-app
               :global-options
               (list (flag-option "verbose"
                                  :short #\v)
                     (flag-option "internal-debug"
                                  :short #\i
                                  :hidden-p t)))))
    (catching-signal (cli-unknown-option condition)
      (parse-argv app '("demo" "--internal-deubg"))
      (assert-searches (cli-error-message condition)
        "Unknown option: --internal-deubg")
      (assert-not-searches (cli-error-message condition)
        "--internal-debug"))
    (catching-signal (cli-unknown-option condition)
      (parse-argv app '("demo" "-x"))
      (assert-searches (cli-error-message condition)
        "Did you mean: -h?")
      (assert-not-searches (cli-error-message condition)
        "-i")))
  t)

(deftest unexpected-positional-errors
  (signals cli-unexpected-argument
    (parse-argv (demo-app :commands nil) '("demo" "extra")))
  t)

(deftest required-option-errors
  (let* ((command (make-command
                   :name "run"
                   :options (list (make-option :name "config"
                                               :kind :value
                                               :required-p t))))
         (app (make-app :name "demo" :commands (list command))))
    (signals cli-missing-option-value
      (parse-argv app '("demo" "run"))))
  t)

(deftest command-help-is-contextual
  (let* ((command (make-command
                   :name "compile"
                   :options (list (make-option :name "config"
                                               :kind :value
                                               :required-p t))
                   :positionals (list (make-positional :key :input :required-p t))))
         (app (make-app :name "demo" :commands (list command))))
    (with-parsed-argv (inv app '("demo" "compile" "--help"))
      (is (eq (invocation-action inv) :help))
      (is (string= (command-name (invocation-command inv)) "compile"))))
  t)

(deftest unknown-command-suggests-nearest-match
  (let* ((command (make-command :name "compile"
                                :aliases '("build")))
         (app (make-app :name "demo" :commands (list command))))
    (caught-signal= (cli-unknown-command condition)
        (parse-argv app '("demo" "compiel"))
      (:searches cli-error-message "Did you mean: compile?")))
  t)

(deftest unknown-command-does-not-suggest-hidden-commands
  (let* ((public-command (make-command :name "compile"))
         (hidden-command (make-command :name "internal-rebuild"
                                       :aliases '("irebuild")
                                       :hidden-p t))
         (app (make-app :name "demo"
                        :commands (list public-command hidden-command))))
    (catching-signal (cli-unknown-command condition)
      (parse-argv app '("demo" "internal-rebiuld"))
      (assert-searches (cli-error-message condition)
        "Unknown command: internal-rebiuld")
      (assert-not-searches (cli-error-message condition)
        "internal-rebuild"
        "irebuild")))
  t)

(deftest option-specification-requires-a-name-before-boolean-parser-setup
  (signals-invalid-specification
    (make-option :kind :boolean))
  t)

(deftest positional-specification-requires-a-key-or-name
  (signals-invalid-specification
    (make-positional))
  t)

(deftest parse-option-aliases-work
  (with-parsed-argv (inv (make-app :name "demo"
                                   :global-options
                                   (list (make-option :name "verbose"
                                                      :aliases '("chatty")
                                                      :kind :flag)
                                         (make-option :name "threads"
                                                      :aliases '("parallel")
                                                      :kind :boolean)))
                         '("demo" "--chatty" "--no-parallel"))
    (option-values= inv :verbose t :threads nil))
  t)

(deftest parse-command-alias-resolves-command
  (let* ((command (make-command :name "compile"
                                :aliases '("build")
                                :description "Compile sources."))
         (app (make-app :name "demo" :commands (list command))))
    (with-parsed-argv (inv app '("demo" "build"))
      (is (string= (command-name (invocation-command inv)) "compile"))))
  t)

(deftest root-positionals-and-rest
  (with-parsed-argv (inv (make-app
                          :name "nshell"
                          :positionals (list (make-positional :key :script :required-p nil)
                                             (make-positional :key :script-args :rest-p t)))
                         '("nshell" "build.ns" "a" "b"))
    (invocation-values= inv
      (:positional :script "build.ns")
      (:positional :script-args '("a" "b"))))
  t)

(deftest root-handler-dispatches
  (let* ((seen nil)
         (app (make-app :name "tmuxish"
                        :handler (lambda (invocation)
                                   (setf seen invocation)
                                   7)))
         (exit-code (run-app app :argv '("tmuxish"))))
    (is (= exit-code 7))
    (is (eq (invocation-app seen) app)))
  t)

(deftest extract-application-argv-after-runtime-marker
  (let ((argv '("sbcl" "--core" "cl-tmux.core"
                "--no-userinit" "attach" "-Lmain")))
    (is (equal (extract-application-argv
                :argv argv
                :runtime-markers '("--no-userinit" "--end-toplevel-options"))
               '("attach" "-Lmain"))))
  t)

(deftest extract-application-argv-after-separator
  (let ((argv '("nix" "run" ".#simulator" "--" "--seeds" "10")))
    (is (equal (extract-application-argv :argv argv :separator "--")
               '("--seeds" "10"))))
  t)

(deftest extract-application-argv-combines-runtime-marker-and-separator
  (let ((argv '("sbcl" "--script" "runner.lisp"
                "--end-toplevel-options" "nix" "run" ".#simulator"
                "--" "--instrument" "USD_JPY")))
    (is (equal (extract-application-argv
                :argv argv
                :runtime-markers '("--no-userinit" "--end-toplevel-options")
               :separator "--")
               '("--instrument" "USD_JPY"))))
  t)

(deftest default-runtime-markers-returns-a-fresh-list
  (let ((left (default-runtime-markers))
        (right (default-runtime-markers)))
    (is (equal left right))
    (is (not (eq left right))))
  t)

(deftest application-argv-uses-default-runtime-markers
  (let ((argv '("sbcl" "--core" "cl-tmux.core"
                "--no-userinit" "attach" "-Lmain")))
    (is (equal (application-argv :argv argv)
               '("attach" "-Lmain"))))
  t)

(deftest application-argv-can-also-extract-after-separator
  (let ((argv '("sbcl" "--script" "runner.lisp"
                "--end-toplevel-options" "nix" "run" ".#simulator"
                "--" "--instrument" "USD_JPY")))
    (is (equal (application-argv :argv argv :separator "--")
               '("--instrument" "USD_JPY"))))
  t)

(deftest strip-argv-separators-removes-literal-sentinels
  (is (equal (strip-argv-separators '("build.lisp" "--" "--flag" "value"))
             '("build.lisp" "--flag" "value")))
  (is (equal (strip-argv-separators '("a" "::" "b") :separator "::")
             '("a" "b")))
  t)
