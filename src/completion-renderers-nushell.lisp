(in-package :cl-cli)

;;;; A Nushell completion renderer.
;;;;
;;;; Emits an `export extern` known-command definition plus a completer function
;;;; for the leading subcommand token. This covers subcommand names and the
;;;; app's global option flags; per-subcommand option externs are intentionally
;;;; omitted to keep the generated module simple and syntactically robust.
;;;; Follows the same optional-stream convention as the other renderers.

(defun %completion-nushell-quote (string)
  "Quote STRING as a Nushell double-quoted literal."
  (with-output-to-string (out)
    (write-char #\" out)
    (loop for char across (%completion-control-safe-string string)
          do (case char
               (#\\ (write-string "\\\\" out))
               (#\" (write-string "\\\"" out))
               (t (write-char char out))))
    (write-char #\" out)))

(defun %completion-nushell-command-completer-name (app)
  (format nil "nu-complete ~A command" (app-name app)))

(defun %completion-nushell-completer-name (app option)
  "The `nu-complete <app> <key>` function name attached to a dynamic OPTION."
  (format nil "nu-complete ~A ~A"
          (app-name app)
          (string-downcase (symbol-name (option-key option)))))

(defun %completion-nushell-flag-spec (app option)
  "Render OPTION as a single Nushell `extern` flag row, or NIL if unnameable.

A long name pairs with a short as `--long(-s)`; a value-bearing option gains a
`: string` type; a value option with a :complete function also gains a
`@\"nu-complete ...\"` custom-completer attachment; the description becomes a
trailing `# ...` comment."
  (let* ((names (option-names option))
         (long (find-if (lambda (name) (> (length name) 1)) names))
         (short (find-if (lambda (name) (= (length name) 1)) names))
         (value-p (member (option-kind option) '(:value :optional-value)))
         (flag (cond
                 ((and long short) (format nil "--~A(-~A)" long short))
                 (long (format nil "--~A" long))
                 (short (format nil "-~A" short))
                 (t nil))))
    (when flag
      (let ((type-part
              (cond
                ((and value-p (option-complete option))
                 (format nil ": string@~A"
                         (%completion-nushell-quote
                          (%completion-nushell-completer-name app option))))
                (value-p ": string")
                (t ""))))
        (format nil "  ~A~A~@[  # ~A~]"
                flag type-part
                (and (option-description option)
                     (%completion-control-safe-string
                      (option-description option))))))))

(defun %completion-nushell-dynamic-completers (app stream)
  "Emit a `nu-complete` def per dynamic GLOBAL option, or nothing.

Each shells out to `app __complete KEY` and returns the first (value) column of
each line; Nushell narrows the list by the word the user has typed. Only global
options are attached, matching the flags the generated `extern` actually lists."
  (let ((app-command (%completion-nushell-quote (app-name app))))
    (dolist (option (remove-if #'option-hidden-p (app-global-options app)))
      (when (option-complete option)
        (format stream "def ~A [] {~%"
                (%completion-nushell-quote
                 (%completion-nushell-completer-name app option)))
        (format stream "  ^~A __complete ~A | lines | each { |it| $it | split row (char tab) | first }~%"
                app-command
                (string-downcase (symbol-name (option-key option))))
        (format stream "}~%~%")))))

(defun %completion-nushell-first-arg-values (app)
  "First-token candidates: subcommand names plus any root positional values."
  (append (%completion-visible-command-tokens app)
          (%completion-app-positional-values app)))

(defun %completion-nushell-command-completer (app stream)
  (when (%completion-nushell-first-arg-values app)
    (format stream "def ~A [] {~%"
            (%completion-nushell-quote
             (%completion-nushell-command-completer-name app)))
    (format stream "  [~{~A~^, ~}]~%"
            (mapcar #'%completion-nushell-quote
                    (%completion-nushell-first-arg-values app)))
    (format stream "}~%~%")))

(defun render-nushell-completion (app &optional stream)
  "Render a Nushell completion module for APP.

With no STREAM, return the completion script as a string. With a STREAM, write
to it and return no values. The module defines a completer for the leading
subcommand and an `export extern` listing subcommands and global option flags.
Hidden commands and options are omitted."
  (unless stream
    (return-from render-nushell-completion
      (with-output-to-string (string-stream)
        (render-nushell-completion app string-stream))))
  (let ((app-name (%completion-control-safe-string (app-name app))))
    (format stream "# Nushell completion for ~A~%" app-name)
    (%completion-nushell-dynamic-completers app stream)
    (%completion-nushell-command-completer app stream)
    (format stream "export extern ~A [~%" (%completion-nushell-quote app-name))
    (when (%completion-nushell-first-arg-values app)
      (format stream "  command?: string@~A~%"
              (%completion-nushell-quote
               (%completion-nushell-command-completer-name app))))
    (dolist (option (append (remove-if #'option-hidden-p (app-global-options app))
                            (built-in-option-specs app)))
      (let ((row (%completion-nushell-flag-spec app option)))
        (when row
          (format stream "~A~%" row))))
    (format stream "]~%")
    (values)))
