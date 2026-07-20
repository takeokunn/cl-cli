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

  (it "reuses the app's dynamic completion index across replies"
    (let* ((app (dynamic-app))
           (first-index (cl-cli::%dynamic-completion-index app)))
      (with-string-output (stream)
        (render-complete-reply app "branch" "d" stream))
      (expect (eq first-index (cl-cli::%dynamic-completion-index app)))))

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

  (it "sanitizes runtime completion fields to one record per line"
    (let* ((app (make-app :name "tool"
                          :global-options
                          (list (make-option
                                 :name "branch"
                                 :kind :value
                                 :complete (lambda (p)
                                             (declare (ignore p))
                                             (list (cons "dev
branch	value" "local
branch	desc")
                                                   (format nil "bad~Cvalue" #\Esc)))))))
           (text (with-string-output (s)
                   (render-complete-reply app "branch" "" s))))
      (assert-searches text
        (format nil "dev branch value~Clocal branch desc~%" #\Tab)
        "badvalue")
      (expect (= 2 (count #\Newline text)))
      (expect (= 1 (count #\Tab text)))))

  (it "keeps only the value column in dynamic shell callbacks"
    (let ((app (make-app :name "tool"
                         :global-options (list (make-option :name "branch" :kind :value
                                                           :complete (lambda (p) (declare (ignore p)) nil)))
                         :commands (make-standard-commands :include-dynamic-p t))))
      (assert-searches (render-completion app "bash")
        "while IFS=$'\\t' read -r comp_value _; do"
        "COMPREPLY+=(\"$comp_value\")")
      (assert-not-searches (render-completion app "bash")
        "compgen -W \"$(\"${words[0]}\" __complete")
      (assert-searches (render-completion app "zsh")
        "while IFS=$'\\t' read -r comp_value _; do"
        "compadd -- \"$comp_value\"")
      (assert-not-searches (render-completion app "zsh") "cut -f1")))

  (it "emits a runtime callback in shell renderers"
    (let ((app (make-app :name "tool"
                         :global-options (list (make-option :name "branch" :kind :value
                                                            :complete (lambda (p) (declare (ignore p)) nil)))
                         :commands (make-standard-commands :include-dynamic-p t))))
      (assert-searches (render-completion app "bash")
        "comp_dynamic='branch'"
        "\"${words[0]}\" __complete \"$comp_dynamic\"")
      (assert-searches (render-completion app "zsh")
        "\"${words[1]}\" __complete branch \"$current_word\"")
      (assert-searches (render-completion app "fish")
        (cl-cli::%completion-shell-quote
         "(command 'tool' __complete branch (commandline -ct))"))
      (assert-searches (render-completion app "nushell")
        "def \"nu-complete tool branch\" [] {"
        "  ^\"tool\" __complete branch | lines | each")
      (assert-searches (render-completion app "elvish")
        "e:'tool' __complete $dynamic[$prev] $words[-1]"))))
