(in-package :cl-cli)

;;;; Dynamic (runtime) completion.
;;;;
;;;; An option or positional may carry a :complete function -- (lambda (partial)
;;;; => list of candidate strings). At completion time the generated shell script
;;;; calls back into the program (`app __complete KEY PARTIAL`), which resolves
;;;; the spec by key, runs its :complete function, and prints one candidate per
;;;; line. The shell never re-parses the whole command line -- it already knows
;;;; which slot is being completed -- so this needs no lenient parser.

(defun %dynamic-all-commands (app)
  "Every command in APP, including nested subcommands, depth-first."
  (labels ((walk (commands)
             (loop for command in commands
                   append (cons command (walk (command-subcommands command))))))
    (walk (app-commands app))))

(defun %dynamic-option-specs (app)
  (append (app-global-options app)
          (loop for command in (%dynamic-all-commands app)
                append (command-options command))))

(defun %dynamic-positional-specs (app)
  (append (app-positionals app)
          (loop for command in (%dynamic-all-commands app)
                append (command-positionals command))))

(defun %key-name-matches-p (key-symbol key-string)
  (string-equal key-string (string-downcase (symbol-name key-symbol))))

(defun %find-dynamic-spec (app key)
  "Resolve KEY (a downcased key name) to an option or positional with :complete."
  (or (find-if (lambda (spec)
                 (and (option-complete spec)
                      (%key-name-matches-p (option-key spec) key)))
               (%dynamic-option-specs app))
      (find-if (lambda (spec)
                 (and (positional-spec-complete spec)
                      (%key-name-matches-p (positional-spec-key spec) key)))
               (%dynamic-positional-specs app))))

(defun %spec-complete-function (spec)
  (if (typep spec 'option-spec)
      (option-complete spec)
      (positional-spec-complete spec)))

(defun render-complete-reply (app key partial &optional (stream *standard-output*))
  "Print the dynamic completion candidates for KEY given the PARTIAL word.

KEY names an option or positional declared with :complete; its function is
called with PARTIAL and each returned candidate is printed on its own line. An
unknown or non-dynamic KEY prints nothing."
  (let ((spec (%find-dynamic-spec app key)))
    (when spec
      (dolist (candidate (funcall (%spec-complete-function spec) (or partial "")))
        ;; A candidate may be a plain value or a (value . description) cons;
        ;; descriptions are emitted tab-separated (fish shows them natively, and
        ;; the bash/zsh callbacks keep only the first column).
        (if (consp candidate)
            (format stream "~A~C~A~%" (car candidate) #\Tab (cdr candidate))
            (format stream "~A~%" candidate)))))
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
