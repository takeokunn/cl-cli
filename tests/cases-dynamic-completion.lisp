(in-package :cl-cli/tests)

(defun dynamic-app ()
  (make-app
   :name "tool"
   :global-options (list (make-option :name "branch" :kind :value
                                      :complete (lambda (partial)
                                                  (remove-if-not
                                                   (lambda (b) (eql 0 (search partial b)))
                                                   '("main" "master" "dev")))))
   :positionals (list (make-positional :key :tag
                                       :complete (lambda (partial)
                                                   (declare (ignore partial))
                                                   '("v1" "v2"))))
   :commands (make-standard-commands :include-dynamic-p t)))

(describe-sequential "dynamic completion"
  (it "prints an option's runtime candidates through __complete"
    (let ((text (with-string-output (stdout)
                  (run-app (dynamic-app) :argv '("tool" "__complete" "branch" "")
                           :stdout stdout))))
      (assert-searches text "main" "master" "dev")))

  (it "filters runtime candidates by the partial word"
    (let ((text (with-string-output (stdout)
                  (run-app (dynamic-app) :argv '("tool" "__complete" "branch" "ma")
                           :stdout stdout))))
      (assert-searches text "main" "master")
      (assert-not-searches text "dev")))

  (it "prints a positional's runtime candidates"
    (let ((text (with-string-output (stdout)
                  (run-app (dynamic-app) :argv '("tool" "__complete" "tag" "")
                           :stdout stdout))))
      (assert-searches text "v1" "v2")))

  (it "render-complete-reply resolves a spec by key"
    (let ((text (with-string-output (stream)
                  (render-complete-reply (dynamic-app) "branch" "de" stream))))
      (assert-searches text "dev")
      (assert-not-searches text "main")))

  (it "prints nothing for an unknown or non-dynamic key"
    (let ((text (with-string-output (stream)
                  (render-complete-reply (dynamic-app) "nope" "" stream))))
      (expect (zerop (length text)))))

  (it "make-standard-commands can add the hidden __complete command"
    (let ((commands (make-standard-commands :include-dynamic-p t)))
      (expect (member "__complete" commands :key #'command-name :test #'string=))
      (expect (command-hidden-p (find "__complete" commands
                                      :key #'command-name :test #'string=)))))

  (it "rejects a non-function :complete"
    (signals-invalid-specification
      (make-option :name "x" :kind :value :complete "not-a-fn")))

  (it "emits a (value . description) candidate as a tab-separated line"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "branch" :kind :value
                                                            :complete (lambda (p)
                                                                        (declare (ignore p))
                                                                        (list (cons "main" "Main branch")
                                                                              "dev"))))))
           (text (with-string-output (s)
                   (render-complete-reply app "branch" "" s))))
      ;; described candidate -> "value<TAB>description"; plain string -> "value"
      (assert-searches text (format nil "main~CMain branch" #\Tab))
      (expect (search (format nil "~%dev~%") (format nil "~%~A" text)))))

  (it "keeps only the value column in the bash and zsh callbacks"
    (let ((app (make-app :name "tool"
                         :global-options (list (make-option :name "branch" :kind :value
                                                           :complete (lambda (p) (declare (ignore p)) nil)))
                         :commands (make-standard-commands :include-dynamic-p t))))
      (assert-searches (render-completion app "bash") "cut -f1")
      (assert-searches (render-completion app "zsh") "cut -f1")))

  (it "emits a runtime callback in bash, zsh, and fish"
    (let ((app (make-app :name "tool"
                         :global-options (list (make-option :name "branch" :kind :value
                                                            :complete (lambda (p) (declare (ignore p)) nil)))
                         :commands (make-standard-commands :include-dynamic-p t))))
      (assert-searches (render-completion app "bash")
        "comp_dynamic='branch'"
        "\"${words[0]}\" __complete \"$comp_dynamic\"")
      (assert-searches (render-completion app "zsh")
        "${words[1]} __complete branch")
      (assert-searches (render-completion app "fish")
        "(tool __complete branch (commandline -ct))"))))
