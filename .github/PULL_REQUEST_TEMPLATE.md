## Problem

What user-visible behavior or internal gap does this change address?

## Changes

The smallest coherent implementation; call out any public API additions.

## Verification

Commands run and their results (see CONTRIBUTING.md):

```bash
sbcl --non-interactive --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)' --quit
ecl --norc --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)'
nix flake check
```

## Documentation

- [ ] README.md updated if the user-visible surface changed
- [ ] CHANGELOG.md updated for user-visible changes
- [ ] New behavior covered by focused tests
