(in-package :cl-cli)

(defvar *help-color* nil
  "When true, the help printers wrap headings and names in ANSI styling.

Bound by PRINT-APP-HELP / PRINT-COMMAND-HELP / RUN-APP. The :color argument that
sets it accepts T, NIL, or :AUTO; :AUTO resolves via %RESOLVE-HELP-COLOR
(NO_COLOR / CLICOLOR_FORCE / terminal detection) before this variable is bound,
so by the time styling runs the value is always a concrete boolean.")

(defun %ansi (code text)
  (if *help-color*
      (format nil "~C[~Am~A~C[0m" #\Escape code text #\Escape)
      text))

(defun %terminal-safe-text (text)
  "Drop terminal control characters from free-form help metadata."
  (with-output-to-string (out)
    (loop for char across (or text "")
          do (let ((code (char-code char)))
               (cond
                 ((member char '(#\Newline #\Return #\Tab))
                  (write-char #\Space out))
                 ((or (< code 32)
                      (= code 127)
                      (and (>= code 128) (< code 160))))
                 (t (write-char char out)))))))

(defun %style-heading (text)
  (%ansi "1" text))

(defun %style-name (text)
  (%ansi "36" text))

(defun %style-padded-name (text width)
  "Pad TEXT to WIDTH visible columns, then style it, so alignment is preserved."
  (%style-name (format nil "~VA" width text)))

(defvar *help-width* nil
  "When a positive integer, help descriptions are word-wrapped to this column.

Bound by PRINT-APP-HELP / PRINT-COMMAND-HELP / RUN-APP. The :width argument that
sets it accepts a positive integer, NIL, or :AUTO; :AUTO resolves via
%RESOLVE-HELP-WIDTH ($COLUMNS) to a width or NIL before this variable is bound.")

(defparameter +help-description-column+ 27
  "The visible column where a help row's description begins: 2 + 24 + 1.")

(defun %wrap-text (text width)
  "Greedily word-wrap TEXT to WIDTH columns, returning a list of lines."
  (let ((words (remove-if (lambda (w) (zerop (length w)))
                          (uiop:split-string text
                                             :separator '(#\Space #\Tab #\Newline))))
        (lines nil)
        (current ""))
    (dolist (word words)
      (cond
        ((zerop (length current)) (setf current word))
        ((<= (+ (length current) 1 (length word)) width)
         (setf current (concatenate 'string current " " word)))
        (t (push current lines)
           (setf current word))))
    (when (plusp (length current))
      (push current lines))
    (nreverse lines)))

(defun %emit-help-row (stream padded-name description)
  "Emit a `  NAME  DESCRIPTION` row, word-wrapping DESCRIPTION under *HELP-WIDTH*."
  (let ((width *help-width*)
        (description (%terminal-safe-text description)))
    (if (and width
             (integerp width)
             (plusp (length description))
             (> width (+ +help-description-column+ 8)))
        (let ((lines (%wrap-text description
                                 (- width +help-description-column+))))
          (format stream "  ~A ~A~%" padded-name (or (first lines) ""))
          (dolist (line (rest lines))
            (format stream "~A~A~%"
                    (make-string +help-description-column+ :initial-element #\Space)
                    line)))
        (format stream "  ~A ~A~%" padded-name description))))

(defun %command-display-name (command)
  (if (command-aliases command)
      (format nil "~A (~{~A~^, ~})"
              (command-name command)
              (command-aliases command))
      (command-name command)))

(defun %usage-options-token (label)
  (format nil "[~A]" label))

(defun %join-help-metadata (parts)
  (if parts
      (format nil " (~{~A~^; ~})" parts)
      ""))

(defun %public-relation-targets
    (option options relation-targets &optional (target-table (%option-target-table options)))
  (let ((targets nil))
    (dolist (target relation-targets (nreverse targets))
      (let ((resolved (%lookup-option-target target-table target)))
        (when (and resolved
                   (not (eq (option-key resolved) (option-key option)))
                   (public-option-candidate-p resolved))
          (push target targets))))))

(defun %option-group-member-names
    (option options &optional (target-table (%option-target-table options)))
  "Public display names of the members of OPTION's exclusive group, or NIL."
  (let ((group (option-group option)))
    (when group
      (loop for key in (option-group-members group)
            for spec = (%lookup-option-target target-table key)
            when (and spec (public-option-candidate-p spec))
              collect (option-token-display-name (first (option-names spec)))))))

(defun %option-intra-group-conflict-p
    (option options target &optional (target-table (%option-target-table options)))
  "True when TARGET is another member of OPTION's own exclusive group."
  (let ((group (option-group option)))
    (and group
         (let ((resolved (%lookup-option-target target-table target)))
           (and resolved
                (member (option-key resolved)
                        (option-group-members group)))))))

(defun %deprecation-note (deprecated)
  "A help/doc note for a DEPRECATED designator (T or reason string), or NIL."
  (cond
    ((null deprecated) nil)
    ((stringp deprecated) (format nil "deprecated: ~A" (%terminal-safe-text deprecated)))
    (t "deprecated")))

(defun %value-hint-note (hint)
  "A help-metadata fragment for a :value-hint, or NIL."
  (case hint
    (:file "expects a file")
    (:dir "expects a directory")
    (t nil)))

(defun %numeric-range-metadata (min max)
  "Render inclusive numeric bounds as a help-metadata fragment, or NIL."
  (cond
    ((and min max) (format nil "range: ~A..~A" min max))
    (min (format nil "min: ~A" min))
    (max (format nil "max: ~A" max))
    (t nil)))

(defun %option-metadata-parts
    (option options &optional (target-table (%option-target-table options)))
  (let ((parts nil))
    (let ((deprecation (%deprecation-note (option-deprecated option))))
      (when deprecation
        (push deprecation parts)))
    (when (option-multiple-p option)
      (push "repeatable" parts))
    (when (eq (option-kind option) :count)
      (push "count" parts))
    (when (option-required-p option)
      (push "required" parts))
    (when (and (option-value-type option)
               (not (eq (option-value-type option) :string)))
      (push (format nil "type: ~(~A~)" (option-value-type option)) parts))
    (let ((range (%numeric-range-metadata (option-value-min option)
                                          (option-value-max option))))
      (when range
        (push range parts)))
    (when (option-value-delimiter option)
      (push (format nil "list (delimited by '~A')" (option-value-delimiter option))
            parts))
    (let ((hint (%value-hint-note (option-value-hint option))))
      (when hint (push hint parts)))
    ;; A :count option's implicit 0 default is conventional noise, so suppress
    ;; it; a caller-chosen non-zero starting count is still worth surfacing.
    (when (and (option-default-present-p option)
               (not (and (eq (option-kind option) :count)
                         (eql (option-default option) 0))))
      (push (format nil "default: ~A" (option-default option)) parts))
    (when (option-env-vars option)
      (push (format nil "env: ~{~A~^, ~}" (option-env-vars option)) parts))
    (when (option-choices option)
      (push (format nil "choices: ~{~A~^ | ~}" (option-choices option)) parts))
    (let ((group-members (%option-group-member-names option options target-table)))
      (when group-members
        (push (if (eq (option-group-mode (option-group option)) :inclusive)
                  (format nil "all or none of: ~{~A~^ | ~}" group-members)
                  (format nil "~A one of: ~{~A~^ | ~}"
                          (if (option-group-required-p (option-group option))
                              "exactly"
                              "at most")
                          group-members))
              parts)))
    (let ((visible-requires (%public-relation-targets option options
                                                      (option-requires option)
                                                      target-table)))
      (when visible-requires
        (push (format nil "requires: ~{~A~^, ~}"
                      (mapcar #'option-relation-target-display-name
                              visible-requires))
              parts)))
    (let ((visible-requires-any-of (%public-relation-targets
                                     option options
                                     (option-requires-any-of option)
                                     target-table)))
      (when visible-requires-any-of
        (push (format nil "requires one of: ~{~A~^, ~}"
                      (mapcar #'option-relation-target-display-name
                              visible-requires-any-of))
              parts)))
    (let ((visible-required-if (%public-relation-targets
                                option options (option-required-if option)
                                target-table)))
      (when visible-required-if
        (push (format nil "required if: ~{~A~^, ~}"
                      (mapcar #'option-relation-target-display-name
                              visible-required-if))
              parts)))
    (let ((visible-required-unless (%public-relation-targets
                                    option options (option-required-unless option)
                                    target-table)))
      (when visible-required-unless
        (push (format nil "required unless: ~{~A~^, ~}"
                      (mapcar #'option-relation-target-display-name
                              visible-required-unless))
              parts)))
    ;; Conflicts among members of this option's own group are already conveyed by
    ;; the "one of" line above; only surface conflicts with options outside it.
    (let ((visible-conflicts
            (remove-if (lambda (target)
                         (%option-intra-group-conflict-p option options target
                                                        target-table))
                       (%public-relation-targets option options
                                                 (option-conflicts-with option)
                                                 target-table))))
      (when visible-conflicts
        (push (format nil "conflicts: ~{~A~^, ~}"
                      (mapcar #'option-relation-target-display-name
                              visible-conflicts))
              parts)))
    (nreverse parts)))

(defun %option-metadata-string
    (option options &optional (target-table (%option-target-table options)))
  (%join-help-metadata (%option-metadata-parts option options target-table)))

(defun %option-display-string (option)
  (with-output-to-string (out)
    (let ((index 0))
      (labels ((write-option-name (name)
                 (when (> index 0)
                   (write-string ", " out))
                 (write-string (option-token-display-name name) out)
                 (incf index)))
        (dolist (name (option-names option))
          (write-option-name name))
        (dolist (name (option-negated-names option))
          (write-option-name name))))
    (when (and (option-kind option)
               (not (member (option-kind option) '(:flag :boolean :count))))
      (let ((value-name (or (option-value-name option)
                            (symbol-name (option-key option))))
            (count (or (option-value-count option) 1)))
        (cond
          ((eq (option-kind option) :optional-value)
           (format out "[=<~A>]" value-name))
          ((variadic-value-count-p count)
           (format out " <~A>..." value-name))
          ((and (integerp count) (> count 1))
           (dotimes (i count)
             (format out " <~A>" value-name)))
          (t
           (format out " <~A>" value-name)))))))

(defun %required-option-synopsis-token (option)
  "Render OPTION as a compact required-option synopsis fragment.

Just the primary name and, for value-bearing kinds, a `<VALUE>` placeholder --
e.g. `--output <FILE>`. Unlike %OPTION-DISPLAY-STRING this omits aliases and
short forms, which belong in the OPTIONS listing, not the one-line synopsis."
  (with-output-to-string (out)
    (write-string (option-token-display-name (first (option-names option))) out)
    (when (and (option-kind option)
               (not (member (option-kind option) '(:flag :boolean :count))))
      (let ((value-name (or (option-value-name option)
                            (symbol-name (option-key option)))))
        (format out " <~A>" value-name)))))

(defun %required-options-synopsis (options)
  "A leading-space synopsis of the visible, required options in OPTIONS.

Required options are spelled out in the usage line -- e.g. `--output <FILE>` --
so the synopsis shows what the user must supply instead of burying it in the
`[options]` catch-all. Non-required and hidden options stay in the catch-all;
built-ins are never required, so they never appear here. Returns \"\" when there
are no required options, leaving existing usage lines untouched."
  (with-output-to-string (out)
    (dolist (option options)
      (when (and (option-required-p option)
                 (not (option-hidden-p option)))
        (format out " ~A" (%required-option-synopsis-token option))))))

(defun %option-description-string
    (option options &optional (target-table (%option-target-table options)))
  (concatenate 'string
               (or (option-description option) "")
               (%option-metadata-string option options target-table)))

(defun %print-option-row
    (stream option options &optional (target-table (%option-target-table options)))
  (%emit-help-row stream
                  (%style-padded-name (%option-display-string option) 24)
                  (%option-description-string option options target-table)))

(defun %usage-positionals-string (positionals)
  (with-output-to-string (out)
    (dolist (positional positionals)
      (format out " ~A" (%format-positional-token positional)))))

(defun %format-root-usage (app)
  (with-output-to-string (out)
    (format out "Usage: ~A" (%terminal-safe-text (app-name app)))
    (when (app-global-options app)
      (format out " ~A" (%usage-options-token "global-options")))
    (write-string (%required-options-synopsis (app-global-options app)) out)
    (cond
      ((app-positionals app)
       (write-string (%usage-positionals-string (app-positionals app)) out))
      ((app-handler app)
       (format out " ~A" (%usage-options-token "args"))))
    (terpri out)))

(defun %format-positional-token (positional)
  (let ((name (symbol-name (positional-spec-key positional))))
    (cond
      ((positional-spec-rest-p positional)
       (if (positional-spec-required-p positional)
           (format nil "~A..." name)
           (format nil "[~A...]" name)))
      ((positional-spec-required-p positional)
       name)
      (t
       (format nil "[~A]" name)))))

(defun %visible-commands (commands)
  (stable-sort-copy (remove-if #'command-hidden-p commands)
                    #'string<
                    :key #'command-name))

(defun %command-sections (commands)
  (let ((ungrouped nil)
        (group-order nil)
        (group-table (make-hash-table :test #'equal)))
    (dolist (command commands)
      (let ((group (command-group command)))
        (if group
            (progn
              (unless (gethash group group-table)
                (setf (gethash group group-table) nil)
                (push group group-order))
              (push command (gethash group group-table)))
            (push command ungrouped))))
    (nconc (when ungrouped
             (list (cons nil (nreverse ungrouped))))
           (mapcar (lambda (group)
                     (cons group (nreverse (gethash group group-table))))
                   (nreverse group-order)))))

(defun %command-description-string (command)
  "COMMAND's description with a trailing deprecation note when applicable.

Shared by the interactive help printer and the man/Markdown doc renderers so a
deprecated command reads the same everywhere."
  (let ((deprecation (%deprecation-note (command-deprecated command)))
        (description (or (command-description command) "")))
    (cond
      ((null deprecation) description)
      ((plusp (length description)) (format nil "~A (~A)" description deprecation))
      (t (format nil "(~A)" deprecation)))))

(defun %print-command-row (stream command)
  (%emit-help-row stream
                  (%style-padded-name (%command-display-name command) 24)
                  (%command-description-string command)))

(defun %format-command-dispatch-usage (app)
  (format nil "Usage: ~A~A <command> [args]~%"
          (%terminal-safe-text (app-name app))
          (%required-options-synopsis (app-global-options app))))

(defun %print-commands (stream commands)
  (let ((sections (%command-sections (%visible-commands commands))))
    (when sections
      (format stream "~&~A~%" (%style-heading "Commands:"))
      (dolist (section sections)
        (when (car section)
          (format stream "~&~A~%" (%style-heading (format nil "~A:" (car section)))))
        (dolist (command (cdr section))
          (%print-command-row stream command))))))

(defun %positional-metadata-parts (positional)
  (let ((parts nil))
    (when (positional-spec-default-present-p positional)
      (push (format nil "default: ~A" (positional-spec-default positional)) parts))
    (when (and (positional-spec-value-type positional)
               (not (eq (positional-spec-value-type positional) :string)))
      (push (format nil "type: ~(~A~)" (positional-spec-value-type positional)) parts))
    (let ((range (%numeric-range-metadata (positional-spec-value-min positional)
                                          (positional-spec-value-max positional))))
      (when range
        (push range parts)))
    (when (positional-spec-choices positional)
      (push (format nil "choices: ~{~A~^ | ~}" (positional-spec-choices positional))
            parts))
    (let ((hint (%value-hint-note (positional-spec-value-hint positional))))
      (when hint (push hint parts)))
    (let ((min (positional-spec-min-count positional))
          (max (positional-spec-max-count positional)))
      (cond
        ((and min max) (push (format nil "~A..~A values" min max) parts))
        (min (push (format nil "at least ~A value~:P" min) parts))
        (max (push (format nil "at most ~A value~:P" max) parts))))
    (nreverse parts)))

(defun %positional-description-string (positional)
  (concatenate 'string
               (or (positional-spec-description positional) "")
               (%join-help-metadata (%positional-metadata-parts positional))))

(defun %print-positional-row (stream positional)
  (%emit-help-row stream
                  (%style-padded-name (%format-positional-token positional) 24)
                  (%positional-description-string positional)))

(defun %print-examples (stream examples)
  (when examples
    (format stream "~&~A~%" (%style-heading "Examples:"))
    (dolist (example examples)
      (format stream "  ~A~%" (%terminal-safe-text example)))))
