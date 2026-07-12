# Contributing to cl-cli

## Scope

Contributions should keep `cl-cli` dependency-light, predictable, and suitable
for consumer CLIs that need strict parsing behavior.

Prefer changes that:

- preserve or improve existing parsing semantics
- extend help/completion output from the same spec metadata
- keep public API additions small and composable
- include focused tests for every behavior change

Avoid changes that:

- introduce new runtime dependencies without a strong reason
- add parser ambiguity for convenience-only shorthand
- duplicate validation logic across parser, help, and completion layers

## Development setup

With Nix:

```bash
nix develop
```

Without Nix, install SBCL and load the system through ASDF or Quicklisp.

## Validation

Run the full verification path before opening a change:

```bash
sbcl --non-interactive --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)' --quit
ecl --norc --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)'
nix flake check
```

When adding or changing parser behavior:

- add or update a focused test in `tests/run-tests.lisp`
- cover both the success path and the expected failure mode when relevant
- update `README.md` if the user-visible surface changed

## Change guidelines

- Keep public exports intentional. Add new exports only when they are reusable
  outside one local consumer.
- Preserve constructor fail-fast behavior for invalid specs.
- Reuse shared normalization helpers instead of re-implementing string or list
  validation in multiple places.
- Keep comments rare and only use them where the code is otherwise hard to
  parse.

## Pull requests

A good change includes:

- a clear problem statement
- the smallest coherent implementation
- verification notes with the commands you ran
- documentation updates when the CLI surface changed

If a change is intentionally incomplete, state the remaining work explicitly.
