# cl-cli

`cl-cli` is a small, dependency-light Common Lisp CLI toolkit for building:

- strict flag and option parsers
- subcommand-based tools
- root/default command entry points
- positional and rest-argument parsers
- help/version handling
- reusable app, command, option, and positional specs

It is intentionally conservative about dependencies so it works well in
minimal Common Lisp and Nix environments.

## Installation

With Quicklisp / ASDF:

```lisp
(ql:quickload :cl-cli)
```

With Nix:

```bash
nix develop
```

The repository includes Nix checks for both `sbcl` and `ecl`, so
`nix flake check` verifies the current test suite across multiple Common Lisp
implementations.

## Quick example

```lisp
(ql:quickload :cl-cli)

(defparameter *app*
  (cl-cli:make-app
   :name "demo"
   :version "0.1.0"
   :global-options (list (cl-cli:make-option :name "verbose" :short #\v :kind :flag))
   :commands (list
              (cl-cli:make-command
               :name "compile"
               :options (list (cl-cli:make-option :name "output" :short #\o :kind :value))
               :positionals (list (cl-cli:make-positional :key :input :required-p t))
               :handler (lambda (invocation)
                           (format t "compile ~A -> ~A~%"
                                   (cl-cli:positional-value invocation :input)
                                   (cl-cli:option-value invocation :output)))))))

(cl-cli:run-app *app* '("demo" "compile" "-o" "out.bin" "input.lisp"))
```

## Root positional example

```lisp
(defparameter *script-app*
  (cl-cli:make-app
   :name "script-runner"
   :positionals (list (cl-cli:make-positional :key :script :required-p nil)
                      (cl-cli:make-positional :key :script-args :rest-p t))
   :handler (lambda (invocation)
              (format t "script=~S args=~S~%"
                      (cl-cli:positional-value invocation :script)
                      (cl-cli:positional-value invocation :script-args)))))
```

Supported option kinds are `:flag`, `:boolean`, `:value`, and `:optional-value`.
The built-in help/version flags are `--help`, `-h`, `--version`, and `-V`.
`--version` / `-V` are available only when the app declares a version string.
Optional values accept bare and attached forms by default, such as
`--coverage` and `--coverage=mcdc`. Use `:consume-optional-value-p t` when a
CLI must also accept a separated non-option value such as `--coverage true`.
Boolean options accept positive and auto-generated negated long forms. For
example, `:name "threads"` supports both `--threads` and `--no-threads`.
Command and global options may also appear after command positionals when a
consumer CLI expects interspersed arguments, such as
`demo compile input.lisp --output out.fasl --verbose`.
Options may also source their default from environment variables with
`:env-var` or `:env-vars`; precedence is `CLI argument > environment variable >
literal :default`.
Help output can surface that metadata directly, including `:required-p`,
`:default`, `:env-var` / `:env-vars`, enumerated `:choices`, and option
relationships via `:requires` / `:conflicts-with`.
Value-bearing options can also be made repeatable with `:multiple-p t`; repeated
occurrences accumulate in input order and `option-value` returns a list.

```lisp
(cl-cli:make-option :name "threads"
                    :short #\t
                    :kind :boolean
                    :env-var "APP_THREADS")
```

Repeatable value options are useful for include paths, module filters, and
similar consumer CLI shapes:

```lisp
(cl-cli:make-option :name "include"
                    :short #\I
                    :kind :value
                    :multiple-p t
                    :default '("src"))
```

Help output is context-sensitive:

- command help includes an `[options]` usage token when the command or app has options
- subcommand apps render dispatch-oriented usage such as
  `Usage: demo [global-options] <command> [args]`
- app and command specs can expose curated `:examples` lines directly in help
- command aliases are shown in the command list
- command lists can be grouped with `:group` for large subcommand surfaces
- option relationships can enforce `:requires` and `:conflicts-with`
- invalid app specs fail fast during `make-app`, not only during parsing
- spec constructors reject empty strings for user-facing identifiers such as
  names, aliases, value names, env vars, choices, completion candidates,
  groups, and examples
- unknown commands and options suggest the nearest known spelling when the typo is close enough
- `--version` is only shown in help when the app has a version string

