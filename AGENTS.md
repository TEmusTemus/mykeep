# MyKeep Agent Guide

## Scope and stack

MyKeep is a private family cloud-storage application. Issue #1 establishes governance only; do not add application features until their prerequisite governance, tooling, and architecture work has been approved and merged.

The planned stack is React, TypeScript, Vite, Tailwind CSS, and Vitest for the frontend; Python 3.12+, FastAPI, and pytest for the backend; and Supabase PostgreSQL with private Supabase Storage. The frontend runs on Vercel and the backend runs on Cloud Run in `asia-southeast1`, while remaining portable to a compatible Python host.

## Security invariants

- Treat LIFF client data as untrusted. Send only the raw `liff.getIDToken()` credential over HTTPS to FastAPI, and authenticate only from LINE's server-side verification response using the verified `sub` claim, expected channel ID, issuer, and expiry.
- Never log, persist, or send an ID token to analytics. Use `HMAC-SHA-256(LINE sub, membership lookup secret)` for member lookup; do not expose raw LINE user IDs to clients or ordinary logs.
- Issue short-lived MyKeep sessions only to approved, enabled members. Store sessions in `HttpOnly`, `Secure`, `SameSite` cookies; support rotation and revocation; and check member status on every request.
- Do not add self-service enrollment or administrative browser screens. Provision, disable, or remove members only with an operator-only CLI or controlled database migration.
- Resolve the authenticated member once in middleware or dependencies. Endpoint and repository interfaces accept that resolved member UUID, never a caller-supplied owner ID.
- Keep Supabase service-role and secret keys server-side only. They must never appear in Vite variables, browser bundles, committed files, or CI logs. Revoke unnecessary anonymous and direct-client privileges, enable RLS, and use least-privilege grants.
- Authorize every private Storage action through FastAPI. Create short-lived signed download URLs only after owner authorization. Return the same `404` for absent, deleted, and foreign-owned files.
- Use opaque storage keys only: `members/<member-uuid>/<file-uuid>/blob`. Do not accept client-selected paths. Store user objects in the private `mykeep` bucket and never modify the Supabase `storage` schema directly.
- Stream uploads through FastAPI, enforce configured size and MIME allow-lists, sanitize filenames, calculate SHA-256 checksums, and avoid accessible metadata after failure. Serve unknown or active content as attachments; never render user HTML or SVG inline.
- Soft-delete for 30 days, block normal listing and download while deleted, and purge metadata and objects only after the recovery window. Restore is owner-only.
- Restrict CORS to exact environment-specific Vercel origins. Enforce HTTPS, request-size and rate limits, and security headers. Redact tokens, cookies, authorization headers, object keys, signed URLs, and filenames from structured logs.
- Keep `/healthz` and `/readyz` free of secrets. Use managed backups and complete a documented restore exercise before production.

## Planned repository layout

Later issues will introduce a monorepo layout for the React frontend, FastAPI backend, database migrations and provisioning, tests, and CI configuration. Keep changes within the issue's approved scope and do not pre-create feature scaffolding without an approved issue.

## Delivery rules

- Work from a synchronized `main` on a branch named `<type>/<issue>-<slug>`.
- Make Conventional Commits: `<type>(<optional scope>): <description>`.
- Every change must be linked to one GitHub issue and delivered through an issue-linked PR. Do not commit directly to `main`, force-push, merge, or deploy without explicit approval.
- Use a single-agent workflow by default for straightforward implementation, documentation, and configuration work. Additional agents and repeated reviews are optional when permitted by higher-priority instructions; reserve them for complex architecture, authentication, security, or difficult debugging. Security-sensitive changes still require focused review and the applicable validation evidence.
- Run the validations required by the affected area and record exact commands and results in the PR. CI must pass formatting, linting, type checks, tests, frontend production build, migration checks, dependency/security checks, and secret scanning when those tools exist.
- Inspect the final diff and scan it for secrets before opening a PR. Never commit credentials, cookies, tokens, private member data, or file data; use local secret management and documented environment configuration instead.
- A task that depends on another task must wait until the prerequisite PR is approved and merged. Do not rely on an unmerged branch as a dependency.
