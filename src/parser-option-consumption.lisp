(in-package :cl-cli)

(defun parse-long-option-token (token)
  (let ((body (subseq token 2)))
    (multiple-value-bind (name attached) (split-string-once body #\=)
      (values (canonical-option-name name) attached))))

(defun parse-short-cluster (token)
  (subseq token 1))

(defun consume-long-option-token (token specs table values action remaining)
  (multiple-value-bind (name attached) (parse-long-option-token token)
    (let* ((entry (resolve-long-option-entry name table specs))
           (spec (option-entry-spec entry))
           (negated-p (option-entry-negated-p entry)))
      (case (option-kind spec)
        (:flag
         (when attached
           (signal-option-does-not-take-value (format nil "--~A" name)))
         (multiple-value-bind (new-values new-action)
             (store-flag-option values spec action)
           (values new-values (rest remaining) new-action
                   (option-stop-parsing-p spec))))
        (:boolean
         (when attached
           (signal-option-does-not-take-value (format nil "--~A" name)))
         (multiple-value-bind (new-values new-action)
             (store-boolean-option-value values spec action negated-p)
           (values new-values (rest remaining) new-action
                   (option-stop-parsing-p spec))))
        ((:value :optional-value)
         (consume-value-option spec attached (rest remaining) values action
                               (format nil "--~A" name)))))))

(defun consume-value-option (spec attached tokens values action token-name)
  (when (and (eq (option-kind spec) :value)
             (null attached)
             (null tokens))
    (signal-cli-error 'cli-missing-option-value
                      (format nil "Missing value for ~A" token-name)
                      :option (option-key spec)))
  (let* ((consume-separated-optional-p
           (and (eq (option-kind spec) :optional-value)
                (option-consume-optional-value-p spec)
                tokens
                (not (command-line-option-p (first tokens)))))
         (raw (cond
                (attached attached)
                (consume-separated-optional-p (first tokens))
                ((eq (option-kind spec) :optional-value) t)
                (t (first tokens)))))
    (when (and (eq (option-kind spec) :flag) raw)
      (signal-option-does-not-take-value token-name))
    (multiple-value-setq (values action)
      (store-parsed-option-value values spec action raw))
    (when (and (eq (option-kind spec) :value)
               (null attached)
               tokens)
      (setf tokens (rest tokens)))
    (when consume-separated-optional-p
      (setf tokens (rest tokens)))
    (values values tokens action (option-stop-parsing-p spec))))

(defun consume-short-cluster (cluster tokens specs table values action)
  (loop for index from 0 below (length cluster)
        do (let* ((name (string (char cluster index)))
                  (entry (resolve-option-entry table name)))
             (unless entry
               (signal-unknown-short-option name specs))
             (let ((spec (option-entry-spec entry)))
               (case (option-kind spec)
                 (:flag
                  (multiple-value-setq (values action)
                    (store-flag-option values spec action))
                  (when (option-stop-parsing-p spec)
                    (return-from consume-short-cluster
                      (values values tokens action t))))
                 (:boolean
                  (multiple-value-setq (values action)
                    (store-boolean-option-value values spec action nil))
                  (when (option-stop-parsing-p spec)
                    (return-from consume-short-cluster
                      (values values tokens action t))))
                 (:optional-value
                  (let* ((rest (subseq cluster (1+ index)))
                         (attached (and (> (length rest) 0) rest))
                         (consume-separated-optional-p
                           (and (null attached)
                                (option-consume-optional-value-p spec)
                                tokens
                                (not (command-line-option-p (first tokens)))))
                         (raw (cond
                                (attached attached)
                                (consume-separated-optional-p (first tokens))
                                (t t))))
                    (multiple-value-setq (values action)
                      (store-parsed-option-value values spec action raw))
                    (when consume-separated-optional-p
                      (setf tokens (rest tokens)))
                    (return-from consume-short-cluster
                      (values values tokens action (option-stop-parsing-p spec)))))
                 (:value
                  (let* ((rest (subseq cluster (1+ index)))
                         (attached (and (> (length rest) 0) rest))
                         (raw (or attached (first tokens))))
                    (when (and (null attached) (null tokens))
                      (signal-cli-error 'cli-missing-option-value
                                        (format nil "Missing value for -~A" name)
                                        :option (option-key spec)))
                    (multiple-value-setq (values action)
                      (store-parsed-option-value values spec action raw))
                    (when (and (null attached) tokens)
                      (setf tokens (rest tokens)))
                    (return-from consume-short-cluster
                      (values values tokens action (option-stop-parsing-p spec)))))))))
  (values values tokens action nil))

(defun consume-argument-option-token (token validated-specs table values action
                                      remaining)
  (cond
    ((long-option-token-p token)
     (multiple-value-bind (new-values new-remaining new-action done-p)
         (consume-long-option-token token validated-specs table values action
                                    remaining)
       (values new-values new-remaining new-action done-p t)))
    ((short-option-token-p token)
     (multiple-value-bind (new-values new-remaining new-action done-p)
         (consume-short-cluster (parse-short-cluster token)
                                (rest remaining)
                                validated-specs
                                table
                                values
                                action)
       (values new-values new-remaining new-action done-p t)))
    (t
     (values values remaining action nil nil))))