Use `:stop-parsing-p t` for options such as shell `-c COMMAND [ARGS...]`
where the option consumes one value and every following token, including
flag-like tokens, must remain positional arguments:

```lisp
(cl-cli:make-option :name "command"
                    :short #\c
                    :kind :value
                    :stop-parsing-p t)
```

Environment-backed defaults are useful for consumer CLIs that already carry
runtime configuration in the process environment:

```lisp
(cl-cli:make-option :name "profile"
                    :kind :value
                    :env-var "APP_PROFILE"
                    :default "dev")
```

When an option accepts a closed set of CLI values, declare them once and let
both parsing and help output share the same source of truth:

```lisp
(cl-cli:make-option :name "mode"
                    :kind :value
                    :choices '("dev" "prod")
                    :description "Execution mode.")
```

When a CLI accepts free-form values but shell completion should still suggest a
curated set, keep validation open and attach `:completion-candidates`
separately. Candidates may be plain values or `(value . description)` pairs:

```lisp
(cl-cli:make-option :name "profile"
                    :kind :value
                    :completion-candidates '(("dev" . "Local development")
                                             ("prod" . "Production release"))
                    :description "Runtime profile.")
```

For modern CLIs that need cross-option validation, declare option
relationships directly in the option spec so parsing and help stay aligned:

```lisp
(list
 (cl-cli:make-option :name "profile"
                     :kind :value)
 (cl-cli:make-option :name "config"
                     :kind :value
                     :requires '(:profile)
                     :description "Config file.")
 (cl-cli:make-option :name "token"
                     :kind :value)
 (cl-cli:make-option :name "password"
                     :kind :value
                     :conflicts-with '("token")))
```

Relation targets may be written either as option keys such as `:profile` or as
names such as `"profile"` / `"--profile"`. They are evaluated after CLI values,
environment defaults, and literal defaults are resolved.
When a relation target points at a hidden option, parsing still honors the
relation but generated help omits that hidden target from public metadata, and
runtime relationship errors avoid printing the hidden option name.

For larger CLIs, group related commands in app help without changing parsing:

```lisp
(list
 (cl-cli:make-command :name "compile"
                      :group "Build"
                      :description "Compile sources.")
 (cl-cli:make-command :name "test"
                      :group "Build"
                      :description "Run tests.")
 (cl-cli:make-command :name "doctor"
                      :group "Diagnostics"
                      :description "Inspect the environment."))
```

When help text should stay aligned with README snippets or a manpage, attach
examples to the app or command spec and let the generated help reuse them:

```lisp
(cl-cli:make-app
 :name "demo"
 :examples '("demo compile src/main.lisp"
             "demo test --filter smoke")
 :commands
 (list
  (cl-cli:make-command
   :name "compile"
   :examples '("demo compile -o out.fasl src/main.lisp"))))
```

`cl-cli:command-by-name` resolves both primary command names and aliases
case-insensitively, which is useful when custom commands need to reuse the
same lookup semantics as the built-in help command.

For script-style options such as `--script FILE [ARGS...] [-- ...]`, keep the
opaque tail in a rest positional and normalize away a literal separator token
only when the downstream script runner should not see it:

```lisp
(let* ((app (cl-cli:make-app
             :name "cl-cc"
             :global-options
             (list (cl-cli:make-option :name "script"
                                       :kind :value
                                       :stop-parsing-p t))
             :positionals
             (list (cl-cli:make-positional :key :script-argv :rest-p t))))
       (invocation
        (cl-cli:parse-argv app
                           '("cl-cc" "--script" "ci/build.lisp"
                             "--" "--target" "release"))))
  (values
   (cl-cli:option-value invocation :script)
   (cl-cli:strip-argv-separators
    (cl-cli:positional-value invocation :script-argv))))
```

Value-bearing short options also accept attached forms. This covers CLI shapes
such as `-Lmain` or `-S/tmp/tmux.sock` without special-case parsing:

```lisp
(let* ((app (cl-cli:make-app
             :name "cl-tmux"
             :global-options
             (list (cl-cli:make-option :name "socket"
                                       :short #\S
                                       :kind :value))))
       (invocation
        (cl-cli:parse-argv app '("cl-tmux" "-S/tmp/tmux.sock"))))
  (cl-cli:option-value invocation :socket))
;; => "/tmp/tmux.sock"
```

