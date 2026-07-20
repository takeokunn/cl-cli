(in-package :cl-cli)

(defun public-option-display-name (spec)
  (if (option-hidden-p spec)
      "a hidden option"
      (%option-display-name spec)))

(defun app-version-string (app)
  (let ((version (app-version app)))
    (when version
      (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) version)))
        (when (> (length trimmed) 0)
          trimmed)))))

(defun app-supports-version-p (app)
  (not (null (app-version-string app))))

(defun make-built-in-option (name short description key)
  (make-option :short short
               :aliases (list name)
               :kind :flag
               :description description
               :hidden-p t
               :key key))

(defun make-built-in-help-option ()
  (make-built-in-option "help" #\h
                        "Show help text for this command."
                        :help))

(defun make-built-in-version-option ()
  (make-built-in-option "version" #\V
                        "Show version information."
                        :version))

(defun built-in-option-p (spec)
  (member (option-key spec) '(:help :version)))

(defun built-in-option-specs (app)
  (let ((specs (when (app-auto-help app)
                 (list (make-built-in-help-option)))))
    (when (app-supports-version-p app)
      (push (make-built-in-version-option) specs))
    (nreverse specs)))

(defun option-specs-with-built-ins (app option-specs)
  (append (built-in-option-specs app)
          option-specs))

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
  (let ((frames (list (list depth args)))
        (expanded nil))
    (loop while frames
          do (destructuring-bind (current-depth current-args) (pop frames)
               (when (> current-depth +response-file-max-depth+)
                 (signal-cli-error 'cli-usage-error
                                   "Response file inclusion nested too deeply."))
               (when current-args
                 (let ((arg (first current-args))
                       (rest-args (rest current-args)))
                   (when rest-args
                     (push (list current-depth rest-args) frames))
                   (cond
                     ((not (stringp arg))
                      (push arg expanded))
                     ((and (>= (length arg) 2)
                           (char= (char arg 0) #\@)
                           (char= (char arg 1) #\@))
                      (push (subseq arg 1) expanded))
                     ((and (> (length arg) 1)
                           (char= (char arg 0) #\@))
                      (push (list (1+ current-depth)
                                  (%split-response-file-contents
                                   (%read-response-file (subseq arg 1))))
                            frames))
                     (t
                      (push arg expanded)))))))
    (nreverse expanded)))
