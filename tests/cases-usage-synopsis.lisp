(in-package :cl-cli/tests)

;;;; Required options are spelled out in the one-line usage synopsis (clap/click
;;;; style) instead of being hidden inside the `[options]` catch-all.

(defun %synopsis-of (thunk)
  "Return the `Usage:` line produced by THUNK, which prints help to its arg."
  (let ((text (with-string-output (out) (funcall thunk out))))
    (or (find-if (lambda (line) (search "Usage:" line))
                 (uiop:split-string text :separator '(#\Newline)))
        "")))

(describe-sequential "required-option usage synopsis"
  (it "spells a required global option into the app dispatch usage line"
    (let* ((app (make-app
                 :name "demo"
                 :global-options (list (make-option :name "token" :kind :value
                                                    :value-name "TOKEN" :required-p t))
                 :commands (list (make-command :name "run"))))
           (usage (%synopsis-of (lambda (out) (print-app-help app out)))))
      (expect (search "--token <TOKEN>" usage))
      (expect (search "<command>" usage))))

  (it "spells a required global option into the root usage of a command-less app"
    (let* ((app (make-app
                 :name "demo"
                 :handler (lambda (i) (declare (ignore i)) 0)
                 :global-options (list (make-option :name "token" :kind :value
                                                    :value-name "TOKEN" :required-p t))))
           (usage (%synopsis-of (lambda (out) (print-app-help app out)))))
      (expect (search "[global-options]" usage))
      (expect (search "--token <TOKEN>" usage))))

  (it "spells required command and global options into the command usage line"
    (let* ((cmd (make-command
                 :name "run"
                 :options (list (make-option :name "config" :kind :value
                                             :value-name "FILE" :required-p t))))
           (app (make-app
                 :name "demo"
                 :global-options (list (make-option :name "token" :kind :value
                                                    :value-name "TOKEN" :required-p t))
                 :commands (list cmd)))
           (usage (%synopsis-of (lambda (out) (print-command-help app cmd out (list cmd))))))
      (expect (search "[options]" usage))
      (expect (search "--config <FILE>" usage))
      (expect (search "--token <TOKEN>" usage))))

  (it "renders a required flag without a value placeholder"
    (let* ((app (make-app
                 :name "demo"
                 :handler (lambda (i) (declare (ignore i)) 0)
                 :global-options (list (make-option :name "force" :kind :flag :required-p t))))
           (usage (%synopsis-of (lambda (out) (print-app-help app out)))))
      (expect (search "--force" usage))
      (expect (not (search "--force <" usage)))))

  (it "keeps a non-required option inside the catch-all, not the synopsis"
    (let* ((app (make-app
                 :name "demo"
                 :handler (lambda (i) (declare (ignore i)) 0)
                 :global-options (list (make-option :name "opt" :kind :value))))
           (usage (%synopsis-of (lambda (out) (print-app-help app out)))))
      (expect (search "[global-options]" usage))
      (expect (not (search "--opt" usage)))))

  (it "never spells a hidden required option into the synopsis"
    (let* ((app (make-app
                 :name "demo"
                 :handler (lambda (i) (declare (ignore i)) 0)
                 :global-options (list (make-option :name "secret" :kind :value
                                                    :required-p t :hidden-p t))))
           (usage (%synopsis-of (lambda (out) (print-app-help app out)))))
      (expect (not (search "--secret" usage))))))
