(in-package :cl-cli)

;;;; An Elvish completion renderer.
;;;;
;;;; Registers an `edit:completion:arg-completer` that puts subcommand names and
;;;; option tokens as candidates; Elvish narrows them by the current prefix.
;;;; Follows the same optional-stream convention as the other renderers.

(defun %completion-elvish-quote (string)
  "Quote STRING as an Elvish single-quoted literal (a quote doubles itself)."
  (with-output-to-string (out)
    (write-char #\' out)
    (loop for char across (%completion-control-safe-string string)
          do (if (char= char #\')
                 (write-string "''" out)
                 (write-char char out)))
    (write-char #\' out)))

(defun %completion-elvish-list (tokens)
  (format nil "[~{~A~^ ~}]" (mapcar #'%completion-elvish-quote tokens)))

(defun %completion-elvish-static-puts (stream commands options positionals indent)
  "Emit the static candidate `put` lines (commands, options, positionals).

INDENT is a leading-whitespace string so the same body renders at top level or
nested inside a dynamic-completion `else` block."
  (when commands
    (format stream "~Avar commands = ~A~%" indent (%completion-elvish-list commands))
    (format stream "~Aput $@commands~%" indent))
  (when options
    (format stream "~Avar options = ~A~%" indent (%completion-elvish-list options))
    (format stream "~Aput $@options~%" indent))
  (when positionals
    (format stream "~Avar positionals = ~A~%" indent (%completion-elvish-list positionals))
    (format stream "~Aput $@positionals~%" indent)))

(defun render-elvish-completion (app &optional stream)
  "Render an Elvish completion script for APP.

With no STREAM, return the completion script as a string. With a STREAM, write
to it and return no values. The script installs an arg-completer that offers
subcommands and global option tokens. Hidden commands and options are omitted."
  (unless stream
    (return-from render-elvish-completion
      (with-output-to-string (string-stream)
        (render-elvish-completion app string-stream))))
  (let* ((app-name (%completion-control-safe-string (app-name app)))
         (commands (%completion-visible-command-tokens app))
         (options (%completion-command-option-tokens app nil))
         (positionals (%completion-app-positional-values app))
         (dynamic (%completion-dynamic-option-alist app)))
    (format stream "# Elvish completion for ~A~%" app-name)
    (when dynamic
      (format stream "use str~%"))
    (format stream "set edit:completion:arg-completer[~A] = {|@words|~%"
            (%completion-elvish-quote app-name))
    (cond
      (dynamic
       ;; When the word before the cursor is a dynamic option, shell out to the
       ;; program; otherwise fall through to the static candidate pool.
       (format stream "  var prev = ''~%")
       (format stream "  if (> (count $words) 1) { set prev = $words[-2] }~%")
       (format stream "  var dynamic = [~{~A~^ ~}]~%"
               (mapcar (lambda (pair)
                         (format nil "&~A=~A"
                                 (%completion-elvish-quote (car pair))
                                 (%completion-elvish-quote (cdr pair))))
                       dynamic))
       (format stream "  if (has-key $dynamic $prev) {~%")
       (format stream "    e:~A __complete $dynamic[$prev] $words[-1] | from-lines | each {|line|~%"
               (%completion-elvish-quote app-name))
       (format stream "      put (str:split \"\\t\" $line | take 1)~%")
       (format stream "    }~%")
       (format stream "  } else {~%")
       (%completion-elvish-static-puts stream commands options positionals "    ")
       (format stream "  }~%"))
      (t
       (%completion-elvish-static-puts stream commands options positionals "  ")))
    (format stream "}~%")
    (values)))