Use `application-argv` when a launcher such as SBCL or Nix inserts runtime
tokens before the real CLI arguments. It applies the library's default SBCL/Nix
runtime markers:

```lisp
(cl-cli:application-argv
 :argv (cl-cli:current-process-argv))

(cl-cli:application-argv
 :argv (cl-cli:current-process-argv)
 :separator "--")
```

Use `extract-application-argv` directly when a consumer needs fully custom
runtime markers:

```lisp
(cl-cli:extract-application-argv
 :argv (cl-cli:current-process-argv)
 :runtime-markers '("--no-userinit" "--end-toplevel-options"))
```

## Migration guide

`cl-cli` already covers the shared parser shapes used by the current in-house
CLIs it is intended to replace. The practical question is not "can it parse
options?" but "which API reproduces each existing command surface without local
parser forks?".

### `cl-cc`

`cl-cc` needs a mix of ordinary subcommands and script-style execution:

- `compile`-style commands with `--flag`, `--key value`, `--key=value`, and `-o value`
- command dispatch on the first non-option token
- `--script FILE [ARGS...] [-- ...]` where everything after the script path stays opaque
- value kinds matching `:boolean`, `:value`, and `:optional-value`

Use these `cl-cli` features:

- `make-command` for first-token subcommand dispatch
- `make-option` with `:kind :flag`, `:kind :boolean`, `:kind :value`, and `:kind :optional-value`
- `:stop-parsing-p t` on `--script` to preserve the opaque tail
- `strip-argv-separators` when the downstream script runner should not receive a literal `--`

Existing coverage:

- script tail preservation and separator normalization are exercised in `stop-parsing-option-preserves-remaining-arguments`, `stop-parsing-short-attached-value`, and `stop-parsing-script-mode-can-normalize-opaque-tail` in [tests/run-tests.lisp](/Users/take/ghq/github.com/takeokunn/cl-cli/tests/run-tests.lisp)

### `cl-tmux`

`cl-tmux` needs launcher-aware argv handling and tmux-style attached short
values:

- runtime token stripping before application parsing
- attached short payloads such as `-Lmain` and `-S/tmp/tmux.sock`
- modes that forward the remaining argv tail verbatim
- root execution when no explicit subcommand token is present

Use these `cl-cli` features:

- `application-argv` or `extract-application-argv` before `run-app`
- short value options with `:short` plus `:kind :value`
- `:stop-parsing-p t` when a mode must forward the remaining tail unchanged
- root `:handler` or `:default-command` for no-subcommand entry points

Existing coverage:

- attached short value parsing is shown in the `-S/tmp/tmux.sock` example above
- root/default dispatch is exercised in `default-command-dispatches-without-command-token` in [tests/run-tests.lisp](/Users/take/ghq/github.com/takeokunn/cl-cli/tests/run-tests.lisp)

### `private-trade-fx`

`private-trade-fx` needs a stricter "single binary" interface:

- flat value options without subcommand routing
- hard failures for unknown options and missing required values
- built-in `--help`
- preservation of arguments after `--`
- option-local parsers for domain validation such as positive integers

Use these `cl-cli` features:

- app-level `:global-options` without defining commands
- the default strict parser behavior for unknown and malformed input
- built-in help/version handling
- `strip-argv-separators` only when downstream logic should hide the separator
- `:parser` on options and positionals for domain-specific validation

Existing coverage:

- parser-hook validation is demonstrated in the positive-integer example below
- separator-preserving and separator-normalizing flows are covered in [tests/run-tests.lisp](/Users/take/ghq/github.com/takeokunn/cl-cli/tests/run-tests.lisp)

### `nshell`

`nshell` needs a shell-like root entry point with a few special launch modes:

- root execution with no args
- built-in `--help`, `-h`, `--version`, and `-V`
- `-c COMMAND [ARGS...]`
- a leading script file followed by rest arguments

Use these `cl-cli` features:

- app-level `:handler` for the zero-arg root path
- built-in help/version flags
- `:stop-parsing-p t` on `-c`
- root positionals with a trailing `:rest-p t` positional for script argv

