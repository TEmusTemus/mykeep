# Supabase Schema and Migrations Design

## Goal

Create MyKeep's first versioned Supabase PostgreSQL schema for approved members,
file metadata, append-only audit events, and persisted sessions. The schema must
enforce per-member isolation with constraints, least-privilege grants, and row
level security without adding Supabase Auth or direct browser access.

## Scope

This design implements GitHub Issue #4 only. It creates database migrations,
database tests, and CI migration verification. It does not add a storage bucket
or policy, member provisioning CLI, LINE verification implementation, browser
administration screens, file endpoints, or frontend features.

## Existing trust model

The browser sends a raw LINE ID token only to FastAPI. FastAPI verifies the
token with LINE, derives HMAC-SHA-256 of the verified LINE subject with the
server-side membership lookup secret, resolves an enabled member, and issues
MyKeep's own secure cookie session. The browser does not use Supabase Auth and
does not access Supabase data directly.

The schema preserves this model. It does not store a raw LINE subject, raw ID
token, session cookie, service key, or custom browser JWT.

## Migration structure

~~~text
supabase/
  config.toml
  migrations/
    <timestamp>_create_mykeep_schema.sql
  tests/
    schema_and_rls.test.sql
    migration_rollback.test.sql
~~~

The initial migration creates extensions, types, tables, indexes, grants, RLS,
and policies in one atomic change. Every application table has RLS enabled and
forced in the same migration that creates it.

The CI-only rollback check runs against a disposable local database. Production
schema changes remain forward-only; a production error is corrected with a
reviewed follow-up migration rather than an automatic destructive rollback.

## Database roles and identity handoff

### Runtime role

A dedicated mykeep_api database role has only the privileges needed by FastAPI.
It is not a table owner, has no role memberships that grant elevated access,
and does not have BYPASSRLS.

FastAPI uses this role for member-scoped work. It does not use Supabase's
service_role credential for normal application requests because that role
bypasses RLS.

### Transaction-local context

After FastAPI has verified a LINE token or MyKeep session, it starts a database
transaction and sets only transaction-local context:

~~~text
mykeep.lookup_hash = verified HMAC-SHA-256 value
mykeep.member_id = resolved member UUID
mykeep.session_hash = SHA-256 of the presented session cookie
~~~

RLS helper functions read this context. Policies compare the context to the
relevant row. SET LOCAL scopes the values to one transaction, preventing
identity leakage through connection pooling.

The context is trusted only within the FastAPI execution boundary. It is not
tamper-proof against arbitrary SQL executed with the runtime role's database
credentials. FastAPI must use parameterized queries, never compose SQL from
request data, and keep that least-privilege credential unavailable to browsers,
operators without a runtime need, logs, CI output, and untrusted code.

Every operation uses an explicit transaction: FastAPI sets context with SET
LOCAL before its first protected query, commits or rolls back before returning
the connection to the pool, and never reuses a connection with an open
transaction. Pooling configuration must preserve transaction isolation. RLS
remains defense in depth against application-query mistakes, while FastAPI
remains the primary authentication and authorization boundary.

### Two-stage identity resolution

Identity resolution deliberately has no caller-supplied member UUID.

1. FastAPI first verifies a LINE token and derives its HMAC lookup hash, or
   hashes the opaque MyKeep session cookie. It sets only the corresponding
   lookup or session-hash context and uses a restricted RLS lookup to find the
   candidate record.
2. FastAPI then checks that the candidate member is enabled. For a session, it
   also checks that the stored token hash matches, the session is unexpired,
   unrevoked, and unrotated. A failure resolves no member.
3. Only after both checks succeed does FastAPI set mykeep.member_id to the
   resolved UUID. All member-scoped file, session, and audit operations then
   use this resolved context.

This sequence lets the database support the existing LINE and cookie flows
without introducing Supabase Auth, a browser JWT, or a URL/body owner ID.

### Direct roles

PUBLIC, anon, and authenticated receive no application-table privileges. They
cannot reach MyKeep tables through the Data API. A separate administrative role
may be used by migrations and a future operator workflow, but it is not a
member runtime role and is never exposed to a browser.

## Tables

### members

- id UUID primary key
- lookup_hash BYTEA not null unique, constrained to 32 bytes
- status constrained to enabled or disabled
- created_at and updated_at timestamps

A unique lookup-hash index supports the verified LINE identity lookup. No raw
LINE subject or profile data is persisted.

### files

- id UUID primary key
- member_id UUID not null references members(id)
- original and sanitized display filenames
- MIME type, non-negative byte size, and 32-byte SHA-256 checksum
- unique opaque storage key
- created, updated, and nullable deleted timestamps

