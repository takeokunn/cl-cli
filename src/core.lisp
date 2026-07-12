(in-package :cl-cli)

(defun ensure-string (thing)
  (etypecase thing
    (string thing)
    (symbol (string-downcase (symbol-name thing)))
    (character (string thing))))

(defun canonical-name (thing)
  (string-downcase (ensure-string thing)))

(defun canonical-option-name (thing)
  (let* ((raw (ensure-string thing))
         (stripped (cond
                     ((and (>= (length raw) 2)
                           (char= (char raw 0) #\-)
                           (char= (char raw 1) #\-))
                      (subseq raw 2))
                     ((and (> (length raw) 0)
                           (char= (char raw 0) #\-))
                      (subseq raw 1))
                     (t raw))))
    (if (= (length stripped) 1)
        stripped
        (string-downcase stripped))))

(defun option-token-display-name (name)
  (if (= (length name) 1)
      (format nil "-~A" name)
      (format nil "--~A" name)))

(defun option-relation-target-display-name (target)
  (etypecase target
    (string (option-token-display-name target))
    (symbol (option-token-display-name (string-downcase (symbol-name target))))))

(defun option-keyword (thing)
  (intern (string-upcase (canonical-name thing)) :keyword))

(defun split-string-once (string separator)
  (let ((index (position separator string)))
    (if index
        (values (subseq string 0 index) (subseq string (1+ index)))
        (values string nil))))

(defun plist-has-key-p (plist key)
  (not (eq (getf plist key :__missing__) :__missing__)))

(defun command-line-option-p (token)
  (and (stringp token)
       (> (length token) 0)
       (char= (char token 0) #\-)))

(defun long-option-token-p (token)
  (and (command-line-option-p token)
       (>= (length token) 2)
       (char= (char token 1) #\-)))

(defun short-option-token-p (token)
  (and (command-line-option-p token)
       (or (= (length token) 2)
           (not (char= (char token 1) #\-)))))

(defun stable-sort-copy (sequence predicate &key key)
  (sort (copy-seq sequence) predicate :key key))

(defun levenshtein-distance (left right)
  (let* ((left-length (length left))
         (right-length (length right))
         (column (make-array (1+ right-length))))
    (loop for j from 0 to right-length
          do (setf (aref column j) j))
    (loop for i from 1 to left-length
          do (let ((previous-diagonal (1- i)))
               (setf (aref column 0) i)
               (loop for j from 1 to right-length
                     for saved = (aref column j)
                     do (setf (aref column j)
                              (min (1+ (aref column j))
                                   (1+ (aref column (1- j)))
                                   (+ previous-diagonal
                                      (if (char-equal (char left (1- i))
                                                      (char right (1- j)))
                                          0
                                          1))))
                        (setf previous-diagonal saved))))
    (aref column right-length)))

(defun suggestion-threshold (target candidate)
  (max 1
       (min 3
            (floor (max (length target)
                        (length candidate))
                   3))))

(defun best-string-suggestion (target candidates)
  (let* ((normalized-target (canonical-name target))
         (best nil)
         (best-distance nil))
    (dolist (candidate candidates best)
      (let* ((normalized-candidate (canonical-name candidate))
             (distance (levenshtein-distance normalized-target
                                            normalized-candidate)))
        (when (or (null best-distance)
                  (< distance best-distance))
          (setf best candidate
                best-distance distance))))
    (when (and best
               (<= best-distance
                   (suggestion-threshold normalized-target
                                         (canonical-name best))))
      best)))

(defun format-suggestion-suffix (target candidates)
  (let ((suggestion (best-string-suggestion target candidates)))
    (if suggestion
        (format nil " Did you mean: ~A?" suggestion)
        "")))

(defmacro with-value-parse-errors ((condition-class message-form &rest initargs) &body body)
  `(handler-case
       (progn ,@body)
     (cli-usage-error (condition)
       (error condition))
     (error (condition)
       (signal-cli-error ,condition-class
                         ,message-form
                         ,@initargs
                         :cause condition))))
