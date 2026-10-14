# GitHub Actions CI Design

## Goal

Provide pull-request CI that enforces MyKeep's existing frontend and backend
quality gates, dependency-security checks, and repository secret scanning.

## Scope and constraints

- Deliver only Issue #3's automation; do not add application functionality.
- Run only against pull requests targeting `main`.
- Use the already pinned local toolchains: Node 24 and Python 3.12.
- Keep workflow permissions read-only and avoid logging sensitive values.
- Preserve the repository's existing workspace scripts and Python project
  configuration rather than duplicating application commands.

## Architecture

One workflow at `.github/workflows/ci.yml` will trigger on pull requests to
`main`. It will use independent frontend, backend, and security jobs, so a
failure clearly identifies the affected gate and jobs can execute in parallel.

The frontend job installs dependencies reproducibly with `npm ci` and runs
formatting, linting, type checking, tests, and the production build. The
backend job installs the API development dependencies and runs Ruff formatting,
Ruff linting, and pytest. The security job checks Node and Python dependencies
for known vulnerabilities and scans the checked-out repository for secrets.

Each job uses explicit tool versions, minimal `contents: read` permission, and
dependency caching where supported. Workflow concurrency cancels an older run
for the same pull request when a newer commit is pushed.

## Failure handling and verification

All commands run without failure suppression: a formatting violation, lint or
type error, failing test, failed build, vulnerable dependency at the selected
severity, or detected secret makes the corresponding job fail and blocks a
passing CI result. Repository-level tests will assert the workflow contains the
required triggers, commands, and security scanners, including a negative
fixture that demonstrates a missing required gate is rejected.

Member-isolation tests do not apply: this issue adds CI infrastructure only and
does not add a member-facing endpoint, data path, or authorization behavior.

## Out of scope

- Deployment, release, or scheduled workflows.
- Database migration tooling and checks, which do not exist in the current
  project structure.
- Changes to application source code, secrets, or authentication.
