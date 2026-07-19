# Security Policy

## Supported versions

This project does not currently publish versioned support windows. Report issues
against the latest commit on the default branch.

## Reporting a vulnerability

Do not open a public issue for a suspected security problem.

Report it privately through GitHub's private vulnerability reporting:

1. Go to <https://github.com/takeokunn/cl-cli/security/advisories/new>
   (also reachable from the repository's **Security** tab → **Report a
   vulnerability**).
2. Include:
   - a description of the issue
   - impact and expected attack conditions
   - a minimal reproduction if available
   - any proposed mitigation or patch

GitHub keeps the report private between you and the maintainers until an
advisory is published.

## Response expectations

Maintainers should aim to:

- acknowledge receipt
- reproduce and assess impact
- prepare a fix and regression test
- disclose the issue after a fix is available when responsible to do so

Because this is a library, security fixes should also document whether the risk
is exploitable through default parser behavior or only through consumer misuse.
