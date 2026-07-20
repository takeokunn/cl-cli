(in-package :cl-cli/tests)

;;;; :color :auto / :width :auto resolution. The environment rules are the
;;;; deterministic, portable contract, so they are what we pin down here; the
;;;; TTY fall-through is exercised against a string stream, which is never a
;;;; terminal, so it must resolve to NIL on every implementation.

(defmacro with-env ((&rest bindings) &body body)
  "Set each (NAME VALUE) env var for BODY, restoring prior values afterward.

An empty string is used as the restore value when a variable was previously
unset, which %ENV-NONEMPTY treats as absent -- exactly the semantics we want."
  (let ((saved (loop for (name) in bindings collect (gensym name))))
    `(let ,(loop for g in saved for (name) in bindings
                 collect `(,g (or (uiop:getenv ,name) "")))
       (unwind-protect
            (progn
              ,@(loop for (name value) in bindings
                      collect `(setf (uiop:getenv ,name) ,value))
              ,@body)
         ,@(loop for g in saved for (name) in bindings
                 collect `(setf (uiop:getenv ,name) ,g))))))

(defun %auto-color-app ()
  "An app whose `go` command has a required option, so `app go` with no value
is a usage error -- the reliable trigger for run-app's stderr help path."
  (make-app :name "envtool" :version "1.0"
            :commands (list (make-command
                             :name "go"
                             :options (list (make-option :name "config"
                                                         :kind :value
                                                         :required-p t))))))

(describe-sequential "terminal color/width auto-detection"
  (it "passes explicit :color T and NIL through unchanged regardless of env"
    (with-env (("NO_COLOR" "1") ("CLICOLOR_FORCE" "1"))
      (expect (eq t (cl-cli::%resolve-help-color t (make-string-output-stream))))
      (expect (eq nil (cl-cli::%resolve-help-color nil (make-string-output-stream))))))

  (it "disables color under :auto when NO_COLOR is set, even with CLICOLOR_FORCE"
    (with-env (("NO_COLOR" "1") ("CLICOLOR_FORCE" "1"))
      (expect (eq nil (cl-cli::%resolve-help-color :auto (make-string-output-stream))))))

  (it "forces color under :auto when CLICOLOR_FORCE is set and NO_COLOR is empty"
    (with-env (("NO_COLOR" "") ("CLICOLOR_FORCE" "1"))
      (expect (eq t (cl-cli::%resolve-help-color :auto (make-string-output-stream))))))

  (it "treats CLICOLOR_FORCE=0 as not forcing, then falls through to the stream"
    (with-env (("NO_COLOR" "") ("CLICOLOR_FORCE" "0"))
      ;; A string stream is never a terminal, so the fall-through yields NIL.
      (expect (eq nil (cl-cli::%resolve-help-color :auto (make-string-output-stream))))))

  (it "falls through to (non-)terminal detection under :auto with no env signal"
    (with-env (("NO_COLOR" "") ("CLICOLOR_FORCE" ""))
      (expect (eq nil (cl-cli::%resolve-help-color :auto (make-string-output-stream))))))

  (it "never treats a string-output-stream as a terminal"
    (expect (eq nil (cl-cli::%stream-tty-p (make-string-output-stream)))))

  (it "passes an explicit :width integer and NIL through unchanged"
    (with-env (("COLUMNS" "40"))
      (expect (eql 100 (cl-cli::%resolve-help-width 100 (make-string-output-stream))))
      (expect (eq nil (cl-cli::%resolve-help-width nil (make-string-output-stream))))))

  (it "reads $COLUMNS under :width :auto"
    (with-env (("COLUMNS" "132"))
      (expect (eql 132 (cl-cli::%resolve-help-width :auto (make-string-output-stream))))))

  (it "yields NIL under :width :auto when COLUMNS is unset"
    (with-env (("COLUMNS" ""))
      (expect (eq nil (cl-cli::%resolve-help-width :auto (make-string-output-stream))))))

  (it "yields NIL under :width :auto when COLUMNS is not a positive integer"
    (with-env (("COLUMNS" "wide"))
      (expect (eq nil (cl-cli::%resolve-help-width :auto (make-string-output-stream)))))
    (with-env (("COLUMNS" "-5"))
      (expect (eq nil (cl-cli::%resolve-help-width :auto (make-string-output-stream))))))

  (it "wires :color :auto through run-app so CLICOLOR_FORCE styles error help"
    (with-env (("NO_COLOR" "") ("CLICOLOR_FORCE" "1"))
      (let* ((app (%auto-color-app))
             (err (make-string-output-stream)))
        ;; The missing required option is a usage error; run-app prints command
        ;; help to STDERR and returns 64. Under :auto+CLICOLOR_FORCE that help
        ;; must carry ANSI escapes, proving :auto is resolved against the actual
        ;; error stream, not merely accepted as a keyword.
        (expect (eql 64 (run-app app :argv '("envtool" "go")
                                 :stderr err :stdout (make-string-output-stream)
                                 :color :auto)))
        (expect (search (string #\Escape) (get-output-stream-string err))))))

  (it "wires :color :auto through run-app and stays plain when NO_COLOR is set"
    (with-env (("NO_COLOR" "1") ("CLICOLOR_FORCE" "1"))
      (let* ((app (%auto-color-app))
             (err (make-string-output-stream)))
        (run-app app :argv '("envtool" "go")
                 :stderr err :stdout (make-string-output-stream) :color :auto)
        (expect (not (search (string #\Escape) (get-output-stream-string err))))))))
