(defpackage :cl-cli/tests
  (:use :cl :cl-cli)
  (:export :run-tests))

(in-package :cl-cli/tests)

(defmacro with-string-output ((stream) &body body)
  `(let ((,stream (make-string-output-stream)))
     ,@body
     (get-output-stream-string ,stream)))
