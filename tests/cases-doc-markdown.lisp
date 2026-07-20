(in-package :cl-cli/tests)

;; Reuses MANPAGE-DEMO-APP (defined in tests/cases-doc-manpage.lisp): a
;; version'd, summarized app with a count option, a hidden option, a command
;; with its own option + positional, a hidden command, and an example.

(defun markdown-text (app)
  (with-string-output (stream)
    (render-markdown app stream)))

(describe-sequential "markdown renderer"
  (it "renders a title, summary blockquote, version, and description"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-searches text "# demo"
                       "> Demo build tool."
                       "**Version:** 1.2.0"
                       "A longer description of demo.")))

  (it "renders a fenced usage block with the dispatch synopsis"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-searches text "## Usage" "demo [global-options] <command> [args]")))

  (it "renders an options table with a code-spanned token and metadata"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-searches text "## Options"
                       "| Option | Description |"
                       "`--verbose, -v`"
                       "(count)")))

  (it "omits hidden options from the options table"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-not-searches text "secret")))

  (it "renders a per-command section with synopsis, positionals, and options"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-searches text "## Commands"
                       "### `compile`"
                       "Compile sources."
                       "demo compile [options] INPUT"
                       "`INPUT`"
                       "`--output, -o <OUTPUT>`")))

  (it "omits hidden commands from the document"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-not-searches text "sneaky" "Should not appear")))

  (it "renders an examples section in a fenced block"
    (let ((text (markdown-text (manpage-demo-app))))
      (assert-searches text "## Examples" "demo compile src/main.lisp")))

  (it "escapes a pipe inside a table cell"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "sep"
                                                             :kind :value
                                                             :description "left | right"))))
           (text (markdown-text app)))
      (assert-searches text "left \\| right")))

  (it "renders an arguments table for a flat positional app"
    (let* ((app (make-app :name "script"
                          :positionals (list (make-positional :key :file
                                                              :required-p t
                                                              :description "Target file."))))
           (text (markdown-text app)))
      (assert-searches text "## Arguments" "| Argument | Description |" "`FILE`")))

  (it "returns the document as a string when no stream is given"
    (let ((result (render-markdown (manpage-demo-app))))
      (expect (stringp result))
      (assert-searches result "# demo")))

  (it "returns no values when given a stream"
    (with-string-output (stream)
      (expect (null (multiple-value-list (render-markdown (manpage-demo-app) stream)))))))
