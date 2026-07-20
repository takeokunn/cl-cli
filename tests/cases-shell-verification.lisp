(in-package :cl-cli/tests)

;;;; Verify generated scripts with the REAL tools that consume them (bash, zsh,
;;;; fish, mandoc) -- catching structural errors substring assertions cannot.
;;;; Each check is skipped when its tool is absent.

(defun %tool-available-p (name)
  (ignore-errors
    (zerop (nth-value 2
                      (uiop:run-program (list "sh" "-c" (format nil "command -v ~A" name))
                                        :ignore-error-status t :output nil :error-output nil)))))

(defun %check-tool (program args script)
  (uiop:with-temporary-file (:pathname path :stream stream :direction :output)
    (write-string script stream)
    (finish-output stream)
    (uiop:run-program (append (list program) args (list (namestring path)))
                      :ignore-error-status t :output :string :error-output :string)))

(defun verification-app ()
  (make-app
   :name "vtool" :version "1.0" :summary "Verification app."
   :manual-date "2026-07-20" :authors '("Ada" "Alan") :see-also '("git(1)")
   :global-options (list (make-option :name "verbose" :short #\v :kind :count)
                         (make-option :name "mode" :kind :value :choices '("dev" "prod"))
                         (make-option :name "config" :kind :value :value-hint :file
                                      :env-var "VTOOL_CONFIG" :description "Config file.")
                         (make-option :name "outdir" :kind :value :value-hint :dir)
                         (make-option :name "define" :short #\D :kind :key-value)
                         (make-option :name "branch" :kind :value
                                      :complete (lambda (p) (declare (ignore p)) '("main"))))
   :positionals (list (make-positional :key :env :choices '("a" "b")))
   :commands (append (make-standard-commands :include-completion-p t :include-docs-p t
                                             :include-dynamic-p t)
                     (list (make-command
                            :name "remote"
                            :options (list (make-option :name "porcelain" :kind :flag))
                            :subcommands (list (make-command :name "add")
                                               (make-command :name "remove")))))))

(describe-sequential "generated script verification"
  (it-run-if (%tool-available-p "bash")
      "the generated bash completion passes bash -n"
    (multiple-value-bind (out err code)
        (%check-tool "bash" '("-n") (render-completion (verification-app) "bash"))
      (declare (ignore out))
      (expect (zerop code))
      (expect (zerop (length err)))))

  (it-run-if (%tool-available-p "zsh")
      "the generated zsh completion passes zsh -n"
    (multiple-value-bind (out err code)
        (%check-tool "zsh" '("-n") (render-completion (verification-app) "zsh"))
      (declare (ignore out err))
      (expect (zerop code))))

  (it-run-if (%tool-available-p "fish")
      "the generated fish completion passes fish --no-execute"
    (multiple-value-bind (out err code)
        (%check-tool "fish" '("--no-execute") (render-completion (verification-app) "fish"))
      (declare (ignore out err))
      (expect (zerop code))))

  (it-run-if (%tool-available-p "mandoc")
      "the generated man page passes mandoc -T lint with no warnings"
    (multiple-value-bind (out err code)
        (%check-tool "mandoc" '("-T" "lint") (render-manpage (verification-app)))
      (declare (ignore code))
      (expect (zerop (length (string-trim '(#\Space #\Newline #\Return) out))))
      (expect (zerop (length (string-trim '(#\Space #\Newline #\Return) err))))))

  (it-run-if (%tool-available-p "nu")
      "the generated nushell completion loads in nushell"
    (multiple-value-bind (out err code)
        (%check-tool "nu" '() (render-completion (verification-app) "nushell"))
      (declare (ignore out err))
      (expect (zerop code))))

  (it-run-if (%tool-available-p "pwsh")
      "the generated powershell completion loads in pwsh"
    (multiple-value-bind (out err code)
        (%check-tool "pwsh" '("-NoProfile" "-File")
                     (render-completion (verification-app) "powershell"))
      (declare (ignore out err))
      (expect (zerop code)))))
