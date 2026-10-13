# MyKeep Architecture and Foundation Design

**Status:** Approved design; implementation has not started
**Issue:** #1 — Project foundation and delivery governance
**Decision date:** 2026-10-13

## Purpose and Scope

MyKeep is a private cloud-storage application for a small family, opened from a LINE MINI App / LIFF experience. Each approved family member has a strictly isolated storage space. This design defines the security boundaries, operating model, delivery process, and v1 scope before application features are implemented.

V1 includes: approved-member sign-in, upload, file listing and search, download, rename, soft delete, and restore within a member's own storage space. It excludes sharing, family folders, public links, self-service enrollment, and administrative browser screens.

## Chosen Architecture

MyKeep uses a backend-for-frontend architecture:

1. The React/TypeScript frontend initializes LIFF and obtains the raw LINE ID token.
2. It sends that token over HTTPS to FastAPI; it never treats decoded client-side profile data as authentication.
3. FastAPI calls LINE's `POST /oauth2/v2.1/verify` endpoint with the received token and the configured expected channel ID. It accepts identity only from the verified response's `sub` claim.
4. FastAPI compares a keyed hash of that LINE subject to the operator-maintained approved-member allow-list. Unapproved and disabled subjects receive no MyKeep session.
5. On success, FastAPI issues a short-lived MyKeep session in an `HttpOnly`, `Secure`, `SameSite` cookie. The browser never receives a Supabase secret or service key.
6. React calls FastAPI for all metadata and file operations. FastAPI authorizes the member before using Supabase PostgreSQL or private Storage.

The frontend is deployed to Vercel. FastAPI is containerized and deployed to Cloud Run in `asia-southeast1`, while remaining portable to another compatible Python host. Supabase has distinct development, staging, and production projects.

Direct browser access to Supabase is deliberately excluded from v1. It would require a LINE-to-Supabase Auth bridge and client-managed RLS identity. Server-mediated access has a smaller security surface for a family application and is easier to test and audit.

## Trust Boundaries and Security Controls

### Authentication and sessions

- Require LIFF's `openid` scope and use `liff.getIDToken()` only to obtain the raw credential for FastAPI.
- Send the ID token only over HTTPS; never log, persist, or expose it to analytics.
- Verify every initial authentication token server-side against LINE with the configured channel ID, issuer, expiry, and returned subject.
- Issue MyKeep sessions with a short expiry, rotation/revocation support, and a server-side member-status check on every request.
- Store only the minimum account data. Member lookup uses `HMAC-SHA-256(LINE sub, membership lookup secret)`; raw LINE user IDs are not exposed to clients or ordinary logs.
- Provision, disable, and remove members only through an operator-only CLI or controlled database migration. No public enrollment endpoint exists.

### Authorization and data isolation

- Resolve the authenticated member exactly once in request middleware/dependencies; endpoint and repository interfaces accept that resolved member UUID rather than a caller-supplied owner ID.
- Enable RLS and least-privilege grants on all application tables. Revoke anonymous/direct-client privileges that are not required.
- Keep Supabase service-role/secret keys server-side only. They are never present in Vite variables, browser bundles, CI logs, or committed files.
- Make all private Storage access server-authorized. The backend creates short-lived signed download URLs only after owner authorization.
- Return a common `404` for absent, deleted, and foreign-owned files so the API does not disclose existence.
- Use opaque object keys, never client-selected paths or visible names, to prevent path traversal and cross-member key guessing.

### File handling

- Store each object beneath `members/<member-uuid>/<file-uuid>/blob` in a private `mykeep` bucket.
- Persist original name, sanitized display name, MIME type, byte size, SHA-256 checksum, opaque object key, owner UUID, and lifecycle timestamps in PostgreSQL.
- Stream uploads through FastAPI. Enforce configured maximum size and allowlisted content types, sanitize filenames, calculate a checksum, and ensure failure does not leave an accessible metadata record.
- Serve unknown or active content as an attachment. Do not render user-supplied HTML or SVG inline.
- Soft-delete a file for 30 days, blocking it from normal listing and downloads. A scheduled purge permanently removes its metadata and object after the recovery window. Restore is owner-only.

