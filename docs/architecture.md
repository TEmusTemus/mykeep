# MyKeep Architecture

MyKeep is a private family cloud-storage application opened through a LINE MINI App / LIFF experience. It uses a backend-for-frontend architecture: the React client handles the user experience, FastAPI owns authentication and authorization, and Supabase provides PostgreSQL and private object storage. The detailed rationale and v1 scope remain in the [approved foundation design](superpowers/specs/2026-10-13-mykeep-foundation-design.md).

## Trust boundaries

- The browser and all LIFF-provided client data are untrusted. The frontend may obtain the raw credential with `liff.getIDToken()`, but it does not authenticate from decoded profile data.
- FastAPI is the only application boundary allowed to verify identity, issue a MyKeep session, make authorization decisions, or use privileged Supabase credentials.
- PostgreSQL and the private `mykeep` Storage bucket are server-side dependencies. The browser never receives a Supabase service-role or secret key and never accesses private objects directly.
- Operators provision, disable, and remove members through a controlled CLI or database migration. V1 has no self-service enrollment or administrative browser interface.

## Authentication and session sequence

1. The React client initializes LIFF with the `openid` scope and obtains the raw LINE ID token.
2. The client sends only that token to FastAPI over HTTPS. The token is never logged, persisted, or sent to analytics.
3. FastAPI sends the token and configured channel ID to LINE's `POST /oauth2/v2.1/verify` endpoint. Authentication fails closed unless LINE verifies the issuer, audience/channel ID, expiry, and subject.
4. FastAPI derives `HMAC-SHA-256(LINE sub, membership lookup secret)` and looks up an approved, enabled member. Raw LINE user IDs are not exposed to clients or ordinary logs.
5. FastAPI issues a short-lived MyKeep session in an `HttpOnly`, `Secure`, `SameSite` cookie. Sessions support rotation and revocation.
6. Every authenticated request rechecks member status. Middleware or a dependency resolves the member once, and endpoints and repositories receive that member UUID rather than an owner ID supplied by the caller.

## Ownership and private files

The `members` table represents the operator-approved identity. Each `files` row belongs to exactly one member UUID and records its original name, sanitized display name, MIME type, size, SHA-256 checksum, opaque object key, and lifecycle timestamps. Security-relevant activity is recorded in minimal, append-only `audit_events`; persisted sessions, if used, remain tied to one member.

Application tables use row-level security and least-privilege grants, with unnecessary anonymous and direct-client privileges revoked. Every file operation is authorized against the resolved member. Absent, soft-deleted, and foreign-owned files all return the same `404` so the API does not reveal whether another member's file exists.

Objects live only in the private `mykeep` bucket under server-generated keys:

```text
members/<member-uuid>/<file-uuid>/blob
```

Clients cannot choose object paths. FastAPI streams uploads, enforces configured size and MIME allow-lists, sanitizes filenames, calculates checksums, and prevents failed uploads from leaving accessible metadata. It creates short-lived signed download URLs only after owner authorization. Unknown or active content is served as an attachment; user HTML and SVG are never rendered inline. Application code uses the Storage API and does not modify Supabase's `storage` schema.

Files are soft-deleted for 30 days. Normal listing and download exclude them, owners may restore them during that window, and a scheduled job purges both metadata and objects afterward.

## Failure handling

- Invalid, expired, mismatched, or unverifiable LINE tokens produce no session.
- Unapproved and disabled members receive an authorization failure without allow-list details.
- LINE, database, and Storage outages return a safe retryable service error with a request ID, without provider response bodies or secrets.
- Upload cleanup is idempotent: retries do not create a second visible record, and failed persistence schedules safe object cleanup.
- Delete and restore operations validate lifecycle state and are idempotent where practical.

## Deployment and secrets

The React/Vite frontend runs on Vercel. Containerized FastAPI runs on Cloud Run in `asia-southeast1` while remaining portable to a compatible Python host. Development, staging, and production use separate Supabase projects, and CORS allows only the exact Vercel origins for each environment.

### Cross-origin session deployment

When Vercel and Cloud Run use different origins, browser requests must opt in to credentials and FastAPI must return an exact allowed origin plus `Access-Control-Allow-Credentials`; wildcard origins are incompatible with credentialed requests. Session cookies need `Secure`, `HttpOnly`, and an appropriate `SameSite` setting—typically `None` for genuinely cross-site deployment—and should remain host-only on the API domain unless a verified custom-domain design requires otherwise. Cookie authentication also requires CSRF protection for state-changing endpoints, using origin/referer validation together with a CSRF token or custom request header. Validate this flow in the LINE LIFF in-app browser on supported devices because embedded-browser cookie policies can differ from ordinary browsers; do not assume third-party-cookie behavior is available.

All secrets stay in server-side secret management. Supabase service credentials, the membership lookup secret, session secrets, LINE credentials, tokens, cookies, signed URLs, object keys, and filenames must not appear in Vite variables, browser bundles, committed files, CI logs, analytics, or ordinary structured logs. Logs use request IDs and redact sensitive headers and values. HTTPS, request-size limits, authentication and upload rate limits, and security headers are enforced. `/healthz` and `/readyz` expose no secrets.

Managed database backups are required, and a documented restore exercise must be completed before production use.

## Verification layers

- Unit tests cover LINE verification responses, HMAC member lookup, session rotation and revocation, member-status checks, authorization, lifecycle rules, and safe error mapping.
- Integration tests cover migrations, row-level security, private Storage behavior, upload consistency and cleanup, signed downloads, soft delete, restore, and purge.
- End-to-end tests cover LIFF-to-FastAPI sign-in, file workflows, failure states, and cross-member isolation.
- Every file endpoint proves both owner success and another approved member's denial. CI also runs formatting, linting, type checks, backend and frontend tests, the frontend production build, migration checks, dependency and security checks, and secret scanning.
