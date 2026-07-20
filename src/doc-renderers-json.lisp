(in-package :cl-cli)

;;;; A JSON schema renderer: emits an app spec as a machine-readable object for
;;;; external tooling (doc generators, GUIs, shell integrations). Dependency
;;;; light -- a small self-contained JSON writer, no external JSON library.
;;;;
;;;; The output describes the author-declared surface: hidden options/commands
;;;; and the auto-added help/version built-ins are omitted, matching the man and
;;;; Markdown renderers. Follows the same optional-stream convention.

(defun %json-escape-string (text)
  (with-output-to-string (out)
    (write-char #\" out)
    (loop for char across (or text "")
          do (case char
               (#\" (write-string "\\\"" out))
               (#\\ (write-string "\\\\" out))
               (#\Newline (write-string "\\n" out))
               (#\Return (write-string "\\r" out))
               (#\Tab (write-string "\\t" out))
               (t (if (< (char-code char) #x20)
                      (format out "\\u~4,'0X" (char-code char))
                      (write-char char out)))))
    (write-char #\" out)))

(defun %json-number (number)
  "Render NUMBER as a valid JSON numeric token.

Integers print directly; any other real is coerced to a double and printed in
fixed notation so a Lisp exponent marker (`1.5d0`) never leaks into the output."
  (if (integerp number)
      (format nil "~D" number)
      (format nil "~F" (coerce number 'double-float))))

(defun %json-bool (value)
  (if value "true" "false"))

(defun %json-array (json-items)
  (format nil "[~{~A~^,~}]" json-items))

(defun %json-string-array (strings)
  (%json-array (mapcar #'%json-escape-string strings)))

(defun %json-member (key json-value)
  "A `\"key\":value` member, or NIL when JSON-VALUE is NIL (i.e. omit the key)."
  (when json-value
    (format nil "~A:~A" (%json-escape-string key) json-value)))

(defun %json-object (&rest members)
  (format nil "{~{~A~^,~}}" (remove nil members)))

(defun %json-keyword-name (keyword)
  (%json-escape-string (string-downcase (symbol-name keyword))))

(defun %json-deprecated (deprecated)
  "Render a :deprecated designator as a JSON value, or NIL to omit the key."
  (cond
    ((null deprecated) nil)
    ((stringp deprecated) (%json-escape-string deprecated))
    (t "true")))

(defun %json-scalar (value)
  "Render a Lisp default VALUE as a JSON scalar or array."
  (cond
    ((null value) "null")
    ((eq value t) "true")
    ((stringp value) (%json-escape-string value))
    ((numberp value) (%json-number value))
    ((listp value) (%json-array (mapcar #'%json-scalar value)))
    (t (%json-escape-string (princ-to-string value)))))

(defun %option->json (option)
  (%json-object
   (%json-member "key" (%json-keyword-name (option-key option)))
   (%json-member "names" (%json-string-array (option-names option)))
   (%json-member "negatedNames"
                 (and (option-negated-names option)
                      (%json-string-array (option-negated-names option))))
   (%json-member "kind" (%json-keyword-name (option-kind option)))
   (%json-member "description"
                 (and (option-description option)
                      (%json-escape-string (option-description option))))
   (%json-member "required" (%json-bool (option-required-p option)))
   (%json-member "multiple" (%json-bool (option-multiple-p option)))
   (%json-member "valueName"
                 (and (option-value-name option)
                      (%json-escape-string (option-value-name option))))
   (%json-member "type" (and (option-value-type option)
                             (%json-keyword-name (option-value-type option))))
   (%json-member "min" (and (option-value-min option)
                            (%json-number (option-value-min option))))
   (%json-member "max" (and (option-value-max option)
                            (%json-number (option-value-max option))))
   (%json-member "delimiter" (and (option-value-delimiter option)
                                  (%json-escape-string (option-value-delimiter option))))
   (%json-member "valueCount"
                 (let ((count (option-value-count option)))
                   (cond
                     ((eq count :+) (%json-escape-string "+"))
                     ((eq count :*) (%json-escape-string "*"))
                     ((and (integerp count) (> count 1)) (%json-number count))
                     (t nil))))
   (%json-member "choices" (and (option-choices option)
                                (%json-string-array (option-choices option))))
   (%json-member "envVars" (and (option-env-vars option)
                                (%json-string-array (option-env-vars option))))
   (%json-member "valueHint" (and (option-value-hint option)
                                  (%json-keyword-name (option-value-hint option))))
   (%json-member "group" (and (option-help-group option)
                              (%json-escape-string (option-help-group option))))
   (%json-member "default" (and (option-default-present-p option)
                                (%json-scalar (option-default option))))
   (%json-member "deprecated" (%json-deprecated (option-deprecated option)))))

(defun %positional->json (positional)
  (%json-object
   (%json-member "key" (%json-keyword-name (positional-spec-key positional)))
   (%json-member "description"
                 (and (positional-spec-description positional)
                      (%json-escape-string (positional-spec-description positional))))
   (%json-member "required" (%json-bool (positional-spec-required-p positional)))
   (%json-member "rest" (%json-bool (positional-spec-rest-p positional)))
   (%json-member "type" (and (positional-spec-value-type positional)
                             (%json-keyword-name (positional-spec-value-type positional))))
   (%json-member "min" (and (positional-spec-value-min positional)
                            (%json-number (positional-spec-value-min positional))))
   (%json-member "max" (and (positional-spec-value-max positional)
                            (%json-number (positional-spec-value-max positional))))
   (%json-member "choices" (and (positional-spec-choices positional)
                                (%json-string-array (positional-spec-choices positional))))
   (%json-member "completionCandidates"
                 (and (positional-spec-completion-candidates positional)
                      (%json-string-array
                       (mapcar #'car (positional-spec-completion-candidates positional)))))
   (%json-member "valueHint" (and (positional-spec-value-hint positional)
                                  (%json-keyword-name (positional-spec-value-hint positional))))
   (%json-member "minCount" (and (positional-spec-min-count positional)
                                 (%json-number (positional-spec-min-count positional))))
   (%json-member "maxCount" (and (positional-spec-max-count positional)
                                 (%json-number (positional-spec-max-count positional))))
   (%json-member "default" (and (positional-spec-default-present-p positional)
                                (%json-scalar (positional-spec-default positional))))))

(defun %command->json (command)
  (%json-object
   (%json-member "name" (%json-escape-string (command-name command)))
   (%json-member "aliases" (and (command-aliases command)
                                (%json-string-array (command-aliases command))))
   (%json-member "group" (and (command-group command)
                              (%json-escape-string (command-group command))))
   (%json-member "description"
                 (and (command-description command)
                      (%json-escape-string (command-description command))))
   (%json-member "options"
                 (%json-array (mapcar #'%option->json
                                      (%doc-visible-options (command-options command)))))
   (%json-member "positionals"
                 (%json-array (mapcar #'%positional->json
                                      (command-positionals command))))
   (%json-member "examples" (and (command-examples command)
                                 (%json-string-array (command-examples command))))
   (%json-member "helpFooter" (and (command-help-footer command)
                                   (%json-escape-string (command-help-footer command))))
   (%json-member "deprecated" (%json-deprecated (command-deprecated command)))
   (let ((subcommands (%visible-commands (command-subcommands command))))
     (%json-member "subcommands"
                   (and subcommands
                        (%json-array (mapcar #'%command->json subcommands)))))))

(defun %app->json (app)
  (%json-object
   (%json-member "name" (%json-escape-string (app-name app)))
   (%json-member "version" (and (app-version-string app)
                                (%json-escape-string (app-version-string app))))
   (%json-member "summary" (and (app-summary app)
                                (%json-escape-string (app-summary app))))
   (%json-member "description" (and (app-description app)
                                    (%json-escape-string (app-description app))))
   (%json-member "options"
                 (%json-array (mapcar #'%option->json
                                      (%doc-visible-options (app-global-options app)))))
   (%json-member "positionals"
                 (%json-array (mapcar #'%positional->json (app-positionals app))))
   (%json-member "commands"
                 (%json-array (mapcar #'%command->json
                                      (%visible-commands (app-commands app)))))
   (%json-member "examples" (and (app-examples app)
                                 (%json-string-array (app-examples app))))
   (%json-member "seeAlso" (and (app-see-also app)
                                (%json-string-array (app-see-also app))))
   (%json-member "authors" (and (app-authors app)
                                (%json-string-array (app-authors app))))))

(defun render-json (app &optional stream)
  "Render APP's spec as a machine-readable JSON object.

With no STREAM, return the JSON as a string. With a STREAM, write to it and
return no values. The object captures the author-declared surface (name,
version, summary, description, global options, positionals, and per-command
options/positionals); hidden entities and the help/version built-ins are
omitted. Output is minified single-line JSON."
  (unless stream
    (return-from render-json
      (with-output-to-string (string-stream)
        (render-json app string-stream))))
  (write-string (%app->json app) stream)
  (terpri stream)
  (values))
