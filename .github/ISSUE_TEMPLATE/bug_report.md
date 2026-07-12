---
name: Bug report
about: Report incorrect parsing, help, completion, or runtime behavior
title: ""
labels: bug
assignees: ""
---

## Summary

A clear description of the incorrect behavior.

## Reproduction

A minimal spec plus argv that reproduces the problem:

```lisp
(let ((app (cl-cli:make-app :name "demo" ...)))
  (cl-cli:parse-argv app '("demo" ...)))
```

## Expected behavior

What you expected `cl-cli` to do.

## Actual behavior

What actually happened, including the full condition/error message if any.

## Environment

- cl-cli version or commit:
- Common Lisp implementation and version (e.g., SBCL 2.4.x, ECL 24.5):
- OS:
