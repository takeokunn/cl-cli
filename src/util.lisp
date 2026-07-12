(in-package :cl-cli)

(defun public-option-display-name (spec)
  (if (option-hidden-p spec)
      "a hidden option"
      (%option-display-name spec)))
