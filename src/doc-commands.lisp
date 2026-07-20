(in-package :cl-cli)

;;;; A built-in `docs [FORMAT]` command, parallel to the `completion [SHELL]`
;;;; command: it prints generated reference documentation (a man page or
;;;; Markdown) for the owning app straight to stdout.

(defun %parse-doc-format (value)
  (let ((format (canonical-name value)))
    (cond
      ((member format '("man" "manpage" "roff" "1") :test #'string=) "man")
      ((member format '("markdown" "md") :test #'string=) "markdown")
      ((member format '("json") :test #'string=) "json")
      (t
       (signal-cli-error 'cli-invalid-positional-value
                         (format nil "Unsupported documentation format: ~A" value)
                         :name :format
                         :value value
                         :cause "Supported formats are man, markdown, and json.")))))

(defun render-docs (app format &optional stream)
  "Render documentation for APP in FORMAT (\"man\", \"markdown\", or \"json\")."
  (let ((resolved (%parse-doc-format format)))
    (cond
      ((string= resolved "man") (render-manpage app stream))
      ((string= resolved "markdown") (render-markdown app stream))
      ((string= resolved "json") (render-json app stream))
      (t
       (signal-cli-error 'cli-invalid-positional-value
                         (format nil "Unsupported documentation format: ~A" format)
                         :name :format
                         :value format)))))

(defun make-docs-command (&key (name "docs")
                               (description "Print generated reference documentation."))
  "Create a `docs [FORMAT]` command spec that prints reference documentation.

FORMAT defaults to man; man, markdown, and json are supported."
  (make-command
   :name name
   :description description
   :positionals (list (make-positional :key :format
                                       :description "Documentation format (man, markdown, json)."
                                       :default "man"
                                       :parser #'%parse-doc-format
                                       ;; Candidates (not :choices) so completion
                                       ;; suggests the canonical formats while the
                                       ;; parser still accepts aliases (md, roff).
                                       :completion-candidates '("man" "markdown" "json")
                                       :required-p nil))
   :handler (lambda (invocation)
              (let ((format (positional-value invocation :format)))
                (render-docs
                 (invocation-app invocation)
                 format
                 (or (invocation-stdout invocation)
                     *standard-output*))))
   :hidden-p nil))
