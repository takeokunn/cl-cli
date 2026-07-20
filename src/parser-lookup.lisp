(in-package :cl-cli)

(defun validate-option-relationships (values specs &optional rulebase)
  ;; Most CLIs declare no requires/conflicts at all. Skip building a rulebase
  ;; and running any Prolog proof search when there is nothing to validate --
  ;; otherwise every parse pays for a rulebase plus O(present log present) empty
  ;; queries that can only ever succeed vacuously.
  (unless (some (lambda (spec)
                  (or (option-requires spec)
                      (option-requires-any-of spec)
                      (option-conflicts-with spec)))
                specs)
    (return-from validate-option-relationships values))
  ;; SPECS' :requires/:conflicts graph is fixed at spec-construction time, so
  ;; %VALIDATE-APP-SPEC already built and validated this exact rulebase once
  ;; and cached it on the app/command spec. Callers pass it in via RULEBASE;
  ;; only rebuild here as a fallback for callers validating an ad hoc SPECS
  ;; list that was never run through MAKE-APP.
  (let* ((rulebase (or rulebase (make-option-relation-rulebase specs)))
         (present-specs
           (remove-if-not (lambda (spec)
                            (plist-has-key-p values (option-key spec)))
                          specs))
         ;; Each transitive required-key closure is a full cl-prolog proof
         ;; search. The sort comparator below asks for the same option's closure
         ;; on every comparison (O(n log n) queries) and the requires loop asks
         ;; again, so memoize per key: one query per option, reused everywhere.
         (closure-cache (make-hash-table :test #'eq))
         (spec-by-key (make-hash-table :test #'eq)))
    (dolist (spec specs)
      (setf (gethash (option-key spec) spec-by-key) spec))
    (flet ((closure-of (key)
             (multiple-value-bind (cached present-p) (gethash key closure-cache)
               (if present-p
                   cached
                   (setf (gethash key closure-cache)
                         (transitive-required-option-keys rulebase key))))))
     (let ((roots
             ;; Report the most upstream failure first: an option that (directly
             ;; or transitively) requires others is validated before them. A
             ;; requiring option always has a strictly larger required-closure
             ;; than anything it depends on, so ordering by closure size (with a
             ;; key-name tiebreaker) is a valid strict weak ordering -- unlike the
             ;; previous reachability comparator, which was non-transitive and so
             ;; gave SORT undefined behaviour (notably across implementations).
             (stable-sort-copy
              present-specs
              (lambda (left right)
                (let ((left-size (length (closure-of (option-key left))))
                      (right-size (length (closure-of (option-key right)))))
                  (if (= left-size right-size)
                      (string< (string (option-key left))
                               (string (option-key right)))
                      (> left-size right-size)))))))
      (dolist (spec roots values)
        (dolist (dependency-key (closure-of (option-key spec)))
          (let ((dependency (gethash dependency-key spec-by-key)))
            (unless (plist-has-key-p values (option-key dependency))
            (signal-cli-error 'cli-missing-dependent-option
                              (if (option-hidden-p spec)
                                  (format nil "A hidden option requires ~A."
                                          (public-option-display-name dependency))
                                  (format nil "Option ~A requires ~A."
                                          (public-option-display-name spec)
                                          (public-option-display-name dependency)))
                              :option (option-key spec)
                              :dependency (option-key dependency)))))
      (when (option-requires-any-of spec)
        (let* ((alternative-keys (any-of-required-option-keys rulebase (option-key spec)))
               (alternatives (mapcar (lambda (key) (gethash key spec-by-key))
                                     alternative-keys)))
          (unless (some (lambda (alternative)
                          (plist-has-key-p values (option-key alternative)))
                        alternatives)
            (signal-cli-error 'cli-missing-any-of-options
                              (if (option-hidden-p spec)
                                  (format nil "A hidden option requires one of: ~{~A~^, ~}."
                                          (mapcar #'public-option-display-name alternatives))
                                  (format nil "Option ~A requires one of: ~{~A~^, ~}."
                                          (public-option-display-name spec)
                                          (mapcar #'public-option-display-name alternatives)))
                              :option (option-key spec)
                              :alternatives (mapcar #'option-key alternatives)))))
      (dolist (target (option-conflicts-with spec))
        (let ((other (resolve-related-option-spec specs target)))
          (when (plist-has-key-p values (option-key other))
            (signal-cli-error 'cli-conflicting-options
                              (if (option-hidden-p spec)
                                  (format nil "A hidden option conflicts with ~A."
                                          (public-option-display-name other))
                                  (format nil "Option ~A conflicts with ~A."
                                          (public-option-display-name spec)
                                          (public-option-display-name other)))
                              :left-option (option-key spec)
                              :right-option (option-key other))))))))))

(defun validate-required-option-groups (values specs)
  "Signal CLI-MISSING-OPTION-VALUE when a required option group has no member set.

Exclusivity within a group is already enforced through :conflicts-with, so this
only checks the at-least-one obligation that REQUIRED-EXCLUSIVE-GROUP adds. Each
distinct group is checked once."
  (let ((seen (make-hash-table :test #'eq)))
    (dolist (spec specs values)
      (let ((group (option-group spec)))
        (when (and group
                   (option-group-required-p group)
                   (not (gethash group seen)))
          (setf (gethash group seen) t)
          (unless (some (lambda (key) (plist-has-key-p values key))
                        (option-group-members group))
            (let ((member-specs
                    (remove nil
                            (mapcar (lambda (key)
                                      (find key specs :key #'option-key :test #'eq))
                                    (option-group-members group)))))
              (signal-cli-error 'cli-missing-option-value
                                (format nil "Exactly one of ~{~A~^, ~} is required."
                                        (mapcar #'public-option-display-name
                                                member-specs))
                                :option (option-key (first member-specs))))))))))

(defun validate-inclusive-groups (values specs)
  "Signal when an all-or-none option group has some but not all members set.

Each distinct :INCLUSIVE group is checked once. Hidden members are named
generically in the error, mirroring the other relationship diagnostics."
  (let ((seen (make-hash-table :test #'eq)))
    (dolist (spec specs values)
      (let ((group (option-group spec)))
        (when (and group
                   (eq (option-group-mode group) :inclusive)
                   (not (gethash group seen)))
          (setf (gethash group seen) t)
          (let* ((members (option-group-members group))
                 (present (remove-if-not (lambda (key) (plist-has-key-p values key)) members))
                 (missing (remove-if (lambda (key) (plist-has-key-p values key)) members)))
            (when (and present missing)
              (flet ((named (key) (find key specs :key #'option-key :test #'eq)))
                (signal-cli-error
                 'cli-missing-dependent-option
                 (format nil "Options ~{~A~^, ~} must be used together; missing ~{~A~^, ~}."
                         (mapcar (lambda (key) (public-option-display-name (named key))) members)
                         (mapcar (lambda (key) (public-option-display-name (named key))) missing))
                 :option (option-key (named (first present)))
                 :dependency (first missing))))))))))

(defun %relation-target-present-p (values specs target)
  (let ((spec (resolve-related-option-spec specs target)))
    (and spec (plist-has-key-p values (option-key spec)))))

(defun validate-conditional-requirements (values specs)
  "Enforce :required-if / :required-unless for options absent from VALUES.

:required-if makes an option mandatory when any listed target is present;
:required-unless makes it mandatory unless any listed target is present."
  (dolist (spec specs values)
    (unless (plist-has-key-p values (option-key spec))
      (let ((trigger (find-if (lambda (target)
                                (%relation-target-present-p values specs target))
                              (option-required-if spec))))
        (when trigger
          (signal-cli-error
           'cli-missing-option-value
           (format nil "Option ~A is required when ~A is supplied."
                   (public-option-display-name spec)
                   (public-option-display-name (resolve-related-option-spec specs trigger)))
           :option (option-key spec))))
      (when (and (option-required-unless spec)
                 (notany (lambda (target)
                           (%relation-target-present-p values specs target))
                         (option-required-unless spec)))
        (signal-cli-error
         'cli-missing-option-value
         (format nil "Option ~A is required unless one of ~{~A~^, ~} is supplied."
                 (public-option-display-name spec)
                 (mapcar (lambda (target)
                           (public-option-display-name
                            (resolve-related-option-spec specs target)))
                         (option-required-unless spec)))
         :option (option-key spec))))))

(defun option-table-from-specs (specs)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (spec specs table)
      (dolist (entry (%option-table-entries spec))
        (destructuring-bind (name negated-p) entry
          (let ((key (canonical-option-name name)))
            (%register-table-entry table
                                   key
                                    (list :spec spec
                                          :name key
                                          :negated-p negated-p)
                                    "option name"
                                    (option-token-display-name key))))))))

(defun command-table-from-specs (commands)
  (let ((table (make-hash-table :test 'equal)))
    (dolist (command commands table)
      (%register-table-entry table
                             (command-name command)
                             (list :command command
                                   :name (command-name command))
                             "command name"
                             (command-name command))
      (dolist (alias (command-aliases command))
        (%register-table-entry table
                               alias
                               (list :command command
                                     :name alias)
                               "command name"
                               alias)))))

(defun public-option-candidate-p (spec)
  (or (not (option-hidden-p spec))
      (built-in-option-p spec)))

(defun public-command-candidate-p (command)
  (not (command-hidden-p command)))

(defun option-candidate-names (specs &key short-only-p long-only-p)
  (let ((candidates nil))
    (dolist (spec specs (nreverse candidates))
      (when (public-option-candidate-p spec)
        (dolist (name (option-names spec))
          (when (or (and short-only-p (= (length name) 1))
                    (and long-only-p (> (length name) 1))
                    (and (not short-only-p) (not long-only-p)))
            (push (option-token-display-name name)
                  candidates)))))))

(defun command-candidate-names (app)
  (let ((candidates nil))
    (dolist (command (app-commands app) (nreverse candidates))
      (when (public-command-candidate-p command)
        (push (command-name command) candidates)
        (dolist (alias (command-aliases command))
          (push alias candidates))))))

(defun unknown-option-message (raw-name candidates)
  (format nil "Unknown option: ~A~A"
          raw-name
          (format-suggestion-suffix raw-name candidates)))

(defun unknown-command-message (app command-name)
  (format nil "Unknown command: ~A~A"
          command-name
          (format-suggestion-suffix command-name
                                    (command-candidate-names app))))

(defvar *allow-abbreviated-options* nil
  "When true, RESOLVE-LONG-OPTION-ENTRY accepts a unique long-option prefix.

Bound by PARSE-ARGV from the app's :allow-abbreviated-options flag so the parser
stays strict by default; see MAKE-APP.")

(defun resolve-option-entry (table name)
  (gethash (canonical-option-name name) table))

(defun %abbreviated-long-option-entry (name table)
  "Resolve NAME as a unique long-option prefix in TABLE, or signal / return NIL.

Collects every long (multi-character) table key that has NAME as a prefix,
collapsing entries that denote the same option and negation sense. A single
distinct result is returned; several distinct results signal an ambiguity;
no match returns NIL so the caller can report an unknown option."
  (let ((results '()))
    (maphash
     (lambda (key entry)
       (when (and (> (length key) 1)
                  (<= (length name) (length key))
                  (string= name key :end2 (length name)))
         (pushnew entry results
                  :test (lambda (a b)
                          (and (eq (option-key (option-entry-spec a))
                                   (option-key (option-entry-spec b)))
                               (eq (option-entry-negated-p a)
                                   (option-entry-negated-p b)))))))
     table)
    (cond
      ((null results) nil)
      ((null (rest results)) (first results))
      (t
       (signal-cli-error
        'cli-unknown-option
        (format nil "Ambiguous option --~A matches: ~{--~A~^, ~}"
                name
                (sort (mapcar (lambda (entry) (getf entry :name)) results)
                      #'string<))
        :option name)))))

(defun resolve-long-option-entry (name table specs)
  (or (resolve-option-entry table name)
      (and *allow-abbreviated-options*
           (%abbreviated-long-option-entry name table))
      (signal-cli-error 'cli-unknown-option
                        (unknown-option-message (format nil "--~A" name)
                                                (option-candidate-names specs
                                                                        :long-only-p t))
                        :option name)))

(defun option-entry-spec (entry)
  (getf entry :spec))

(defun option-entry-negated-p (entry)
  (getf entry :negated-p))

(defun resolve-command-spec (table name)
  (gethash (canonical-name name) table))

(defun short-option-candidates (specs)
  (option-candidate-names specs :short-only-p t))

(defun signal-unknown-short-option (name specs)
  (signal-cli-error 'cli-unknown-option
                    (unknown-option-message (format nil "-~A" name)
                                            (short-option-candidates specs))
                    :option name))
