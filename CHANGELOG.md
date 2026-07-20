# Changelog

All notable user-visible changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Dynamic (runtime) completion now works in all six generated shells. Previously
  only bash, zsh, and fish shelled out to the `__complete` callback for a
  `:complete` option; PowerShell, nushell, and elvish offered only a static
  candidate pool. PowerShell now inspects the token before the cursor, elvish
  branches on the previous word, and nushell attaches a per-flag custom
  completer — each invoking `app __complete KEY <partial>`. The generated
  scripts were verified against real `pwsh`, `nu`, and `elvish`.
- Terminal-aware help: `print-app-help`, `print-command-help`, and `run-app`
  now accept `:color :auto` and `:width :auto`. `:color :auto` honors `NO_COLOR`
  and `CLICOLOR_FORCE` and otherwise enables ANSI styling only when the target
  stream is a terminal (isatty on SBCL; environment-only elsewhere); `:width
  :auto` reads `$COLUMNS`. Explicit `t` / `nil` / integer values still force the
  decision, and the defaults remain `nil` so existing behavior is unchanged.
- `option-value-source` reports the provenance of an option value —
  `:command-line`, `:env`, `:config`, or `:default` (or `nil` when unset) — the
  analogue of clap's `ArgMatches::value_source`, so a handler can tell an
  explicit choice apart from a fallback. `invocation-option-sources` exposes the
  raw map.
- Required options are now spelled out in the one-line usage synopsis (for
  example `Usage: demo run [options] --config <FILE>`) instead of being hidden
  inside the `[options]` catch-all; non-required and hidden options stay in the
  catch-all.
- `run-app` accepts `:usage-exit-code` and `:error-exit-code` to override the
  exit codes returned for usage errors (default `64`, `EX_USAGE`) and other
  unhandled errors (default `70`, `EX_SOFTWARE`).
- Dynamic (runtime) completion: an option or positional may carry a `:complete`
  function `(lambda (partial) => candidates)`. Add `make-complete-command` (or
  `make-standard-commands :include-dynamic-p t`) and the generated bash, zsh, and
  fish completions call back into the program (`app __complete KEY PARTIAL`) at
  completion time to offer runtime candidates — no re-parsing of the command
  line. A candidate may be a plain value or a `(value . description)` cons
  (emitted tab-separated; fish shows the description). `render-complete-reply`
  exposes the same lookup directly, and `option-complete` reads the function.
- Bash, zsh, and fish completion now complete nested subcommands at every level
  of a command tree (`app remote <TAB>` offers `add` / `remove`), with each
  command's options — and its ancestors' — completing once that command is on
  the line. All three were verified by exercising the generated scripts under the
  real shells, not just syntax-checking them.
- The built-in `completion` and `docs` commands now carry
  `:completion-candidates`, so generated shell completion suggests the shell
  names (`demo completion <TAB>`) and documentation formats
  (`demo docs <TAB>`) while the parsers still accept aliases (`pwsh`, `nu`,
  `md`, `roff`).
- `:value-hint` (`:file` / `:dir`) on `make-option` (value-bearing) and
  `make-positional`: the generated bash, zsh, and fish completions offer file or
  directory path completion at the hinted slot (`compgen -f/-d`, `_files`/`_files -/`,
  the fish directory completer). Surfaced in help ("expects a file/directory")
  and JSON. Reader `option-value-hint`.
- Positional value completion: `make-positional` now accepts
  `:completion-candidates` (like options), and all six shell completers
  (bash, zsh, fish, powershell, nushell, elvish) offer a positional's
  `:choices` / `:completion-candidates` values at its argument slot. Positional
  candidates also appear in the JSON schema.
- Opt-in help description word-wrapping: `print-app-help`, `print-command-help`,
  and `run-app` accept `:width N` to word-wrap option/command/positional
  descriptions to column N, with continuation lines aligned under the
  description gutter. No terminal-width detection; off by default.
- `:auto-help` on `make-app` (default `t`): pass `nil` to suppress the built-in
  `-h` / `--help` flag for a CLI that manages its own help or forwards `--help`
  to a wrapped tool. A `help` command added via `make-standard-commands` is
  unaffected. Reader `app-auto-help`.
- Greedy variadic `:value-count` on a `:value` option: `:+` (one or more) and
  `:*` (zero or more) consume every following token up to the next option-like
  token (`--files a b c`), storing the list. `:+` requires at least one value.
  Help shows `<NAME>...` and JSON emits `"+"` / `"*"`.
- `:see-also`, `:authors`, and `:manual-date` on `make-app`: rendered as the SEE
  ALSO / AUTHORS sections and the `.TH` date of `render-manpage`, and exposed in
  `render-json` (the first two). `render-manpage` also emits standard EXIT STATUS
  (0 / 64 / 70) and ENVIRONMENT (env-backed options) sections, and the generated
  page passes `mandoc -T lint` cleanly. Readers `app-see-also`, `app-authors`,
  `app-manual-date`.
