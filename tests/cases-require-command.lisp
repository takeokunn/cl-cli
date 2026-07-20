(in-package :cl-cli/tests)

(defun require-command-app ()
  (make-app :name "tool"
            :require-command t
            :version "1.0.0"
            :commands (list (make-command :name "build"
                                          :handler (lambda (inv) (declare (ignore inv)) 0))
                            (make-command :name "test"
                                          :handler (lambda (inv) (declare (ignore inv)) 0)))))

(describe-sequential "require-command"
  (it "errors when no command is given"
    (signals cli-unknown-command
      (parse-argv (require-command-app) '("tool"))))

  (it "lists the available commands in the error"
    (caught-signal= (cli-unknown-command condition)
        (parse-argv (require-command-app) '("tool"))
      (:searches cli-error-message "requires a command" "build" "test")))

  (it "dispatches a supplied command normally"
    (with-parsed-argv (inv (require-command-app) '("tool" "build"))
      (expect (string= (command-name (invocation-command inv)) "build"))))

  (it "still handles --help"
    (with-parsed-argv (inv (require-command-app) '("tool" "--help"))
      (expect (eq (invocation-action inv) :help))))

  (it "still handles --version"
    (with-parsed-argv (inv (require-command-app) '("tool" "--version"))
      (expect (eq (invocation-action inv) :version))))

  (it "rejects require-command without commands at make time"
    (signals-invalid-specification
      (make-app :name "tool" :require-command t))))
