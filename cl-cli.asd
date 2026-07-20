(defparameter +cl-cli-repository-url+
  "https://github.com/takeokunn/cl-cli")

(defparameter +cl-cli-issues-url+
  "https://github.com/takeokunn/cl-cli/issues")

(defparameter +cl-cli-readme+
  (when *load-pathname*
    (uiop:read-file-string (merge-pathnames #P"README.md" *load-pathname*))))

(asdf:defsystem "cl-cli"
  :description "Composable Common Lisp CLI parsing and dispatch primitives."
  :long-description +cl-cli-readme+
  :author "takeokunn"
  :maintainer "takeokunn"
  :homepage +cl-cli-repository-url+
  :bug-tracker +cl-cli-issues-url+
  :source-control (:git +cl-cli-repository-url+)
  :license "MIT"
  :version "0.1.0"
  :depends-on ("uiop" "cl-prolog")
  :in-order-to ((asdf:test-op (asdf:test-op "cl-cli/tests")))
  :serial t
  :components ((:file "src/package")
               (:file "src/conditions")
               (:file "src/core")
               (:file "src/model-helpers")
               (:file "src/model")
               (:file "src/option-relations")
               (:file "src/model-app")
               (:file "src/util")
               (:file "src/terminal")
               (:file "src/parser-lookup")
               (:file "src/parser-option-consumption")
               (:file "src/parser-consumption")
               (:file "src/parser-values")
               (:file "src/parser-core")
               (:file "src/parser-dispatch")
               (:file "src/help-renderers")
               (:file "src/help-printers")
               (:file "src/help-commands")
               (:file "src/runtime")
               (:file "src/completion-helpers")
               (:file "src/completion-renderer-helpers")
               (:file "src/completion-renderers-bash")
               (:file "src/completion-renderers-zsh")
               (:file "src/completion-renderers-fish")
               (:file "src/doc-helpers")
               (:file "src/doc-renderers-manpage")
               (:file "src/doc-renderers-markdown")
               (:file "src/doc-renderers-json")
               (:file "src/doc-commands")
               (:file "src/completion-commands")))

(asdf:defsystem "cl-cli/tests"
  :description "Test system for cl-cli."
  :author "takeokunn"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("cl-cli" "cl-weave" "cl-prolog/weave")
  :serial t
  :components ((:file "tests/package")
               (:file "tests/test-fixtures")
               (:file "examples/consumer-migrations")
               (:file "tests/test-support")
               (:file "tests/cases-parse")
               (:file "tests/cases-property-parse")
               (:file "tests/cases-options")
               (:file "tests/cases-typed-values")
               (:file "tests/cases-count")
               (:file "tests/cases-delimited-values")
               (:file "tests/cases-config")
               (:file "tests/cases-value-source")
               (:file "tests/cases-deprecated")
               (:file "tests/cases-positional-choices")
               (:file "tests/cases-abbreviated-options")
               (:file "tests/cases-nested-subcommands")
               (:file "tests/cases-option-groups")
               (:file "tests/cases-response-files")
               (:file "tests/cases-positional-arity")
               (:file "tests/cases-nested-default")
               (:file "tests/cases-colored-help")
               (:file "tests/cases-terminal-detection")
               (:file "tests/cases-help-wrap")
               (:file "tests/cases-auto-help")
               (:file "tests/cases-negative-numbers")
               (:file "tests/cases-key-value")
               (:file "tests/cases-multi-value")
               (:file "tests/cases-variadic-options")
               (:file "tests/cases-inclusive-group")
               (:file "tests/cases-choice-suggestions")
               (:file "tests/cases-require-command")
               (:file "tests/cases-conditional-requirements")
               (:file "tests/cases-validation-specification")
               (:file "tests/cases-validation-values")
               (:file "tests/cases-validation-boolean")
               (:file "tests/cases-validation-relations")
               (:file "tests/cases-help")
               (:file "tests/cases-usage-synopsis")
               (:file "tests/cases-exit-codes")
               (:file "tests/cases-completion-bash")
               (:file "tests/cases-completion-zsh")
               (:file "tests/cases-completion-fish")
               (:file "tests/cases-completion-commands")
               (:file "tests/cases-doc-manpage")
               (:file "tests/cases-manpage-metadata")
               (:file "tests/cases-doc-markdown")
               (:file "tests/cases-doc-json")
               (:file "tests/cases-doc-commands")
               (:file "tests/cases-consumer-migrations"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :cl-cli/tests :run-tests)))