- `:required-if` / `:required-unless` on `make-option`: conditional
  requirements. `:required-if` makes an option mandatory when any listed option
  is present; `:required-unless` makes it mandatory unless any listed option is
  present. Both signal `cli-missing-option-value`, are hidden-target safe, and
  render in help. Readers `option-required-if`, `option-required-unless`.
- `:require-command` on `make-app`: parsing fails with `cli-unknown-command`
  (listing the available commands) unless a subcommand is dispatched, expressing
  a "subcommand mandatory" contract. Reader `app-require-command`.
- Invalid `:choices` values (for options and positionals) now append a
  nearest-match "Did you mean: ...?" suggestion to the error, reusing the same
  suggestion machinery as unknown options and commands.
- `:value-count N` on a `:value` option: consume exactly N following tokens as a
  parsed list (`--point 1 2` => `(1 2)`); too few remaining tokens signal
  `cli-missing-option-value`, and with `:multiple-p` each occurrence contributes
  its own N-element list. Reader `option-value-count`.
- `:kind :key-value`: each occurrence parses `key=value` (a bare `key` records
  value `t`) and accumulates the pairs into an alist, so `-D a=1 -D b=2` reads as
  `(("a" . "1") ("b" . "2"))` — the compiler-define / docker-env shape.
- `inclusive-group`: an all-or-none option group (if any member is supplied, all
  must be), the complement of `exclusive-group`; rendered as "all or none of" in
  help and signalling `cli-missing-dependent-option` on a partial set.
- `:allow-negative-numbers` on `make-app`: keeps a token that looks like a
  negative number (`-5`, `-1.5`) from being parsed as a short-option cluster, so
  it can serve as a positional or option value. Reader
  `app-allow-negative-numbers`.
- `:group` on `make-option`: a help-section label that groups related options
  under their own heading in help output (mirroring a command's `:group`) and is
  exposed in JSON. Reader `option-help-group`.
- Response-file expansion: `make-app :expand-response-files t` expands a `@path`
  argument into the whitespace-separated arguments read from that file before
  parsing (recursively; `@@` escapes a literal leading `@`; a missing file is a
  usage error), mirroring the gcc/clap convention. Reader
  `app-expand-response-files`.
- `:min-count` / `:max-count` on a rest `make-positional`: constrain how many
  values it collects (too few signals `cli-missing-positional`, too many
  `cli-unexpected-argument`); shown in help and JSON.
- `:default-command` on `make-command`: a command with `:subcommands` can name a
  default subcommand dispatched when no subcommand token is present, mirroring
  the app-level `:default-command`.
- Opt-in colored help: `print-app-help`, `print-command-help`, and `run-app`
  accept `:color t` to wrap headings and names in ANSI styling. There is no
  automatic terminal detection, so callers stay in control; off by default.
- Nested subcommands: `make-command` accepts `:subcommands` (a list of command
  specs), so a command dispatches like a mini-app (`git remote add`). The next
  non-option token selects a subcommand; the parent command's options stay
  available to the whole subtree and global counters accumulate across the path.
  Parsing, help (path-qualified usage plus a subcommand list), the man/Markdown/
  JSON renderers, and `run-app` dispatch all recurse to arbitrary depth. The new
  `invocation-command-path` accessor returns the full root-to-leaf chain.
- `:choices` on `make-positional`: restricts a positional to a closed set,
  validated before the parser runs (`cli-invalid-positional-value` on mismatch)
  and shown in help and JSON output, matching option `:choices`.
- `:help-footer` on `make-command`: trailing help/epilog prose for a command,
  mirroring the app-level `:help-footer` and falling back to it; reflected in the
  man/Markdown/JSON renderers. Reader `command-help-footer`.
- `:allow-abbreviated-options` on `make-app`: opt-in GNU-style unambiguous
  long-option prefix matching (`--verb` for `--verbose`); an ambiguous prefix
  signals `cli-unknown-option` listing the matches. Off by default to preserve
  strict exact-match parsing. Reader `app-allow-abbreviated-options`.
- `render-elvish-completion` and `elvish` support in `render-completion` and the
  `completion` command, bringing built-in completion coverage to six shells
  (bash, zsh, fish, powershell, nushell, elvish).
- `:config` on `parse-argv` and `run-app`: an optional plist of
  `option-key -> value` that supplies option defaults, slotting into the
  precedence chain below CLI arguments and environment variables but above a
  literal `:default`. Values are coerced like defaults (a string runs through
  the option parser, a list is spread, a delimited option splits a string), so a
  caller can layer in configuration loaded from a file without forking the
  parser.
- `:deprecated` on `make-option` and `make-command` (`t` or a reason string):
  the entity stays visible in help and completion but is annotated as deprecated
  in help, man, Markdown, and JSON output; dispatching a deprecated command
  makes `run-app` print a warning to stderr. Readers `option-deprecated` and
  `command-deprecated`.
- `:value-delimiter` on `make-option`: a single-character delimiter that makes a
  `:value` option split one occurrence into a list (`--tags a,b,c` =>
  `("a" "b" "c")`), parsing each piece (honoring `:type`) and accumulating across
  occurrences. Empty pieces are dropped, and string/list `:default`s and
  environment values are split the same way.
- `render-nushell-completion` and `nushell`/`nu` support in `render-completion`
  and the `completion` command: a Nushell module with an `export extern`
  covering subcommands and global option flags.
- `render-json`: emits the app's declared spec (options, positionals, commands,
  types, ranges, delimiters, defaults) as a machine-readable JSON object for
  external tooling. Also available as the `json` format of the `docs` command.
