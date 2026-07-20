(in-package :cl-cli/tests)

(describe-sequential "auto-help toggle"
  (it "provides -h/--help by default"
    (with-parsed-argv (inv (make-app :name "tool") '("tool" "--help"))
      (expect (eq (invocation-action inv) :help))))

  (it "suppresses the help flag when auto-help is disabled"
    (signals cli-unknown-option
      (parse-argv (make-app :name "tool" :auto-help nil) '("tool" "--help"))))

  (it "suppresses the short help flag too"
    (signals cli-unknown-option
      (parse-argv (make-app :name "tool" :auto-help nil) '("tool" "-h"))))

  (it "omits the help flag from help output"
    (let ((app (make-app :name "tool" :auto-help nil
                         :global-options (list (make-option :name "verbose" :kind :flag)))))
      (with-app-help-text (text app)
        (assert-not-searches text "--help"))))

  (it "keeps the version flag working alongside a disabled help flag"
    (with-parsed-argv (inv (make-app :name "tool" :auto-help nil :version "1.0")
                          '("tool" "--version"))
      (expect (eq (invocation-action inv) :version))))

  (it "leaves an explicit help command usable"
    (let ((app (make-app :name "tool" :auto-help nil
                         :commands (list (make-help-command)))))
      (with-parsed-argv (inv app '("tool" "help"))
        (expect (string= (command-name (invocation-command inv)) "help"))))))
