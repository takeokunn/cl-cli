# Changelog

All notable user-visible changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `:requires-any-of` on `make-option`: declares that at least one of a set of
  alternative options must also be supplied (unlike `:requires`, which demands
  all of them). Signals the new `cli-missing-any-of-options` condition and
  renders as `requires one of: ...` in help. `make-app` rejects a
  `:requires-any-of` whose every alternative conflicts with the option itself,
  since such an option could never be validly supplied.
- Contributor, support, and release-process documentation.

### Changed

- Completion renderers (`render-completion`, `render-bash-completion`,
  `render-zsh-completion`, `render-fish-completion`) now return the generated
  script as a string when called without a stream, mirroring the `format`
  destination contract; passing a stream still writes to it and returns no
  values. Previously the no-stream form wrote to `*standard-output*` and
  returned no values, so there was no way to obtain the script as a string
  through the public API.
- Expanded package metadata for ASDF consumers and package indexes.
- Documented the `cl-prolog` git-dependency install path, since `cl-cli` is not
  yet resolvable through a bare Quicklisp `quickload`.
- Option `:requires`/`:conflicts-with` validation now reuses the Prolog
  rulebase built once at `make-app` time instead of rebuilding and re-querying
  it on every `parse-argv` call.

### Fixed

- Bash completion never offered attached-value candidates (`--option=value`)
  for command-scoped options.
- A short-option cluster silently dropped characters that followed a
  mid-cluster `:stop-parsing-p` flag or boolean instead of surfacing them as
  positional input.
- An `:optional-value` option configured with `:consume-optional-value-p t`
  could not accept a separated bare `-` (the stdin/stdout idiom) as its value.
- `make-app` no longer accepts a positional sequence with a required positional
  after an optional one, since such a spec could never assign the later
  positional correctly.
- `make-app` now rejects two options whose keys collide (e.g. case-differing
  single-character names like `-a`/`-A`) instead of letting them silently share
  one storage slot.
- `make-app` now rejects a user-declared option that reuses the reserved
  `:help`/`:version` key, which previously could hijack CLI dispatch into the
  help/version action.
- `extract-application-argv`/`application-argv` no longer strip a literal
  application argument that happens to match a runtime marker when it appears
  after the `--` separator.
- `make-option`/`make-positional` now validate identifier safety before
  interning the option/positional key, instead of after.
- A relation rulebase cached on a shared, reused `command-spec` (per the
  library's own "reusable command spec" pattern) could be silently overwritten
  by a second, unrelated `make-app` call that spliced in the same command
  object, corrupting validation for the first app. The cache now lives per-app,
  keyed by command object, instead of being stored on the shared command
  struct.
- Corrected broken absolute-path documentation links and gave `SECURITY.md` a
  concrete private vulnerability-reporting path.

[Unreleased]: https://github.com/takeokunn/cl-cli/commits/main
