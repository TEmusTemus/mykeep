# Contributing to MyKeep

## Choose and prepare work

1. Select an open GitHub issue with a clearly approved scope. Do not add application features before their governance and tooling prerequisites are approved and merged.
2. Synchronize your local `main` with the remote before starting.
3. Create one branch per issue, named `<type>/<issue>-<slug>`; for example, `docs/1-project-foundation`.

## Implement and validate

Make focused changes that satisfy the issue. Use Conventional Commits in the form `<type>(<optional scope>): <description>`, such as `docs: add project governance policies`.

Before opening a PR, run the applicable formatting, linting, type checking, tests, frontend production build, migration checks, dependency/security checks, and secret scanning. Include the exact commands and results as test evidence. Test security-sensitive behavior with both an owner-success case and another approved member's denial when file endpoints are introduced.

Review the final diff for unrelated changes and for credentials, tokens, cookies, private member data, raw LINE user IDs, filenames, object keys, or signed URLs. Never commit Supabase service-role or other secret keys, and never place them in Vite variables, browser bundles, or CI logs.

## Open and land a pull request

Open an issue-linked PR that explains the problem, approach, files changed, validation evidence, and any security or migration impact. Keep PRs reviewable and limited to the issue scope.

Request review and address feedback. `main` is PR-only: do not push directly to it, force-push it, merge a PR, or deploy without explicit approval. Required CI checks and review approval must be complete before merge. Work that depends on another issue must wait for that prerequisite PR to be approved and merged.
