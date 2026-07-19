(in-package :cl-cli/tests)

;;; Property-based coverage for the parser. These exercise invariants that must
;;; hold for *any* generated name/value, complementing the example-based cases.
;;; The name alphabet is restricted to letters that cannot spell the built-in
;;; "help"/"version" options, and a minimum length of 2 keeps generated names in
;;; the long-option space (single characters are short options).

(defun property-option-keyword (name)
  (intern (string-upcase name) :keyword))

(describe-sequential "property parse"
  (it-property "round-trips value options for arbitrary values"
      ((name (gen-string :min-length 2 :max-length 6 :alphabet "abcdef"))
       (value (gen-string :min-length 1 :max-length 8 :alphabet "abcXYZ0139")))
    (let* ((option (make-option :name name :kind :value))
           (app (make-app :name "demo" :global-options (list option)))
           (invocation (parse-argv app (list "demo"
                                             (format nil "--~A" name)
                                             value))))
      (expect (option-value invocation (property-option-keyword name))
              :to-equal value)))

  (it-property "records flags when present and leaves them null otherwise"
      ((name (gen-string :min-length 2 :max-length 6 :alphabet "abcdef")))
    (let* ((option (make-option :name name :kind :flag))
           (app (make-app :name "demo" :global-options (list option)))
           (key (property-option-keyword name)))
      (expect (option-value (parse-argv app (list "demo" (format nil "--~A" name)))
                            key)
              :to-be-truthy)
      (expect (option-value (parse-argv app (list "demo")) key)
              :to-be-null)))

  (it-property "forwards tokens after -- verbatim to a rest positional"
      ((tokens (gen-list (gen-string :min-length 1 :max-length 5 :alphabet "ab-Z9")
                         :min-length 0 :max-length 5)))
    (let* ((app (make-app :name "demo"
                          :positionals (list (make-positional :key :rest
                                                              :rest-p t))))
           (invocation (parse-argv app (append (list "demo" "--") tokens))))
      (expect (positional-value invocation :rest) :to-equal tokens)))

  (it-property "treats --opt=value and --opt value equivalently"
      ((name (gen-string :min-length 2 :max-length 6 :alphabet "abcdef"))
       (value (gen-string :min-length 1 :max-length 8 :alphabet "abcXYZ019")))
    (let* ((app (make-app :name "demo"
                          :global-options (list (make-option :name name :kind :value))))
           (key (property-option-keyword name))
           (attached (parse-argv app (list "demo" (format nil "--~A=~A" name value))))
           (separated (parse-argv app (list "demo" (format nil "--~A" name) value))))
      (expect (option-value attached key) :to-equal value)
      (expect (option-value separated key) :to-equal value)))

  (it-property "accumulates multiple-p values in argv order"
      ((values (gen-list (gen-string :min-length 1 :max-length 5 :alphabet "abcXYZ019")
                         :min-length 1 :max-length 5)))
    (let* ((app (make-app :name "demo"
                          :global-options (list (make-option :name "tag" :kind :value
                                                            :multiple-p t))))
           (argv (cons "demo" (loop for value in values append (list "--tag" value))))
           (invocation (parse-argv app argv)))
      (expect (option-value invocation :tag) :to-equal values)))

  (it-property "an exclusive group admits at most one member"
      ((raw (gen-list (gen-member '("a" "b" "c" "d")) :min-length 0 :max-length 4)))
    (let* ((names (remove-duplicates raw :test #'string=))
           (app (make-app :name "g"
                          :global-options (exclusive-group
                                           (make-option :name "a" :kind :flag)
                                           (make-option :name "b" :kind :flag)
                                           (make-option :name "c" :kind :flag)
                                           (make-option :name "d" :kind :flag))))
           (argv (cons "g" (mapcar (lambda (name) (format nil "--~A" name)) names))))
      (if (>= (length names) 2)
          (expect (lambda () (parse-argv app argv)) :to-throw 'cli-conflicting-options)
          (expect (parse-argv app argv)))))

  (it-property "a required exclusive group admits exactly one member"
      ((raw (gen-list (gen-member '("a" "b" "c" "d")) :min-length 0 :max-length 4)))
    (let* ((names (remove-duplicates raw :test #'string=))
           (app (make-app :name "g"
                          :global-options (required-exclusive-group
                                           (make-option :name "a" :kind :flag)
                                           (make-option :name "b" :kind :flag)
                                           (make-option :name "c" :kind :flag)
                                           (make-option :name "d" :kind :flag))))
           (argv (cons "g" (mapcar (lambda (name) (format nil "--~A" name)) names))))
      (case (length names)
        (0 (expect (lambda () (parse-argv app argv))
                   :to-throw 'cli-missing-option-value))
        (1 (expect (option-value (parse-argv app argv)
                                 (property-option-keyword (first names)))))
        (t (expect (lambda () (parse-argv app argv))
                   :to-throw 'cli-conflicting-options))))))
