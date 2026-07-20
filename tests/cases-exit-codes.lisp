(in-package :cl-cli/tests)

;;;; run-app exit codes: the sysexits defaults (0 / 64 / 70) and the
;;;; :usage-exit-code / :error-exit-code overrides.

(defun %exit-app ()
  (make-app
   :name "exitool"
   :commands
   (list (make-command
          :name "need"
          :options (list (make-option :name "config" :kind :value :required-p t))
          :handler (lambda (i) (declare (ignore i)) 0))
         (make-command
          :name "boom"
          :handler (lambda (i) (declare (ignore i)) (error "kaboom"))))))

(defun %silent-run (app argv &rest keys)
  (apply #'run-app app :argv argv
         :stdout (make-string-output-stream)
         :stderr (make-string-output-stream)
         keys))

(describe-sequential "run-app exit codes"
  (it "returns 0 on a successful dispatch"
    (expect (eql 0 (%silent-run (%exit-app) '("exitool" "need" "--config" "c")))))

  (it "returns 64 (EX_USAGE) by default for a usage error"
    (expect (eql 64 (%silent-run (%exit-app) '("exitool" "need")))))

  (it "returns 70 (EX_SOFTWARE) by default for an unhandled internal error"
    (expect (eql 70 (%silent-run (%exit-app) '("exitool" "boom")))))

  (it "honors :usage-exit-code for usage errors"
    (expect (eql 2 (%silent-run (%exit-app) '("exitool" "need")
                                :usage-exit-code 2))))

  (it "honors :error-exit-code for unhandled internal errors"
    (expect (eql 1 (%silent-run (%exit-app) '("exitool" "boom")
                                :error-exit-code 1))))

  (it "leaves the other code at its default when only one is overridden"
    ;; Overriding the usage code must not change the internal-error code.
    (expect (eql 70 (%silent-run (%exit-app) '("exitool" "boom")
                                 :usage-exit-code 2)))
    (expect (eql 2 (%silent-run (%exit-app) '("exitool" "need")
                                :usage-exit-code 2 :error-exit-code 1)))))
