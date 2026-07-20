(in-package :cl-cli/tests)

(defun nested-default-app ()
  (make-app
   :name "tool"
   :commands
   (list (make-command
          :name "remote"
          :default-command "list"
          :subcommands
          (list (make-command
                 :name "list"
                 :positionals (list (make-positional :key :filter :required-p nil))
                 :handler (lambda (inv) (declare (ignore inv)) 0))
                (make-command
                 :name "add"
                 :handler (lambda (inv) (declare (ignore inv)) 0)))))))

(describe-sequential "command default-command"
  (it "dispatches the default subcommand when no token is present"
    (with-parsed-argv (inv (nested-default-app) '("tool" "remote"))
      (expect (equal (mapcar #'command-name (invocation-command-path inv))
                     '("remote" "list")))))

  (it "keeps a non-subcommand token as the default subcommand's argument"
    (with-parsed-argv (inv (nested-default-app) '("tool" "remote" "origin"))
      (expect (string= (command-name (invocation-command inv)) "list"))
      (expect (string= (positional-value inv :filter) "origin"))))

  (it "still dispatches an explicit subcommand"
    (with-parsed-argv (inv (nested-default-app) '("tool" "remote" "add"))
      (expect (string= (command-name (invocation-command inv)) "add"))))

  (it "rejects a default-command naming an unknown subcommand"
    (signals-invalid-specification
      (make-app :name "tool"
                :commands (list (make-command
                                 :name "parent"
                                 :default-command "nope"
                                 :subcommands (list (make-command :name "real")))))))

  (it "rejects a default-command without subcommands"
    (signals-invalid-specification
      (make-app :name "tool"
                :commands (list (make-command :name "parent"
                                              :default-command "x"))))))
