(defpackage :cl-cli/tests
  (:use :cl :cl-cli)
  (:import-from :cl-prolog
                :assertz
                :make-rulebase
                :query-prolog)
  (:import-from :cl-prolog/weave
                :deftest-queries)
  (:import-from :cl-weave
                :describe-sequential
                :expect
                :gen-list
                :gen-member
                :gen-string
                :it
                :it-property
                :it-run-if
                :run-all
                :signals)
  (:export :run-tests))

(in-package :cl-cli/tests)

(defmacro with-string-output ((stream) &body body)
  `(let ((,stream (make-string-output-stream)))
     ,@body
     (get-output-stream-string ,stream)))
