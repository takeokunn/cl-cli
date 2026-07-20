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

`cl-cli` depends on [`cl-prolog`](https://github.com/takeokunn/cl-prolog), which
is **not in Quicklisp**, so a bare `(ql:quickload :cl-cli)` will not resolve on
its own. Choose one of the paths below.

### With Nix (recommended)

The flake wires up `cl-prolog` and `cl-weave` for you:

```bash
nix develop        # drop into a shell with all dependencies available
nix flake check    # run the test suite across sbcl and ecl
```

### With ASDF / Quicklisp

Clone `cl-cli` and its `cl-prolog` dependency where ASDF can find them (for
example under `~/common-lisp/` or `~/quicklisp/local-projects/`), then load it.
Once the dependency is registered, Quicklisp resolves the remaining `uiop`
dependency automatically:

```bash
git clone https://github.com/takeokunn/cl-prolog  ~/common-lisp/cl-prolog
git clone https://github.com/takeokunn/cl-cli     ~/common-lisp/cl-cli
```

```lisp
(ql:quickload :cl-cli)
```

Running the test suite additionally requires
[`cl-weave`](https://github.com/takeokunn/cl-weave) checked out the same way.

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

Supported option kinds are `:flag`, `:boolean`, `:value`, `:optional-value`,
`:count`, and `:key-value`. A `:key-value` option parses each occurrence as
`key=value` (a bare `key` records value `t`) and accumulates the pairs into an
alist, matching the compiler-define / container-env shape:

```lisp
(cl-cli:make-option :name "define" :short #\D :kind :key-value)
;; -D a=1 -D b=2  =>  (("a" . "1") ("b" . "2"))
```

A `:count` option is a repeatable counter: each occurrence increments
an integer and it defaults to `0`, so `-vvv` (or a repeated `--verbose`) yields
`3`. This is the conventional shape for verbosity flags:

```lisp
(cl-cli:make-option :name "verbose" :short #\v :kind :count
                    :description "Increase verbosity.")
```

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
`:env-var` or `:env-vars`, and callers may layer in values loaded from a config
file by passing a `:config` plist to `parse-argv` / `run-app`. The full
precedence is `CLI argument > environment variable > :config > literal
:default`:

```lisp
(cl-cli:run-app *app*
                :argv (cl-cli:current-process-argv)
                :config '(:profile "prod" :threads 8))
```

The config plist is keyed by option key, and its values are coerced exactly like
a literal `:default` (a string is parsed through the option's `:type`/`:parser`,
a list is spread across a repeatable option, and a delimited option splits a
string value).
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

A `:value` option can also split a single occurrence into a list with
`:value-delimiter` (a single character), so `--tags a,b,c` yields
`("a" "b" "c")`. Each piece is parsed (honoring `:type`) and repeated
occurrences keep accumulating; a string or list `:default` and an environment
value are split the same way:

```lisp
(cl-cli:make-option :name "tags"
                    :kind :value
                    :value-delimiter #\,
                    :default '("core"))
```

A `:value` option can consume a fixed number of separate tokens with
`:value-count N`, returning a parsed list (`--point 1 2` => `(1 2)`); with
`:multiple-p` each occurrence contributes its own N-element list:

```lisp
(cl-cli:make-option :name "point" :kind :value :type :integer :value-count 2)
```

`:value-count` may also be `:+` (one or more) or `:*` (zero or more), which
greedily consume following tokens up to the next option-like token
(`--files a b c`); help shows the value as `<NAME>...`:

```lisp
(cl-cli:make-option :name "files" :kind :value :value-count :+)
```

Help output is context-sensitive:

- command help includes an `[options]` usage token when the command or app has options
- subcommand apps render dispatch-oriented usage such as
  `Usage: demo [global-options] <command> [args]`
- app and command specs can expose curated `:examples` lines directly in help
- command aliases are shown in the command list
- options and commands can be marked `:deprecated` (with an optional reason
  string); they stay usable and visible but are annotated as deprecated in help
  and generated docs, and a deprecated command prints a stderr warning when run
- command lists can be grouped with `:group` for large subcommand surfaces
- option relationships can enforce `:requires` and `:conflicts-with`
- mutually-exclusive option sets can be declared with `exclusive-group`, or
  `required-exclusive-group` for an "exactly one of" obligation
- invalid app specs fail fast during `make-app`, not only during parsing
- spec constructors reject empty strings for user-facing identifiers such as
  names, aliases, value names, env vars, choices, completion candidates,
  groups, and examples
- app, command, and option names are restricted to safe identifier characters
  (letters, digits, `-`, `_`, `.`), so author- or config-supplied names cannot
  inject shell syntax into generated completion scripts
- a required positional may not follow an optional one, and two options may
  not resolve to the same key (e.g. via case-differing single-character
  names), since either would silently misassign or overwrite parsed values
- an option may not reuse the reserved `:help`/`:version` key
- unknown commands and options — and invalid `:choices` values — suggest the nearest known spelling when the typo is close enough
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

Positionals accept `:choices` too, validated the same way (mismatches signal
`cli-invalid-positional-value`) and surfaced in help and JSON output:

```lisp
(cl-cli:make-positional :key :env
                        :required-p t
                        :choices '("dev" "prod"))
```

For file-path arguments, attach `:value-hint :file` or `:value-hint :dir` to an
option or positional; the generated bash, zsh, and fish completions then offer
file or directory completion at that slot (and it is shown in help and JSON):

```lisp
(cl-cli:make-option :name "config" :kind :value :value-hint :file)
(cl-cli:make-positional :key :dir :value-hint :dir)
```

A rest positional (`:rest-p t`) can also bound how many values it collects with
`:min-count` / `:max-count` (too few signals `cli-missing-positional`, too many
`cli-unexpected-argument`):

```lisp
(cl-cli:make-positional :key :files :rest-p t :min-count 1 :max-count 8)
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

`:requires` demands every listed target; when only one of several alternatives
must be present (such as authenticating with a token *or* a username and
password), declare `:requires-any-of` instead:

```lisp
(cl-cli:make-option :name "login"
                    :kind :flag
                    :requires-any-of '(:token :username))
```

Parsing signals `cli-missing-any-of-options` when none of the declared
alternatives are supplied, and help lists them as `requires one of: --token,
--username`.

For requirements that depend on *other* options, use `:required-if` (the option
becomes mandatory when any listed option is present) or `:required-unless` (it
is mandatory unless any listed option is present). Both signal
`cli-missing-option-value` and render in help as `required if: ...` /
`required unless: ...`:

```lisp
(list
 (cl-cli:make-option :name "profile" :kind :value)
 (cl-cli:make-option :name "config" :kind :value :required-if '(:profile))
 (cl-cli:make-option :name "token" :kind :value)
 (cl-cli:make-option :name "user" :kind :value :required-unless '(:token)))
```

To make a set of options mutually exclusive (at most one may be supplied),
splice them through `cl-cli:exclusive-group` instead of hand-writing every
pairwise `:conflicts-with`. Each member gains the others as conflicts, so
exclusivity reuses the same validation and hidden-target-safe error messages:

```lisp
:global-options (cl-cli:exclusive-group
                 (cl-cli:make-option :name "json" :kind :flag)
                 (cl-cli:make-option :name "yaml" :kind :flag)
                 (cl-cli:make-option :name "table" :kind :flag))
```

Conflicts an option already declares are preserved, so a group member can still
conflict with options outside the group.

When the choice is mandatory, use `cl-cli:required-exclusive-group` instead:
exclusivity is enforced as above, and parsing additionally fails with
`Exactly one of ...` when none of the members is supplied — expressing an
"exactly one of" obligation that pairwise `:conflicts-with` cannot.

For the opposite relationship — options meant to be used *together*, such as a
paired `--host` and `--port` — splice them through `cl-cli:inclusive-group`. If
any member is supplied, all must be (supplying none is fine); a partial set
signals `cli-missing-dependent-option` and help renders the members as
"all or none of":

```lisp
:global-options (cl-cli:inclusive-group
                 (cl-cli:make-option :name "host" :kind :value)
                 (cl-cli:make-option :name "port" :kind :value))
```

Options accept a `:group` label too, which sections them under their own heading
in help (and appears in JSON), mirroring command grouping:

```lisp
(list
 (cl-cli:make-option :name "output" :kind :value :group "Output")
 (cl-cli:make-option :name "format" :kind :value :group "Output")
 (cl-cli:make-option :name "token" :kind :value :group "Auth"))
```

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

- script tail preservation and separator normalization are exercised in `stop-parsing-option-preserves-remaining-arguments`, `stop-parsing-short-attached-value`, and `stop-parsing-script-mode-can-normalize-opaque-tail` in [tests/run-tests.lisp](tests/run-tests.lisp)

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
- root/default dispatch is exercised in `default-command-dispatches-without-command-token` in [tests/run-tests.lisp](tests/run-tests.lisp)

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
- separator-preserving and separator-normalizing flows are covered in [tests/run-tests.lisp](tests/run-tests.lisp)

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
- root/default dispatch behavior is covered in [tests/run-tests.lisp](tests/run-tests.lisp)

### Verification path

For the four target CLIs above, the remaining migration work is consumer-side
spec translation, not new parser primitives in `cl-cli`.

- representative specs for all four migration targets live in [examples/consumer-migrations.lisp](examples/consumer-migrations.lisp)
- load the system with ASDF
- run [tests/run-tests.lisp](tests/run-tests.lisp)
- if you launch through SBCL, Nix, or a wrapper script, normalize argv first with `application-argv`

## Typed values

For the common case of numeric or boolean domain validation, declare a `:type`
instead of writing a `:parser` lambda. Supported types are `:integer`,
`:number`, `:float`, `:boolean`, and the default `:string`; `:min` and `:max`
add inclusive bounds for numeric types. Both `make-option` and `make-positional`
accept them:

```lisp
(cl-cli:make-option :name "jobs"
                    :kind :value
                    :type :integer
                    :min 1
                    :max 64
                    :description "Parallel job count.")

(cl-cli:make-positional :key :port
                        :type :integer
                        :min 1
                        :max 65535)
```

A `:type` and an explicit `:parser` are mutually exclusive, `:min`/`:max`
require a numeric `:type`, and `:min` may not exceed `:max`; all three are
checked at `make-*` time. The resolved type and range appear in help metadata
(for example `type: integer; range: 1..64`). Type failures and out-of-range
values are reported as `cl-cli:cli-invalid-option-value` /
`cl-cli:cli-invalid-positional-value`, exactly like a failing `:parser`. Numeric
parsing binds `*read-eval*` off, so a crafted value can never execute code.

## Validation and exit codes

When a domain rule does not fit a built-in `:type`, option and positional
parsers remain the right place for custom validation:

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

`run-app` returns `0` on success, `64` (`EX_USAGE`) for a `cli-usage-error`, and
`70` (`EX_SOFTWARE`) for any other unhandled error — the BSD sysexits
conventions. Pass `:usage-exit-code` and/or `:error-exit-code` to match a
different policy (for example `:usage-exit-code 2` to mirror argparse):

```lisp
(cl-cli:run-app *app* :argv argv :usage-exit-code 2 :error-exit-code 1)
```

### Knowing where a value came from

`option-value-source` reports the provenance of an option value — one of
`:command-line`, `:env`, `:config`, or `:default` (or `nil` when the option was
never set). This is the analogue of clap's `ArgMatches::value_source`, and lets
a handler tell an explicit user choice apart from a fallback — the key to
"only override when the user actually set it" and to layered-config merges:

```lisp
(lambda (invocation)
  (when (eq (cl-cli:option-value-source invocation :output) :command-line)
    (override-output (cl-cli:option-value invocation :output)))
  0)
```

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

Like `format`, these renderers take an optional stream: called with no stream
they return the script as a string, and called with a stream they write to it
and return no values. Pass an explicit stream to avoid building an intermediate
string:

```lisp
(cl-cli:render-completion *app* "bash" *standard-output*)
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

Current built-in support is `bash`, `zsh`, `fish`, `powershell` (alias `pwsh`),
`nushell` (alias `nu`), and `elvish`. Generated completion offers command names,
their options, and positional values from a positional's `:choices` or
`:completion-candidates`. The bash, zsh, and fish completers descend the
full nested-subcommand tree (`app remote add`, with each level's accumulated
option scope); the remaining shells complete the top command level. Hidden
commands and hidden options are omitted from the generated script. Aliases are included in generated completion candidates.
Options declared with `:choices` also feed shell value completion candidates.
Use `:completion-candidates` when shell suggestions should be broader or
differently documented than parser validation. The PowerShell renderer emits a
`Register-ArgumentCompleter -Native` script block that suggests subcommands and
option tokens, switching to a subcommand's own options once that subcommand
appears on the line; the Nushell renderer emits an `export extern` module
covering subcommands and global option flags:

```lisp
(cl-cli:render-powershell-completion *app*)
(cl-cli:render-nushell-completion *app*)
```

## Dynamic completion

For candidates that are only known at runtime (branch names, hostnames, records
in a database), attach a `:complete` function to an option or positional and add
the hidden callback command with `make-standard-commands :include-dynamic-p t`
(or `make-complete-command`):

```lisp
(cl-cli:make-app
 :name "demo"
 :global-options (list (cl-cli:make-option
                        :name "branch"
                        :kind :value
                        :complete (lambda (partial)
                                    (remove-if-not
                                     (lambda (b) (eql 0 (search partial b)))
                                     (list-git-branches)))))
 :commands (cl-cli:make-standard-commands :include-dynamic-p t))
```

All six generated completions — bash, zsh, fish, PowerShell, nushell, and
elvish — then call `demo __complete branch <partial>` at completion time and
offer whatever the function prints. (bash/zsh/fish and elvish shell out from the
completion function; PowerShell inspects the token before the cursor; nushell
attaches a per-flag custom completer.) Because the shell already knows which
slot it is completing, the callback only receives the option/positional key and
the partial word — the full command line is never re-parsed. A candidate may be
a plain string or a `(value . description)` cons; descriptions are emitted
tab-separated and shown by shells that support them.
`cl-cli:render-complete-reply` performs the same lookup directly if you wire the
callback yourself.

## Documentation generation

Beyond interactive `--help`, `cl-cli` can render offline reference documentation
directly from an app spec, reusing the same option/command metadata so the docs
never drift from the parser. Both renderers follow the completion renderers'
stream contract (no stream returns a string; a stream is written to and returns
no values):

```lisp
(cl-cli:render-manpage *app*)   ; a section-1 man page (roff)
(cl-cli:render-markdown *app*)  ; GitHub-flavored Markdown reference
(cl-cli:render-json *app*)      ; machine-readable spec for tooling
```

The man page covers NAME, SYNOPSIS, DESCRIPTION, OPTIONS, ARGUMENTS, COMMANDS,
EXIT STATUS, EXAMPLES, and an ENVIRONMENT section for env-backed options, plus
SEE ALSO / AUTHORS sections and a `.TH` date when the app declares `:see-also` /
`:authors` / `:manual-date` (it passes `mandoc -T lint` cleanly); the Markdown
output produces a title, a usage block,
option/argument tables, per-command sections, and examples. `render-json` emits
the declared spec — options, positionals, commands, and their `:type`, range,
delimiter, choices, and default metadata — as a minified JSON object that
external tooling can consume. Hidden options and commands are omitted from all
three.

To let users generate these themselves, add the built-in `docs [FORMAT]` command
(the documentation counterpart to `completion [SHELL]`). It defaults to `man`
and also accepts `markdown` and `json`:

```lisp
(cl-cli:make-app
 :name "demo"
 :commands (append
            (cl-cli:make-standard-commands :include-docs-p t)
            (list ...)))
```

```bash
demo docs man       > demo.1
demo docs markdown  > docs/demo.md
demo docs json      > demo.schema.json
```

`cl-cli:render-docs` dispatches to the two renderers by format name if you need
the same routing without the command wrapper.

## Command shapes

Use `:default-command` when a subcommand app should dispatch a command even
without an explicit command token. Use root `:positionals` plus a root
`:handler` for script-style CLIs such as `SCRIPT [ARGS...]`. Conversely, pass
`:require-command t` to `make-app` when a subcommand is mandatory: parsing then
fails with `cli-unknown-command` (listing the available commands) if the root is
invoked without one.

## Nested subcommands

A command may declare its own `:subcommands`, so it dispatches like a mini-app
(`git remote add`). The next non-option token after the command selects a
subcommand, and the parent command's options remain available to the whole
subtree; global options and counters accumulate across the entire path:

```lisp
(cl-cli:make-app
 :name "git"
 :global-options (list (cl-cli:make-option :name "verbose" :short #\v :kind :count))
 :commands
 (list (cl-cli:make-command
        :name "remote"
        :options (list (cl-cli:make-option :name "porcelain" :kind :flag))
        :subcommands
        (list (cl-cli:make-command
               :name "add"
               :positionals (list (cl-cli:make-positional :key :name :required-p t)
                                  (cl-cli:make-positional :key :url :required-p t))
               :handler (lambda (invocation)
                          (format t "add ~A ~A~%"
                                  (cl-cli:positional-value invocation :name)
                                  (cl-cli:positional-value invocation :url))))))))
```

`git -v remote --porcelain add origin URL` dispatches the `add` handler with the
global `--verbose` count and the parent `--porcelain` flag both visible. Nesting
works to arbitrary depth. `invocation-command` is the dispatched leaf command and
`invocation-command-path` is the full root-to-leaf chain. Command help renders a
path-qualified usage line (`Usage: git remote add ...`) and lists a command's
subcommands, and the man/Markdown/JSON renderers recurse through the tree. When a
parent command has subcommands but no handler, running it with no subcommand
token prints that command's help listing its subcommands. A mistyped subcommand
of a command that takes no positionals signals `cli-unknown-command` with a
suggestion. A command may also declare a `:default-command` naming one of its
subcommands to dispatch when no subcommand token is present, mirroring the
app-level `:default-command`.

## Abbreviated options

Pass `:allow-abbreviated-options t` to `make-app` for GNU-style prefix matching,
where a unique unambiguous prefix of a long option stands in for the full name
(`--verb` for `--verbose`). An ambiguous prefix signals `cli-unknown-option`
listing the candidates, and an exact match always wins over a longer option that
merely shares the prefix. It is off by default to preserve strict exact-match
parsing.

## Response files

Pass `:expand-response-files t` to `make-app` to expand a `@path` argument into
the whitespace-separated arguments read from that file before parsing (useful
when a command line grows past a shell's length limit). Expansion is recursive,
`@@` yields a literal leading `@`, and a missing file signals a usage error:

```lisp
(cl-cli:run-app (cl-cli:make-app :name "tool" :expand-response-files t ...)
                :argv '("tool" "@args.txt"))
```

## Colored help

`print-app-help`, `print-command-help`, and `run-app` accept `:color t` to wrap
headings and option/command names in ANSI styling, and `:width N` to word-wrap
descriptions to column N (continuation lines align under the description gutter).

Both accept `:auto` for terminal-aware detection so the common case needs no
manual probing:

- `:color :auto` disables color when `NO_COLOR` is set, forces it on when
  `CLICOLOR_FORCE` is set to anything but `0`, and otherwise enables it only
  when the target stream is a terminal (isatty; SBCL probes the real
  descriptor, other implementations fall back to the environment rules).
- `:width :auto` reads `$COLUMNS`, wrapping to that width when it is a positive
  integer and leaving output unwrapped otherwise.

Explicit `t` / `nil` / integer values still force the decision, and the defaults
stay `nil` (no styling, no wrapping) so nothing changes unless you opt in:

```lisp
;; Follow the terminal and the NO_COLOR / CLICOLOR_FORCE / COLUMNS conventions:
(cl-cli:run-app *app* :argv (cl-cli:current-process-argv) :color :auto :width :auto)

;; Or force it, as before:
(cl-cli:run-app *app* :argv (cl-cli:current-process-argv) :color t :width 80)
```

To suppress the built-in `-h` / `--help` flag entirely — for a CLI that manages
its own help or forwards `--help` to a wrapped tool — pass `:auto-help nil` to
`make-app` (a `help` command from `make-standard-commands` still works).

## Negative-number arguments

By default a token like `-5` is parsed as a short-option cluster (and rejected
if `5` is not an option). Pass `:allow-negative-numbers t` to `make-app` so a
token that looks like a negative number (`-5`, `-1.5`) is instead kept as a
positional or option value — useful for numeric CLIs:

```lisp
(cl-cli:make-app :name "calc" :allow-negative-numbers t
                 :positionals (list (cl-cli:make-positional :key :n :type :number)))
```

## Public API reference

All public symbols live in the `cl-cli` package.

**Spec constructors** — `make-app`, `make-command`, `make-option`,
`make-positional`, `exclusive-group`, `required-exclusive-group`,
`inclusive-group`.

**Built-in commands** — `make-standard-commands` (the aggregate), or the
individual `make-help-command`, `make-version-command`,
`make-completion-command`, `make-docs-command`, and `make-complete-command` (the
hidden dynamic-completion callback; `render-complete-reply` is its logic).

**Parsing and dispatch** — `parse-argv` returns an invocation object without
running handlers; `run-app` parses and dispatches, returning a process exit
code.

**Help** — `print-app-help` and `print-command-help` render help text directly
to a stream, independent of the built-in `help` command.

**Shell completion** — `render-completion` (shell name as a string) plus the
shell-specific `render-bash-completion`, `render-zsh-completion`,
`render-fish-completion`, `render-powershell-completion`,
`render-nushell-completion`, and `render-elvish-completion`.

**Documentation** — `render-manpage`, `render-markdown`, and `render-json`
render offline reference docs and machine-readable schema; `render-docs`
dispatches to them by format name (`"man"` / `"markdown"` / `"json"`).

**Runtime argv** — `current-process-argv`, `application-argv`,
`extract-application-argv`, `default-runtime-markers`, and
`strip-argv-separators` normalize launcher-inserted tokens and `--` separators.

**Invocation accessors** — `option-value` and `positional-value` read resolved
values; `option-value-source` reports where an option value came from
(`:command-line` / `:env` / `:config` / `:default`). `invocation-app`,
`invocation-command`, `invocation-action`, `invocation-argv0`,
`invocation-raw-argv`, `invocation-global-options`, `invocation-command-options`,
`invocation-positionals`, `invocation-command-path`, `invocation-option-sources`,
`invocation-stdout`, and `invocation-stderr` expose the rest of the parsed
invocation. `command-by-name` resolves a command spec by name or alias.

**Spec accessors** — every `make-app` / `make-command` / `make-option` /
`make-positional` keyword has a matching reader in the `app-*`, `command-*`,
and `option-*` families (for example `app-commands`, `command-options`,
`option-required-p`).

**Conditions** — usage errors subclass `cli-usage-error`; specification errors
signal `cli-invalid-specification`. Concrete conditions include
`cli-unknown-option`, `cli-unknown-command`, `cli-missing-option-value`,
`cli-missing-dependent-option`, `cli-missing-any-of-options`,
`cli-conflicting-options`, `cli-missing-positional`, `cli-invalid-option-value`,
`cli-invalid-positional-value`, and `cli-unexpected-argument`, each with
readers such as `cli-error-message` for structured handling.

## Scope and non-goals

cl-cli aims for feature parity with the mainstream CLI frameworks (clap, cobra,
click, argparse) on everything that is fundamentally a *parsing, dispatch, help,
or completion* concern. A few capabilities those frameworks offer are
deliberately left to the application, because they are runtime-I/O or
policy concerns rather than argument handling:

- **Interactive prompting** for missing values, hidden/password input, and
  confirmation prompts (click's `prompt=` / `hide_input=`). Reading a terminal
  with echo disabled is an I/O concern; clap and cobra defer it too. A handler
  can prompt from `invocation-stdout` / `invocation-stderr` as needed.
- **Filesystem-touching validators** (existence/readability checks). Declare
  intent with `:value-hint :file` / `:dir` for completion, and enforce with a
  custom `:parser`; whether a path must already exist is per-app policy.
- **Config-file *parsing*** (TOML/YAML). The `:config` layer accepts an
  already-parsed plist and slots it between env vars and literal defaults
  (see `option-value-source`); choosing and reading the file format stays with
  the caller.
- **Stdin values, progress bars, and completion-script installation** are pure
  runtime behavior; the library gives you a `-`-token you can special-case, the
  streams to draw on, and `render-*-completion` output to install where you like.

Everything else the reference frameworks expose — including terminal-aware
color/width, value provenance, "did you mean" suggestions, and configurable
exit codes — is built in and covered above.

## Test

```bash
sbcl --non-interactive --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)' --quit
ecl --norc --load tests/run-tests.lisp --eval '(cl-cli/tests:run-tests)'
nix flake check
```

## Contributing

Development workflow, change expectations, and verification requirements are
documented in [CONTRIBUTING.md](CONTRIBUTING.md).

## Support

Usage questions, bug-report expectations, and maintainer support boundaries are
documented in [SUPPORT.md](SUPPORT.md).

## Changelog

User-visible release notes are tracked in
[CHANGELOG.md](CHANGELOG.md).

## Releasing

The maintainer release checklist is documented in
[RELEASING.md](RELEASING.md).

## Security

Private vulnerability handling expectations are documented in
[SECURITY.md](SECURITY.md).

## License

MIT
