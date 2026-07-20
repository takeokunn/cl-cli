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

  (it "escapes raw HTML and Markdown controls in prose metadata"
    (let* ((app (make-app :name "tool"
                          :version "<b>2.0</b> *beta*"
                          :description "<img src=x onerror=alert(1)> [docs](javascript:alert(1))"
                          :commands (list (make-command
                                           :name "run"
                                           :description "Run <script>alert(1)</script>"
                                           :help-footer "See [unsafe](javascript:alert(1))."))))
           (text (markdown-text app)))
      (assert-searches text
                       "**Version:** &lt;b&gt;2.0&lt;/b&gt; \\*beta\\*"
                       "&lt;img src=x onerror=alert(1)&gt;"
                       "\\[docs\\](javascript:alert(1))"
                       "Run &lt;script&gt;alert(1)&lt;/script&gt;"
                       "See \\[unsafe\\](javascript:alert(1)).")
      (assert-not-searches text
                           "<img"
                            "<script>"
                            "<b>2.0</b>"
                            "[docs](javascript:alert(1))")))

  (it "strips control characters and uses delimiter-safe Markdown fences"
    (let* ((escape (string (code-char 27)))
           (app (make-app :name "tool"
                          :description (format nil "safe~Atext" escape)
                          :examples (list "echo ``` cannot close fence")))
           (text (markdown-text app)))
      (assert-searches text
                       "safetext"
                       "````"
                       "echo ``` cannot close fence")
      (assert-not-searches text escape)))

  (it "uses delimiter-safe Markdown code spans for value names"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "template"
                                                             :kind :value
                                                             :value-name "VA`L"
                                                             :description "Template."))))
           (text (markdown-text app)))
      (assert-searches text "``--template <VA`L>``")))

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
