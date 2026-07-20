(in-package :cl-cli/tests)

(defun colored-help-app ()
  (make-app
   :name "tool"
   :global-options (list (make-option :name "verbose" :short #\v :kind :flag
                                      :description "Be loud."))
   :commands (list (make-command :name "build" :description "Build it."))))

(defun ansi-marker ()
  (format nil "~C[" #\Escape))

(describe-sequential "colored help"
  (it "includes ANSI styling when color is enabled"
    (let ((text (with-string-output (s) (print-app-help (colored-help-app) s :color t))))
      (expect (search (format nil "~C[1m" #\Escape) text))
      ;; The visible content is still present inside the styling.
      (assert-searches text "Options:" "--verbose" "build")))

  (it "omits ANSI styling by default"
    (let ((text (with-string-output (s) (print-app-help (colored-help-app) s))))
      (expect (null (search (ansi-marker) text)))))

  (it "colors command help when enabled"
    (let* ((app (colored-help-app))
           (command (command-by-name app "build"))
           (text (with-string-output (s) (print-command-help app command s (list command) :color t))))
      (expect (search (ansi-marker) text))))

  (it "run-app honors the color flag for --help"
    (let ((text (with-string-output (stdout)
                  (run-app (colored-help-app) :argv '("tool" "--help")
                           :stdout stdout :stderr (make-string-output-stream) :color t))))
      (expect (search (ansi-marker) text))))

  (it "run-app stays plain without the color flag"
    (let ((text (with-string-output (stdout)
                  (run-app (colored-help-app) :argv '("tool" "--help")
                           :stdout stdout :stderr (make-string-output-stream)))))
      (expect (null (search (ansi-marker) text))))))