Existing coverage:

- root positional parsing is shown in the `script-runner` example above
- root/default dispatch behavior is covered in [tests/run-tests.lisp](/Users/take/ghq/github.com/takeokunn/cl-cli/tests/run-tests.lisp)

### Verification path

For the four target CLIs above, the remaining migration work is consumer-side
spec translation, not new parser primitives in `cl-cli`.

- representative specs for all four migration targets live in [examples/consumer-migrations.lisp](/Users/take/ghq/github.com/takeokunn/cl-cli/examples/consumer-migrations.lisp)
- load the system with ASDF
- run [tests/run-tests.lisp](/Users/take/ghq/github.com/takeokunn/cl-cli/tests/run-tests.lisp)
- if you launch through SBCL, Nix, or a wrapper script, normalize argv first with `application-argv`

## Validation and exit codes

Option and positional parsers are the right place for domain validation:

```lisp
(cl-cli:make-option
 :name "count"
 :kind :value
 :parser (lambda (value)
           (let ((number (parse-integer value)))
             (unless (plusp number)
               (error "Expected a positive integer."))
             number)))
```

Parser failures are reported as `cl-cli:cli-invalid-option-value` or
`cl-cli:cli-invalid-positional-value`, so `run-app` treats them as usage errors
instead of internal failures. Command handlers may return an integer to choose
the process exit code.

Handlers can write through the invocation streams when `run-app` is used:

```lisp
(lambda (invocation)
  (format (cl-cli:invocation-stdout invocation) "ok~%")
  0)
```

## Shell completion

Generate a static completion script directly from the app definition:

```lisp
(write-string
 (cl-cli:render-completion *app* "bash")
 *standard-output*)
```

Shell-specific renderers are also available:

```lisp
(cl-cli:render-bash-completion *app*)
(cl-cli:render-zsh-completion *app*)
(cl-cli:render-fish-completion *app*)
```

If you want standard built-in subcommands, use
`cl-cli:make-standard-commands`. It returns `help` and `version` by default;
when the app omits a version string, `version` prints just the app name.
Set `:include-completion-p t` to add `completion` too:

```lisp
(setf *app*
      (cl-cli:make-app
       :name "demo"
       :commands (append
                  (cl-cli:make-standard-commands
                   :include-completion-p t)
                  (list ...))))
```

Then users can install completion with:

```bash
eval "$($(command -v demo) completion bash)"
```

For Zsh and Fish:

```bash
autoload -U compinit && compinit
source <($(command -v demo) completion zsh)

source <($(command -v demo) completion fish)
```

Current built-in support is `bash`, `zsh`, and `fish`. Hidden commands and
hidden options are omitted from the generated script. Aliases are included in
generated completion candidates. Options declared with `:choices` also feed
shell value completion candidates. Use `:completion-candidates` when shell
suggestions should be broader or differently documented than parser validation.

## Command shapes

Use `:default-command` when a subcommand app should dispatch a command even
without an explicit command token. Use root `:positionals` plus a root
`:handler` for script-style CLIs such as `SCRIPT [ARGS...]`.

## Test

```bash
sbcl --non-interactive --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)' --quit
ecl --norc --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)'
nix flake check
```

## Contributing

Development workflow, change expectations, and verification requirements are
documented in [CONTRIBUTING.md](/Users/take/ghq/github.com/takeokunn/cl-cli/CONTRIBUTING.md).

## Support

Usage questions, bug-report expectations, and maintainer support boundaries are
documented in [SUPPORT.md](/Users/take/ghq/github.com/takeokunn/cl-cli/SUPPORT.md).

## Changelog

User-visible release notes are tracked in
[CHANGELOG.md](/Users/take/ghq/github.com/takeokunn/cl-cli/CHANGELOG.md).

## Releasing

The maintainer release checklist is documented in
[RELEASING.md](/Users/take/ghq/github.com/takeokunn/cl-cli/RELEASING.md).

## Security

Private vulnerability handling expectations are documented in
[SECURITY.md](/Users/take/ghq/github.com/takeokunn/cl-cli/SECURITY.md).

## License

MIT
