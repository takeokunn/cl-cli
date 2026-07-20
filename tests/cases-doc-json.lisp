(in-package :cl-cli/tests)

;; Reuses MANPAGE-DEMO-APP (tests/cases-doc-manpage.lisp).

(defun json-text (app)
  (with-string-output (stream)
    (render-json app stream)))

(describe-sequential "json renderer"
  (it "emits top-level app metadata"
    (let ((text (json-text (manpage-demo-app))))
      (assert-searches text
                       "\"name\":\"demo\""
                       "\"version\":\"1.2.0\""
                       "\"summary\":\"Demo build tool.\""
                       "\"description\":\"A longer description of demo.\"")))

  (it "describes global options including kind and count"
    (let ((text (json-text (manpage-demo-app))))
      (assert-searches text
                       "\"key\":\"verbose\""
                       "\"names\":[\"verbose\",\"v\"]"
                       "\"kind\":\"count\"")))

  (it "describes commands with their options and positionals"
    (let ((text (json-text (manpage-demo-app))))
      (assert-searches text
                       "\"commands\":["
                       "\"name\":\"compile\""
                       "\"key\":\"output\""
                       "\"positionals\":["
                       "\"key\":\"input\""
                       "\"required\":true")))

  (it "omits hidden options and commands"
    (let ((text (json-text (manpage-demo-app))))
      (assert-not-searches text "secret" "sneaky")))

  (it "emits examples arrays"
    (let ((text (json-text (manpage-demo-app))))
      (assert-searches text "\"examples\":[\"demo compile src/main.lisp\"]")))

  (it "encodes typed numeric metadata as JSON numbers"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "jobs"
                                                             :kind :value
                                                             :type :integer
                                                             :min 1
                                                             :max 64))))
           (text (json-text app)))
      (assert-searches text "\"type\":\"integer\"" "\"min\":1" "\"max\":64")))

  (it "encodes a delimiter and string default"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "tags"
                                                             :kind :value
                                                             :value-delimiter #\,
                                                             :default '("a" "b")))))
           (text (json-text app)))
      (assert-searches text "\"delimiter\":\",\"" "\"default\":[\"a\",\"b\"]")))

  (it "escapes special characters in strings"
    (let* ((app (make-app :name "tool"
                          :global-options (list (make-option :name "note"
                                                             :kind :value
                                                             :description "a\"b\\c"))))
           (text (json-text app)))
      (assert-searches text "a\\\"b\\\\c")))

  (it "produces balanced brackets and braces"
    (let ((text (json-text (manpage-demo-app))))
      (expect (= (count #\{ text) (count #\} text)))
      (expect (= (count #\[ text) (count #\] text)))))

  (it "routes through the docs command as the json format"
    (let* ((app (make-app :name "demo"
                          :commands (list (make-docs-command))))
           (text (with-string-output (stdout)
                   (run-app app :argv '("demo" "docs" "json") :stdout stdout))))
      (assert-searches text "\"name\":\"demo\"")))

  (it "returns the document as a string with no stream"
    (let ((result (render-json (manpage-demo-app))))
      (expect (stringp result))
      (assert-searches result "\"name\":\"demo\"")))

  (it "returns no values when given a stream"
    (with-string-output (stream)
      (expect (null (multiple-value-list (render-json (manpage-demo-app) stream)))))))
