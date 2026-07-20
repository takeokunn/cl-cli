(in-package :cl-cli/tests)

(defmacro with-response-files ((&rest file-content-pairs) &body body)
  "Bind the response-file reader to serve an in-memory FILE -> CONTENTS map."
  `(let ((cl-cli::*response-file-reader*
           (lambda (path)
             (cond ,@(loop for (name contents) on file-content-pairs by #'cddr
                           collect `((string= path ,name) ,contents))
                   (t (error "No such response file: ~A" path))))))
     ,@body))

(defun response-file-app ()
  (make-app
   :name "tool"
   :expand-response-files t
   :global-options (list (make-option :name "verbose" :kind :flag)
                         (make-option :name "output" :kind :value))
   :positionals (list (make-positional :key :args :rest-p t))))

(describe-sequential "response files"
  (it "expands a response file into arguments"
    (with-response-files ("args.txt" "--verbose --output out.txt")
      (with-parsed-argv (inv (response-file-app) '("tool" "@args.txt"))
        (expect (eq (option-value inv :verbose) t))
        (expect (string= (option-value inv :output) "out.txt")))))

  (it "splits on newlines as well as spaces"
    (with-response-files ("args.txt" (format nil "--output~%out.txt"))
      (with-parsed-argv (inv (response-file-app) '("tool" "@args.txt"))
        (expect (string= (option-value inv :output) "out.txt")))))

  (it "mixes expanded and inline arguments in order"
    (with-response-files ("a.txt" "--verbose")
      (with-parsed-argv (inv (response-file-app) '("tool" "@a.txt" "extra"))
        (expect (eq (option-value inv :verbose) t))
        (expect (equal (positional-value inv :args) '("extra"))))))

  (it "expands nested response files"
    (with-response-files ("a.txt" "@b.txt" "b.txt" "--verbose")
      (with-parsed-argv (inv (response-file-app) '("tool" "@a.txt"))
        (expect (eq (option-value inv :verbose) t)))))

  (it "preserves argv order when a response file is followed by more args"
    (with-response-files ("opts.txt" "--output from-file")
      (with-parsed-argv (inv (response-file-app)
                         '("tool" "@opts.txt" "--verbose"))
        (expect (string= (option-value inv :output) "from-file"))
        (expect (option-value inv :verbose)))))

  (it "signals a usage error for recursive response files"
    (with-response-files ("loop.txt" "@loop.txt")
      (signals cli-usage-error
        (parse-argv (response-file-app) '("tool" "@loop.txt")))))

  (it "parses negative numbers from response files like argv"
    (let ((app (make-app :name "calc"
                         :expand-response-files t
                         :allow-negative-numbers t
                         :positionals (list (make-positional :key :n
                                                             :type :number)))))
      (with-response-files ("n.txt" "-5")
        (with-parsed-argv (inv app '("calc" "@n.txt"))
          (expect (eql (positional-value inv :n) -5))))))

  (it "treats @@ as a literal leading @"
    (with-response-files ()
      (with-parsed-argv (inv (response-file-app) '("tool" "@@literal"))
        (expect (equal (positional-value inv :args) '("@literal"))))))

  (it "signals a usage error for a missing response file"
    (with-response-files ()
      (signals cli-usage-error
        (parse-argv (response-file-app) '("tool" "@missing.txt")))))

  (it "leaves @tokens untouched when expansion is disabled"
    (let ((app (make-app :name "tool"
                         :positionals (list (make-positional :key :args :rest-p t)))))
      (with-parsed-argv (inv app '("tool" "@args.txt"))
        (expect (equal (positional-value inv :args) '("@args.txt"))))))

  (it "preserves the original argv in raw-argv"
    (with-response-files ("args.txt" "--verbose")
      (with-parsed-argv (inv (response-file-app) '("tool" "@args.txt"))
        (expect (equal (invocation-raw-argv inv) '("tool" "@args.txt")))))))
