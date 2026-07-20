(in-package :cl-cli/tests)

(defun option-group-app ()
  (make-app
   :name "tool"
   :global-options (list (make-option :name "plain" :kind :flag :description "Ungrouped.")
                         (make-option :name "output" :kind :value
                                      :group "Output" :description "Output file.")
                         (make-option :name "format" :kind :value
                                      :group "Output" :description "Output format.")
                         (make-option :name "token" :kind :value
                                      :group "Auth" :description "API token."))))

(describe-sequential "option groups"
  (it "renders group headings with their options"
    (with-app-help-text (text (option-group-app))
      (assert-searches text "Output:" "--output" "--format" "Auth:" "--token")))

  (it "keeps ungrouped options and built-ins under the main heading"
    (with-app-help-text (text (option-group-app))
      (assert-search-order text "Options:" "--plain" "Output:")
      (assert-search-order text "Options:" "--help" "Output:")))

  (it "orders the main heading before the group sections"
    (with-app-help-text (text (option-group-app))
      (assert-search-order text "Options:" "Output:" "Auth:")))

  (it "exposes the group in json"
    (let ((text (with-string-output (s) (render-json (option-group-app) s))))
      (assert-searches text "\"group\":\"Output\"" "\"group\":\"Auth\"")))

  (it "rejects an empty group label"
    (signals-invalid-specification
      (make-option :name "x" :kind :flag :group ""))))
