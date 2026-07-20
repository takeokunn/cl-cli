(in-package :cl-cli)

;;;; Dynamic (runtime) completion.
;;;;
;;;; An option or positional may carry a :complete function -- (lambda (partial)
;;;; => list of candidate strings). At completion time the generated shell script
;;;; calls back into the program (`app __complete KEY PARTIAL`), which resolves
;;;; the spec by key, runs its :complete function, and prints one candidate per
;;;; line. The shell never re-parses the whole command line -- it already knows
;;;; which slot is being completed -- so this needs no lenient parser.

(defun %build-dynamic-completion-index (app)
  "Map dynamic completion keys to their option/positional spec in one tree walk."
  (let ((index (make-hash-table :test #'equal)))
    (labels ((register-option (spec)
               (when (option-complete spec)
                 (setf (gethash (string-downcase (symbol-name (option-key spec))) index)
                       spec)))
             (register-positional (spec)
               (when (positional-spec-complete spec)
                 (setf (gethash (string-downcase (symbol-name (positional-spec-key spec))) index)
                       spec)))
             (walk-command (command)
               (dolist (spec (command-options command))
                 (register-option spec))
               (dolist (spec (command-positionals command))
                 (register-positional spec))
               (dolist (subcommand (command-subcommands command))
                 (walk-command subcommand))))
      (dolist (spec (app-global-options app))
        (register-option spec))
      (dolist (spec (app-positionals app))
        (register-positional spec))
      (dolist (command (app-commands app))
        (walk-command command)))
    index))

(defun %dynamic-completion-index (app)
  "Return APP's cached dynamic completion index."
  (or (app-dynamic-completion-index app)
      (setf (app-dynamic-completion-index app)
            (%build-dynamic-completion-index app))))

(defun %spec-complete-function (spec)
  (if (typep spec 'option-spec)
      (option-complete spec)
      (positional-spec-complete spec)))

(defun render-complete-reply (app key partial &optional (stream *standard-output*))
  "Print the dynamic completion candidates for KEY given the PARTIAL word.

KEY names an option or positional declared with :complete; its function is
called with PARTIAL and each returned candidate is printed on its own line. An
unknown or non-dynamic KEY prints nothing."
  (let ((spec (and key
                   (gethash (string-downcase key)
                            (%dynamic-completion-index app)))))
    (when spec
      (dolist (candidate (funcall (%spec-complete-function spec) (or partial "")))
        ;; A candidate may be a plain value or a (value . description) cons;
        ;; descriptions are emitted tab-separated (fish shows them natively, and
        ;; the bash/zsh callbacks keep only the first column).
        (if (consp candidate)
            (format stream "~A~C~A~%"
                    (%completion-control-safe-string (car candidate))
                    #\Tab
                    (%completion-control-safe-string (cdr candidate)))
            (format stream "~A~%"
                    (%completion-control-safe-string candidate))))))
  (values))

(defun make-complete-command (&key (name "__complete"))
  "Create the hidden `__complete KEY [PARTIAL]` callback command.

Add it to an app's :commands (or via MAKE-STANDARD-COMMANDS :include-dynamic-p)
so the generated shell completion can query a :complete function at runtime."
  (make-command
   :name name
   :hidden-p t
   :description "Print dynamic completion candidates (internal)."
   :positionals (list (make-positional :key :complete-key :required-p t)
                      (make-positional :key :complete-word :required-p nil))
   :handler (lambda (invocation)
              (render-complete-reply
               (invocation-app invocation)
               (positional-value invocation :complete-key)
               (or (positional-value invocation :complete-word) "")
               (or (invocation-stdout invocation) *standard-output*))
              0)))