The storage key is constrained to the exact generated form
members/<member-id>/<file-id>/blob. deleted_at supports the 30-day soft-delete
window. An active-listing partial index supports normal member file queries,
and a deleted-file index supports the later purge job.

### audit_events

- immutable event UUID
- nullable member reference using ON DELETE SET NULL
- request correlation ID
- bounded event type and outcome
- event timestamp

Audit rows do not include tokens, cookies, filenames, object keys, signed URLs,
raw LINE identifiers, or file contents. The runtime role can insert the minimum
required event record but cannot select, update, or delete audit rows unless a
later approved requirement grants a narrower capability.

### sessions

- id UUID primary key
- member_id UUID not null references members(id)
- unique 32-byte session-token hash
- issued, expiry, rotation, and revocation timestamps
- nullable replacement-session UUID that references a session for the same
  member

The table stores only a hash of the session credential. Constraints reject
invalid hash lengths and expiry/lifecycle ordering. The replacement reference
uses a composite foreign key so a session cannot rotate into another member's
session. A check requires rotated_at and replacement_session_id to be either
both null or both non-null.

The intended session-resolution query accepts a credential only when its hash
matches and expires_at is later than the database clock, revoked_at is null,
rotated_at is null, and replacement_session_id is null. Rotation inserts the
replacement session and marks the old row rotated in the same transaction.
Therefore the prior credential cannot remain valid through the approved
resolution path after that transaction commits. Revocation updates revoked_at;
expiry is evaluated by the resolver rather than relying on a delayed cleanup
job. Partial indexes support active-session lookup and revocation checks.

## RLS policies

Every table has ENABLE ROW LEVEL SECURITY and FORCE ROW LEVEL SECURITY.

- members: lookup is limited to a row whose lookup hash matches verified
  transaction context; subsequent member-scoped access is limited to the
  resolved member UUID.
- files: select, insert, update, and delete policies require the row owner
  to equal the resolved member UUID. Update policy checks both old and new
  ownership, preventing an owner reassignment.
- sessions: session resolution is limited to the transaction's presented
  hashed cookie; after resolution, member-scoped access requires the resolved
  member UUID.
- audit_events: insertion with a non-null actor requires actor_member_id to
  equal the resolved member UUID; mutation is denied. An event before member
  resolution must have a null actor_member_id and may use only the
  unauthenticated event form.

Each operation uses a distinct policy rather than a broad FOR ALL policy.
Table grants and policies are declared together because grants are evaluated
before RLS.

### Unauthenticated audit events

Authentication failures and other pre-resolution events are recorded with a
null actor_member_id, a bounded event type and outcome, and a request ID. They
do not store a supplied LINE subject, lookup hash, token, cookie, or free-form
error payload. The audit insert policy permits this form only when no member
context is set. Once a member context is set, a non-null actor must equal that
context; the runtime cannot insert an audit row naming a different member.
This protection depends on the same trusted FastAPI boundary and parameterized
query requirement as the rest of the RLS design.

## Test strategy

Database tests run against local Supabase/PostgreSQL:

1. Apply the schema to an empty database and assert expected tables, indexes,
   RLS state, grants, and policy behavior.
2. Create valid member, file, audit, and session rows.
3. Assert constraint failures for duplicate lookup/session hashes, bad digest
   sizes, unknown foreign keys, negative file size, invalid storage key,
   invalid lifecycle timestamps, and invalid member state.
4. Prove that a transaction with no member context returns no member-scoped
   rows.
5. Prove member A can operate on its own file/session records and member B
   cannot read, mutate, soft-delete, restore, or reassign them.
6. Prove anon and authenticated fail before RLS because they lack grants.
7. Prove audit events can be appended through the intended runtime path and
   cannot be updated or deleted; prove unauthenticated events require a null
   actor and authenticated events cannot name a different member.
8. Prove a transaction that sets member A context leaves no context available
   after commit or rollback, then verify a reused pooled connection cannot read
   member A data before member B context is set.
9. Prove a disabled member fails the second-stage lookup and gains no
   member-scoped access.
10. Prove expired, revoked, and rotated session hashes fail resolution, while
    the replacement credential succeeds after an atomic rotation.
11. Exercise the disposable rollback path, then confirm reapplication works.

## CI and review

The PR workflow gains a database job that installs a pinned Supabase CLI,
starts local Supabase on the Linux runner, resets/applies migrations, runs the
SQL database tests, and executes the disposable rollback verification. It uses
no hosted Supabase credentials or project secrets.

Before opening the Issue #4 pull request, run schema/migration tests alongside
the current frontend and backend checks; inspect the final migration diff; and
scan it for secrets, raw member data, connection strings, tokens, service-role
keys, filenames, object keys, and signed URLs.

