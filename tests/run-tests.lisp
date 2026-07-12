;;; Command-line entry point:
;;;   sbcl --non-interactive --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)' --quit
;;;   ecl --norc --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)'

(eval-when (:load-toplevel :execute)
  (require :asdf)
  (let* ((asdf-package (or (find-package :asdf)
                           (error "ASDF package is unavailable.")))
         (load-asd (or (find-symbol "LOAD-ASD" asdf-package)
                       (error "ASDF does not provide LOAD-ASD.")))
         (load-system (or (find-symbol "LOAD-SYSTEM" asdf-package)
                          (error "ASDF does not provide LOAD-SYSTEM."))))
    (funcall load-asd (merge-pathnames #P"../cl-cli.asd"
                                       (or *load-truename* *compile-file-truename*)))
    (funcall load-system "cl-cli/tests")))
