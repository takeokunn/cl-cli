(defpackage :cl-cli/examples (:use :cl :cl-cli)
  (:export
    :make-cl-cc-app
    :make-cl-tmux-app
    :make-private-trade-fx-app
    :make-nshell-app))

(in-package :cl-cli/examples)

(defun option (name &rest args)
  (apply #'make-option :name name args))

(defun positional (key &rest args)
  (apply #'make-positional :key key args))

(defmacro options (&rest specs)
  `(list ,@specs))

(defmacro positionals (&rest specs)
  `(list ,@specs))

(defmacro commands (&rest specs)
  `(list ,@specs))

(defun parse-positive-integer (value)
  (let ((number (parse-integer value)))
    (unless (plusp number)
      (error "Expected a positive integer."))
    number))

(defun make-cl-cc-app ()
  (make-app
    :name
    "cl-cc"
    :summary
    "Compiler-oriented CLI with subcommands and script mode."
    :global-options
    (options
      (option "verbose" :short #\v :kind :flag)
      (option "script" :kind :value :stop-parsing-p t))
    :positionals
    (positionals (positional :script-argv :rest-p t))
    :commands
    (append
      (make-standard-commands :include-completion-p t)
      (commands
        (make-command
          :name
          "compile"
          :aliases
          '("build")
          :description
          "Compile a source file."
          :options
          (options
            (option "output" :short #\o :kind :value)
            (option "coverage" :kind :optional-value)
            (option "threads" :kind :boolean))
          :positionals
          (positionals (positional :input :required-p t)))))))

(defun make-cl-tmux-app ()
  (make-app
    :name
    "cl-tmux"
    :summary
    "tmux-style CLI with attached short values and a default command."
    :global-options
    (options
      (option "label" :short #\L :kind :value)
      (option "socket" :short #\S :kind :value))
    :commands
    (append
      (make-standard-commands)
      (commands
        (make-command
          :name
          "attach"
          :description
          "Attach to a session."
          :positionals
          (positionals
            (positional :target :required-p nil)
            (positional :attach-argv :rest-p t)))
        (make-command
          :name
          "display"
          :description
          "Forward a command tail verbatim."
          :options
          (options (option "command" :short #\c :kind :value :stop-parsing-p t))
          :positionals
          (positionals (positional :command-argv :rest-p t)))))
    :default-command
    "attach"))

(defun make-private-trade-fx-app ()
  (make-app
    :name
    "private-trade-fx"
    :summary
    "Single-binary CLI with strict validation."
    :global-options
    (options
      (option "instrument" :kind :value :choices '("USD_JPY" "EUR_USD") :required-p t)
      (option "count" :kind :value :parser #'parse-positive-integer)
      (option "profile" :kind :value :env-var "FX_PROFILE")
      (option "config" :kind :value :requires '(:profile)))
    :commands
    (make-standard-commands)
    :positionals
    (positionals (positional :strategy-argv :rest-p t))))

(defun make-nshell-app ()
  (make-app
    :name
    "nshell"
    :summary
    "Shell-style CLI with command and script modes."
    :global-options
    (options (option "command" :short #\c :kind :value :stop-parsing-p t))
    :commands
    (make-standard-commands)
    :positionals
    (positionals
      (positional :script :required-p nil)
      (positional :script-argv :rest-p t))
    :handler
    (lambda (invocation)
      invocation)))
