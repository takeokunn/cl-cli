(in-package :cl-cli)

(defun public-option-display-name (spec)
  (if (option-hidden-p spec)
      "a hidden option"
      (%option-display-name spec)))

(defparameter *response-file-reader* #'uiop:read-file-string
  "Reads a response-file path into its string contents.

Injectable so tests need not touch the filesystem; defaults to
UIOP:READ-FILE-STRING.")

(defparameter +response-file-max-depth+ 32
  "Guard against a response file that (transitively) includes itself.")

(defun %read-response-file (path)
  (handler-case (funcall *response-file-reader* path)
    (cli-usage-error (condition) (error condition))
    (error (condition)
      (signal-cli-error 'cli-usage-error
                        (format nil "Cannot read response file ~A: ~A" path condition)))))

(defun %split-response-file-contents (contents)
  (remove-if (lambda (token) (zerop (length token)))
             (uiop:split-string contents
                                :separator '(#\Space #\Tab #\Newline #\Return #\Page))))

(defun expand-response-files (args &optional (depth 0))
  "Expand every @FILE token in ARGS into the args read from FILE.

A token `@path` is replaced by the whitespace-separated tokens of the file at
`path`, expanded recursively. `@@x` yields a literal `@x`, so a real argument
that must start with `@` can still be passed. A bare `@` is left untouched."
  (when (> depth +response-file-max-depth+)
    (signal-cli-error 'cli-usage-error "Response file inclusion nested too deeply."))
  (loop for arg in args
        append (cond
                 ((not (stringp arg)) (list arg))
                 ((and (>= (length arg) 2)
                       (char= (char arg 0) #\@)
                       (char= (char arg 1) #\@))
                  (list (subseq arg 1)))
                 ((and (> (length arg) 1)
                       (char= (char arg 0) #\@))
                  (expand-response-files
                   (%split-response-file-contents
                    (%read-response-file (subseq arg 1)))
                   (1+ depth)))
                 (t (list arg)))))
