(in-package :cl-cli)

(defvar *cli-error-app* nil)
(defvar *cli-error-command* nil)

(define-condition cli-usage-error (error)
  ((message :initarg :message :reader cli-error-message)
   (context-app :initarg :context-app
                :initform nil
                :reader cli-usage-error-app)
   (context-command :initarg :context-command
                    :initform nil
                    :reader cli-usage-error-command))
  (:report (lambda (condition stream)
             (format stream "~A" (cli-error-message condition)))))

(define-condition cli-invalid-specification (cli-usage-error) ())
(define-condition cli-unknown-option (cli-usage-error)
  ((option :initarg :option :reader cli-unknown-option-name)))
(define-condition cli-unknown-command (cli-usage-error)
  ((command :initarg :command :reader cli-unknown-command-name)))
(define-condition cli-missing-option-value (cli-usage-error)
  ((option :initarg :option :reader cli-missing-option-value-name)))
(define-condition cli-missing-dependent-option (cli-usage-error)
  ((option :initarg :option :reader cli-missing-dependent-option-name)
   (dependency :initarg :dependency :reader cli-missing-dependent-option-dependency)))
(define-condition cli-conflicting-options (cli-usage-error)
  ((left-option :initarg :left-option :reader cli-conflicting-options-left-option)
   (right-option :initarg :right-option :reader cli-conflicting-options-right-option)))
(define-condition cli-missing-positional (cli-usage-error)
  ((name :initarg :name :reader cli-missing-positional-name)))
(define-condition cli-invalid-option-value (cli-usage-error)
  ((option :initarg :option :reader cli-invalid-option-value-name)
   (value :initarg :value :reader cli-invalid-option-value-value)
   (cause :initarg :cause :reader cli-invalid-option-value-cause)))
(define-condition cli-invalid-positional-value (cli-usage-error)
  ((name :initarg :name :reader cli-invalid-positional-value-name)
   (value :initarg :value :reader cli-invalid-positional-value-value)
   (cause :initarg :cause :reader cli-invalid-positional-value-cause)))
(define-condition cli-unexpected-argument (cli-usage-error)
  ((argument :initarg :argument :reader cli-unexpected-argument-name)))

(defun signal-cli-error (type message &rest initargs)
  (apply #'error
         type
         :message message
         :context-app *cli-error-app*
         :context-command *cli-error-command*
         initargs))
