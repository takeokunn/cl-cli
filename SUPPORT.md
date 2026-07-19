# Support

## Usage questions

Use the GitHub issue tracker for questions about:

- modeling a CLI with `make-app`, `make-command`, or `make-option`
- migration from an existing in-house parser
- help, completion, or runtime argv integration
- expected strictness for parsing and validation behavior

When asking for help, include:

- the `cl-cli` version or commit you are using
- a minimal app spec
- the argv input that failed
- the observed output or condition
- the behavior you expected

## Bug reports

Open a GitHub issue when you can reproduce a library defect. A good report
includes:

- a minimal reproduction
- the exact implementation used, such as `sbcl` or `ecl`
- whether the bug is parser behavior, help rendering, completion rendering, or runtime argv handling
- the smallest failing test you would expect in `tests/`

## Security issues

Do not use public issues for suspected vulnerabilities. Follow
[SECURITY.md](SECURITY.md).

## Maintenance expectations

This repository currently treats the default branch as the supported line.
Compatibility guarantees should be documented in `CHANGELOG.md` when tagged
releases start.
