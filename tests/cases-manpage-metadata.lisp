(in-package :cl-cli/tests)

(defun manpage-metadata-app ()
  (make-app :name "demo"
            :version "1.0.0"
            :summary "Demo."
            :see-also '("git(1)" "make(1)")
            :authors '("Ada Lovelace" "Alan Turing")))

(describe-sequential "man page metadata"
  (it "renders a SEE ALSO section"
    (let ((text (with-string-output (s) (render-manpage (manpage-metadata-app) s))))
      (assert-searches text ".SH SEE ALSO" "git(1), make(1)")))

  (it "renders an AUTHORS section"
    (let ((text (with-string-output (s) (render-manpage (manpage-metadata-app) s))))
      (assert-searches text ".SH AUTHORS" "Ada Lovelace" "Alan Turing")))

  (it "omits the sections when unset"
    (let ((text (with-string-output (s) (render-manpage (make-app :name "bare") s))))
      (assert-not-searches text ".SH SEE ALSO" ".SH AUTHORS")))

  (it "exposes see-also and authors in json"
    (let ((text (with-string-output (s) (render-json (manpage-metadata-app) s))))
      (assert-searches text "\"seeAlso\":[\"git(1)\",\"make(1)\"]"
                       "\"authors\":[\"Ada Lovelace\",\"Alan Turing\"]")))

  (it "rejects an empty see-also entry"
    (signals-invalid-specification
      (make-app :name "demo" :see-also '(""))))

  (it "puts the manual date in the TH header when given"
    (let ((text (with-string-output (s)
                  (render-manpage (make-app :name "demo" :manual-date "2026-07-20") s))))
      (assert-searches text ".TH \"DEMO\" \"1\" \"2026-07-20\"")))

  (it "renders an EXIT STATUS section"
    (let ((text (with-string-output (s) (render-manpage (make-app :name "demo") s))))
      (assert-searches text ".SH EXIT STATUS" ".B 0" ".B 64" ".B 70")))

  (it "renders an ENVIRONMENT section for env-backed options"
    (let* ((app (make-app :name "demo"
                          :global-options (list (make-option :name "profile" :kind :value
                                                            :env-var "DEMO_PROFILE"
                                                            :description "Runtime profile."))
                          :commands (list (make-command
                                           :name "build"
                                           :options (list (make-option :name "jobs" :kind :value
                                                                       :env-var "DEMO_JOBS"))))))
           (text (with-string-output (s) (render-manpage app s))))
      (assert-searches text ".SH ENVIRONMENT" ".B DEMO_PROFILE" ".B DEMO_JOBS")))

  (it "omits ENVIRONMENT when no option is env-backed"
    (let ((text (with-string-output (s)
                  (render-manpage (make-app :name "demo"
                                            :global-options (list (make-option :name "x" :kind :flag)))
                                  s))))
      (assert-not-searches text ".SH ENVIRONMENT"))))
