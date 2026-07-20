(in-package :cl-cli/tests)

(defun manpage-demo-app ()
  (make-app
   :name "demo"
   :version "1.2.0"
   :summary "Demo build tool."
   :description "A longer description of demo."
   :help-footer "See the project page for more."
   :global-options (list (make-option :name "verbose"
                                      :short #\v
                                      :kind :count
                                      :description "Increase verbosity.")
                         (flag-option "secret" :hidden-p t))
   :commands (list (make-command
                    :name "compile"
                    :description "Compile sources."
                    :options (list (make-option :name "output"
                                                :short #\o
                                                :kind :value
                                                :description "Output file."))
                    :positionals (list (make-positional :key :input
                                                        :required-p t
                                                        :description "Input file.")))
                   (make-command :name "sneaky"
                                 :hidden-p t
                                 :description "Should not appear."))
   :examples '("demo compile src/main.lisp")))

(defun manpage-text (app)
  (with-string-output (stream)
    (render-manpage app stream)))

(describe-sequential "manpage renderer"
  (it "emits a section-1 TH header with the program title"
    (let ((text (manpage-text (manpage-demo-app))))
      (assert-searches text ".TH \"DEMO\" \"1\"" "demo 1.2.0")))

  (it "renders NAME with the summary"
    (let ((text (manpage-text (manpage-demo-app))))
      (assert-searches text ".SH NAME" "demo \\- Demo build tool.")))

  (it "renders a SYNOPSIS with the program name and dispatch shape"
    (let ((text (manpage-text (manpage-demo-app))))
      (assert-searches text ".SH SYNOPSIS" ".B demo" "<command> [args]")))

  (it "renders DESCRIPTION including the help footer"
    (let ((text (manpage-text (manpage-demo-app))))
      (assert-searches text ".SH DESCRIPTION"
                       "A longer description of demo."
                       "See the project page for more.")))

  (it "renders OPTIONS with roff-escaped option tokens and metadata"
    (let ((text (manpage-text (manpage-demo-app))))
      (assert-searches text ".SH OPTIONS" "\\-\\-verbose, \\-v" "count")))

  (it "omits hidden options from the man page"
    (let ((text (manpage-text (manpage-demo-app))))
      (assert-not-searches text "secret")))

  (it "renders COMMANDS with nested options and positionals"
    (let ((text (manpage-text (manpage-demo-app))))
      (assert-searches text ".SH COMMANDS" ".B compile" "Compile sources."
                       ".RS" "\\-\\-output, \\-o" ".RE")))

  (it "omits hidden commands from the man page"
    (let ((text (manpage-text (manpage-demo-app))))
      (assert-not-searches text "sneaky" "Should not appear")))

  (it "renders EXAMPLES inside a no-fill block"
    (let ((text (manpage-text (manpage-demo-app))))
      (assert-searches text ".SH EXAMPLES" ".nf" "demo compile src/main.lisp" ".fi")))

  (it "documents flat positionals in an ARGUMENTS section"
    (let* ((app (make-app :name "script"
                          :positionals (list (make-positional :key :file
                                                              :required-p t
                                                              :description "Target file."))))
           (text (manpage-text app)))
      (assert-searches text ".SH ARGUMENTS" ".B FILE" "Target file.")))

  (it "guards a description that starts with a control character"
    (let* ((app (make-app :name "tool"
                          :description ".hidden leading dot"))
           (text (manpage-text app)))
      (assert-searches text "\\&.hidden leading dot")))

  (it "guards embedded roff control lines in free-form text"
    (let* ((app (make-app :name "tool"
                          :version (format nil "1.0~%.TH OWNED")
                          :manual-date (format nil "2026-07-20~%.TH DATE")
                          :summary (format nil "safe~%.SH NAME2")
                          :description (format nil "description~%.SH PWNED~%'bad")
                          :help-footer (format nil "footer~%.PP injected")
                          :examples (list (format nil "tool run~%.TH HACKED"))
                          :authors (list (format nil "Ada~%.SH AUTHORS2"))
                          :see-also (list (format nil "git(1)~%.SH SEE2"))))
           (text (manpage-text app)))
      (assert-searches text
                       "\\&.SH NAME2"
                       "\\&.SH PWNED"
                       "\\&'bad"
                       "\\&.PP injected"
                       "\\&.TH HACKED"
                       "\\&.SH AUTHORS2"
                       "\\&.SH SEE2")
      (assert-not-searches text
                           (format nil "~%.SH NAME2")
                           (format nil "~%.SH PWNED")
                           (format nil "~%'bad")
                           (format nil "~%.PP injected")
                           (format nil "~%.TH HACKED")
                           (format nil "~%.SH AUTHORS2")
                           (format nil "~%.SH SEE2")
                           (format nil "~%.TH OWNED")
                           (format nil "~%.TH DATE"))))

  (it "returns the page as a string when no stream is given"
    (let ((result (render-manpage (manpage-demo-app))))
      (expect (stringp result))
      (assert-searches result ".TH \"DEMO\"")))

  (it "returns no values when given a stream"
    (with-string-output (stream)
      (expect (null (multiple-value-list (render-manpage (manpage-demo-app) stream)))))))
