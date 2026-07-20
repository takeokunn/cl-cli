(in-package :cl-cli/tests)

(defun wrap-app ()
  (make-app :name "tool"
            :global-options
            (list (make-option :name "verbose" :kind :flag
                               :description
                               "Enable very verbose diagnostic output across every subsystem and phase."))))

(describe-sequential "help word-wrap"
  (it "wraps a long description under the given width"
    (let ((text (with-string-output (s) (print-app-help (wrap-app) s :width 45))))
      ;; A continuation line indented to the 27-column description gutter.
      (expect (search (format nil "~%~A" (make-string 27 :initial-element #\Space)) text))))

  (it "keeps the full description on one line by default"
    (let ((text (with-string-output (s) (print-app-help (wrap-app) s))))
      (assert-searches text
        "Enable very verbose diagnostic output across every subsystem and phase.")))

  (it "keeps every line within the width"
    (let* ((text (with-string-output (s) (print-app-help (wrap-app) s :width 45)))
           (lines (uiop:split-string text :separator (list #\Newline))))
      (dolist (line lines)
        (expect (<= (length line) 45)))))

  (it "wraps through run-app --help with :width"
    (let ((text (with-string-output (stdout)
                  (run-app (wrap-app) :argv '("tool" "--help")
                           :stdout stdout :stderr (make-string-output-stream) :width 45))))
      (expect (search (format nil "~%~A" (make-string 27 :initial-element #\Space)) text)))))
