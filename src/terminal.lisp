(in-package :cl-cli)

;;;; Terminal capability detection backing :color :auto and :width :auto.
;;;;
;;;; Two layers. The environment rules -- NO_COLOR, CLICOLOR_FORCE, COLUMNS --
;;;; are portable, deterministic, and identical on every Lisp, so they are what
;;;; the test suite pins down. TTY probing is a best-effort second layer that
;;;; varies per implementation and ALWAYS degrades to NIL instead of erroring,
;;;; so :auto is safe to pass anywhere and a caller never has to guard it.

(defun %env-nonempty (name)
  "Return the value of environment variable NAME when set and non-empty, else NIL."
  (let ((value (uiop:getenv name)))
    (and value (plusp (length value)) value)))

(defun %positive-integer-or-nil (string)
  "Parse STRING to a positive integer, or NIL when it is not one."
  (let ((n (ignore-errors (parse-integer string :junk-allowed t))))
    (and (integerp n) (plusp n) n)))

(defun %resolve-output-stream (stream)
  "Follow synonym/two-way wrappers down to the concrete stream under STREAM.

*standard-output* and friends are usually SYNONYM-STREAMs that carry no file
descriptor of their own, so a naive isatty probe against them always fails; we
have to reach the FD-STREAM they point at first."
  (cond
    ((typep stream 'synonym-stream)
     (%resolve-output-stream (symbol-value (synonym-stream-symbol stream))))
    ((typep stream 'two-way-stream)
     (%resolve-output-stream (two-way-stream-output-stream stream)))
    (t stream)))

(defun %stream-tty-p (stream)
  "Best-effort test of whether STREAM is connected to a terminal.

Returns NIL -- never errors -- on implementations without an isatty binding, so
callers get a conservative \"assume not a terminal\" answer rather than a crash.
Only SBCL currently probes the real descriptor; elsewhere the environment rules
in %RESOLVE-HELP-COLOR remain the sole signal."
  (and (ignore-errors
         (let ((target (%resolve-output-stream stream)))
           (declare (ignorable target))
           #+sbcl (and (sb-sys:fd-stream-p target)
                       (plusp (sb-unix:unix-isatty (sb-sys:fd-stream-fd target))))
           #-sbcl nil))
       t))

(defun %resolve-help-color (color stream)
  "Resolve a :color argument (T, NIL, or :AUTO) to a concrete boolean.

:AUTO honors the de-facto conventions in precedence order: NO_COLOR wins over
everything (https://no-color.org), then CLICOLOR_FORCE (any value but \"0\")
forces color on even when piped, and finally we fall back to whether STREAM is
a terminal. Explicit T / NIL pass straight through so a caller can always force
the decision regardless of environment."
  (if (eq color :auto)
      (cond
        ((%env-nonempty "NO_COLOR") nil)
        ((let ((force (%env-nonempty "CLICOLOR_FORCE")))
           (and force (not (string= force "0"))))
         t)
        (t (%stream-tty-p stream)))
      (and color t)))

(defun %resolve-help-width (width stream)
  "Resolve a :width argument (positive integer, NIL, or :AUTO) to a width or NIL.

:AUTO reads $COLUMNS -- the value shells export and the portable proxy for
terminal width; when it is unset or invalid the result is NIL, meaning \"do not
wrap\", which matches the library's historical default. Explicit integers and
NIL pass through unchanged."
  (declare (ignorable stream))
  (if (eq width :auto)
      (let ((columns (%env-nonempty "COLUMNS")))
        (and columns (%positive-integer-or-nil columns)))
      width))
