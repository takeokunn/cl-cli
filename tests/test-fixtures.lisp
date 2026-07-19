(in-package :cl-cli/tests)

(defun completion-text (app &optional (shell "bash"))
  (with-string-output (stream)
    (render-completion app shell stream)))

(defmacro with-completion-fixture ((app &rest initargs) &body body)
  `(let ((,app (make-completion-fixture ,@initargs)))
     ,@body))

(defmacro assert-completion-searches ((app &optional (shell "bash")) &rest needles)
  `(assert-searches (completion-text ,app ,shell)
     ,@needles))

(defmacro assert-completion-not-searches ((app &optional (shell "bash")) &rest needles)
  `(assert-not-searches (completion-text ,app ,shell)
     ,@needles))

(defmacro assert-completion-searches-for-shells ((app) &rest shell-needles)
  `(progn
     ,@(loop for (shell . needles) in shell-needles
             collect `(assert-completion-searches (,app ,shell)
                        ,@needles))))

(defun make-completion-fixture (&key (app-name "demo")
                                      version
                                      global-options
                                      commands
                                      (command-name "compile")
                                      command-aliases
                                      command-description
                                      command-hidden-p
                                      command-options)
  (let ((command (make-command :name command-name
                               :aliases command-aliases
                               :description command-description
                               :hidden-p command-hidden-p
                               :options command-options)))
    (make-app :name app-name
              :version version
              :global-options global-options
              :commands (or commands
                            (list command)))))

(defun completion-visible-commands-and-options-fixture ()
  (make-completion-fixture
   :version "1.0.0"
   :global-options (list (make-option :name "verbose"
                                      :short #\v
                                      :kind :flag))
   :command-aliases '("build")
   :command-description "Compile sources."
   :command-options (list (make-option :name "output"
                                       :short #\o
                                       :kind :value))))

(defun completion-hidden-commands-and-options-fixture ()
  (make-completion-fixture
   :global-options (list (make-option :name "visible-flag"
                                      :kind :flag)
                         (make-option :name "secret-flag"
                                      :kind :flag
                                      :hidden-p t))
   :commands (list (make-command :name "visible")
                   (make-command :name "secret"
                                 :hidden-p t))))

(defun completion-choice-values-fixture ()
  (make-completion-fixture
   :command-options (list (make-option :name "profile"
                                       :kind :value
                                       :choices '("dev" "prod")))))

(defun completion-candidate-descriptions-fixture ()
  (make-completion-fixture
   :command-options (list (make-option :name "profile"
                                       :kind :value
                                       :completion-candidates '(("dev" . "Local development")
                                                                ("prod" . "Production release"))))))

(defun completion-negated-boolean-options-fixture ()
  (make-completion-fixture
   :command-options (list (make-option :name "threads"
                                       :kind :boolean))))

(defun make-example-app (name)
  (let ((symbol (find-symbol name "CL-CLI/EXAMPLES")))
    (unless symbol
      (error "Missing example app constructor: ~A" name))
    (funcall (symbol-function symbol))))

(defun demo-app (&rest initargs)
  (apply #'make-app :name "demo" initargs))
