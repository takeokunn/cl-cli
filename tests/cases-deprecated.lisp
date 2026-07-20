(in-package :cl-cli/tests)

(defun deprecated-demo-app ()
  (make-app
   :name "tool"
   :global-options (list (make-option :name "old"
                                      :kind :value
                                      :deprecated "use --new"
                                      :description "Old option.")
                         (make-option :name "gone"
                                      :kind :flag
                                      :deprecated t))
   :commands (list (make-command :name "legacy"
                                 :description "Legacy command."
                                 :deprecated t
                                 :handler (lambda (inv) (declare (ignore inv)) 0))
                   (make-command :name "run"
                                 :handler (lambda (inv) (declare (ignore inv)) 0)))))

(describe-sequential "deprecated entities"
  (it "annotates a deprecated option reason in help"
    (with-app-help-text (text (deprecated-demo-app))
      (assert-searches text "--old" "deprecated: use --new")))

  (it "annotates a bare deprecated option in help"
    (with-app-help-text (text (deprecated-demo-app))
      (assert-searches text "--gone")
      ;; The bare-deprecated flag renders "(deprecated)" with no reason suffix.
      (expect (search "deprecated" text))))

  (it "annotates a deprecated command in help"
    (with-app-help-text (text (deprecated-demo-app))
      (assert-searches text "legacy" "Legacy command. (deprecated)")))

  (it "keeps deprecated entities visible in completion"
    (let ((text (render-completion (deprecated-demo-app) "bash")))
      (assert-searches text "legacy" "old")))

  (it "marks deprecation in the man page"
    (let ((text (with-string-output (stream)
                  (render-manpage (deprecated-demo-app) stream))))
      ;; The reason's hyphens are roff-escaped (`--new` -> `\-\-new`).
      (assert-searches text "deprecated: use \\-\\-new" "Legacy command. (deprecated)")))

  (it "marks deprecation in markdown"
    (let ((text (with-string-output (stream)
                  (render-markdown (deprecated-demo-app) stream))))
      (assert-searches text "deprecated: use --new" "(deprecated)")))

  (it "marks deprecation in json"
    (let ((text (with-string-output (stream)
                  (render-json (deprecated-demo-app) stream))))
      (assert-searches text "\"deprecated\":\"use --new\"" "\"deprecated\":true")))

  (it "warns on stderr when a deprecated command is dispatched"
    (let* ((app (deprecated-demo-app))
           (err (with-string-output (stderr)
                  (run-app app :argv '("tool" "legacy")
                           :stdout (make-string-output-stream)
                           :stderr stderr))))
      (assert-searches err "warning" "'legacy'" "deprecated")))

  (it "does not warn for a non-deprecated command"
    (let* ((app (deprecated-demo-app))
           (err (with-string-output (stderr)
                  (run-app app :argv '("tool" "run")
                           :stdout (make-string-output-stream)
                           :stderr stderr))))
      (expect (zerop (length err)))))

  (it "keeps the deprecation reason on the command warning"
    (let* ((app (make-app :name "tool"
                          :commands (list (make-command :name "old"
                                                        :deprecated "use 'run'"
                                                        :handler (lambda (inv)
                                                                   (declare (ignore inv))
                                                                   0)))))
           (err (with-string-output (stderr)
                  (run-app app :argv '("tool" "old")
                           :stdout (make-string-output-stream)
                           :stderr stderr))))
      (assert-searches err "deprecated: use 'run'")))

  (it "rejects an empty deprecation reason"
    (signals-invalid-specification
      (make-option :name "x" :kind :value :deprecated ""))
    (signals-invalid-specification
      (make-command :name "x" :deprecated ""))))