- Typed values on `make-option` and `make-positional`: `:type` selects a
  built-in value parser (`:integer`, `:number`, `:float`, `:boolean`, or the
  default `:string`), and `:min`/`:max` add inclusive bounds for numeric types.
  This replaces most hand-written `:parser` lambdas for common domain
  validation. The chosen type and range appear in help metadata, and both
  are validated at `make-*` time (`:type` and `:parser` are mutually exclusive,
  bounds require a numeric type, and `:min` must not exceed `:max`). Numeric
  parsing binds `*read-eval*` off so a value can never execute reader code.
- `:kind :count` on `make-option`: a repeatable counter option where each
  occurrence increments an integer (`-vvv` => 3, or a repeated `--verbose`),
  defaulting to 0. Ideal for verbosity flags.
- `render-manpage`: generates a section-1 man page (roff) from an app spec,
  covering NAME, SYNOPSIS, DESCRIPTION, OPTIONS, ARGUMENTS, COMMANDS, and
  EXAMPLES, and honoring hidden options/commands.
- `render-markdown`: generates GitHub-flavored Markdown reference documentation
  (title, usage block, option/argument tables, per-command sections, examples).
- `make-docs-command` and `render-docs`: a built-in `docs [FORMAT]` command
  (parallel to `completion [SHELL]`) that prints the generated man page or
  Markdown to stdout; `make-standard-commands` gains `:include-docs-p`.
- `render-powershell-completion` and `powershell`/`pwsh` support in
  `render-completion` and the `completion` command: a
  `Register-ArgumentCompleter -Native` script that offers subcommands and
  option tokens, narrowing to a subcommand's own options once it appears.
- Option readers `option-value-type`, `option-value-min`, and `option-value-max`
  for the new typed-value metadata.
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

- Fish completion never offered top-level command names: they were emitted with
  a `__fish_seen_subcommand_from <command>` guard (true only *after* the command
  was typed) instead of `__fish_use_subcommand`, so `app <TAB>` completed
  nothing. Confirmed and fixed via behavioral `fish -c 'complete -C ...'` testing
  (syntax-only checks could not catch it).
- Generated bash completion never completed a separated option value
  (`--mode <TAB>`): the `case "$prev"` scan set `expect_value` / `value_source`
  but nothing turned them into `COMPREPLY`. The completer now consumes them and
  uses `_init_completion -s` so an attached value (`--mode=<TAB>`) completes
  through the same path. Verified against the real `bash-completion` library.
- Fish completion offered file paths alongside an option's closed `:choices`
  value set; choice/candidate value options are now `-f` (exclusive) so only the
  declared values are suggested.
- An option's `:value-hint` never drove shell completion (only positionals did):
  bash now completes files for a plain / `:file`-hint value option (via
  `complete -o default`) and directories for a `:dir` hint (`compgen -d`), fish
  completes directories for a `:dir`-hint option, and zsh completes files/dirs
  for a `:file` / `:dir`-hint option (`_files` / `_files -/`).
- Generated bash completion never completed a subcommand's options: the root
  `-*` fallback returned the global options and stopped before any command case
  ran, and the first-word command completion pre-empted `app -<TAB>`. Both are
  now guarded, so subcommand (and nested-subcommand) option completion works.
  Found via behavioral testing (sourcing the script and inspecting `COMPREPLY`).
- Generated bash completion emitted an empty `case` label (a bash syntax error)
  for a `:value` option that had no `:choices` / `:completion-candidates`; such
  an option now falls through to the shell's default file completion. The bash,
  zsh, and fish generators are now checked with real `bash -n` / `zsh -n` /
  `fish --no-execute` in the test suite's manual verification.
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
