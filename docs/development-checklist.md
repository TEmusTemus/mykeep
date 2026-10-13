# Development Checklist

Complete these gates in order for every issue.

1. Confirm the issue scope, approved architecture, and all prerequisite PRs. Do not begin dependent work until each prerequisite is approved and merged.
2. Synchronize `main`, create one `<type>/<issue>-<slug>` branch, and keep the change limited to that issue.
3. Implement the change while preserving the security invariants: server-side LINE token verification, resolved-member authorization, server-only secrets, private server-authorized Storage, and no logging of sensitive values.
4. Add or update the appropriate tests. For file endpoints, prove owner success and another approved member's denial, without disclosing foreign file existence.
5. Run applicable formatting, linting, type checking, tests, frontend production build, migration checks, dependency/security checks, and secret scanning. Record exact commands and results.
6. Inspect the final diff. Remove unrelated edits and verify it contains no credentials, tokens, cookies, private member data, raw LINE user IDs, filenames, object keys, signed URLs, or uploaded file contents.
7. Commit with a Conventional Commit and open an issue-linked PR describing scope, approach, changed files, test evidence, security impact, and migration impact.
8. Wait for required CI checks and review approval. Do not merge to `main` or deploy without explicit approval.