### Operational protections

- Restrict CORS to the exact Vercel frontend origins for each environment.
- Enforce HTTPS, request-size limits, upload and authentication rate limits, and standard security headers.
- Emit structured logs with request IDs while redacting tokens, cookies, authorization headers, object keys, signed URLs, and filenames.
- Provide `/healthz` for process health and `/readyz` for dependency readiness without exposing secrets.
- Use managed database backups and document a periodic restore exercise before production use.

LINE documents the required server-side verification flow for LIFF ID tokens, and Supabase documents private-bucket RLS and signed-URL controls. See [LINE token guidance](https://developers.line.biz/en/tips/2026/08/13/send-token-to-server/), [LINE ID-token verification](https://developers.line.biz/en/reference/line-login/), and [Supabase private buckets](https://supabase.com/docs/guides/storage/buckets/fundamentals).

## Logical Data Model

| Entity | Responsibility | Isolation rule |
| --- | --- | --- |
| `members` | Approved identity, status, timestamps, lookup hash | One row is resolved from the verified LINE subject; only server/operator access |
| `files` | File metadata, ownership, storage key, deletion lifecycle | A member may operate only on rows with its own UUID |
| `audit_events` | Minimal security-relevant events and request correlation | Append-only server writes; no credentials or file contents |
| `sessions` (if persisted) | Revocation/rotation state | Tied to one member and checked before authorization |

`files` owns the logical lifecycle. Storage objects are created and removed only by the Storage API; application code must not modify the `storage` schema directly.

## API and UI Responsibilities

The React application owns LIFF initialization, presenting the authenticated member's file experience, client-side validation feedback, progress UI, and calling typed FastAPI API-client functions. It does not contain authorization decisions, privileged Storage access, or secret configuration.

FastAPI owns token verification, MyKeep session issuance, request authorization, upload streaming, metadata consistency, signed-URL creation, audit logging, and error mapping. Every route has explicit request/response schemas and uses domain services and repositories rather than embedding Storage calls in route handlers.

V1 endpoints are grouped by responsibility: authentication/session, member profile, files, and operational health. File actions are scoped solely by the resolved authenticated member, never by a member ID supplied in a URL or body.

## Failure Handling

- Invalid, expired, mismatched-audience, or unavailable LINE token verification fails closed without a session.
- Unapproved or disabled members receive an authorization failure that reveals no allow-list details.
- Storage, database, and LINE outages return a safe retryable service error with a request ID; no provider response body or secret is returned.
- Upload cleanup is idempotent: retries cannot create a second visible file record, and failed persistence schedules safe object cleanup.
- Deletion and restore validate lifecycle state and are idempotent where practical.

## Quality and Delivery Requirements

- Frontend: React, TypeScript, Vite, Tailwind CSS, Vitest.
- Backend: Python 3.12+, FastAPI, pytest.
- Database/storage: Supabase PostgreSQL with private Supabase Storage.
- CI validates formatting, linting, type checking, tests, frontend production build, migration checks, dependency/security checks, and secret scanning.
- Tests include unit coverage for token verification, session and authorization logic; integration coverage for database/storage lifecycle; and end-to-end coverage of LIFF handoff and cross-user denial.
- Every file endpoint must prove both owner success and another approved member's denial.
- `main` is PR-only, with required checks and no force pushes. Every task is tracked by a GitHub issue, implemented on one feature branch, committed conventionally, and delivered through an issue-linked PR. Merge and deployment always require explicit approval.

## Phased Delivery Shape

1. Governance and repository foundation.
2. Monorepo/tooling and quality baseline.
3. Database, private Storage, migrations, and member provisioning.
4. LINE verification and MyKeep sessions.
5. Authorized file API and lifecycle.
6. LIFF user interface.
7. Security hardening, recovery, and observability.
8. Staging deployment and acceptance testing.

Each phase is decomposed into independently reviewable GitHub issues. Feature implementation remains out of scope for Issue #1.
