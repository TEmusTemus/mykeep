# Database runtime access

FastAPI connects with a separately provisioned login role and immediately uses
`SET LOCAL ROLE mykeep_api` inside every member-scoped transaction. The
`mykeep_api` role created by the migration is `NOLOGIN`, `NOINHERIT`, and
`NOBYPASSRLS`; it owns neither application tables nor resolver functions.

The login credential is provisioned outside this repository. It must be a
`NOINHERIT`, `NOBYPASSRLS`, non-owner login role with no direct application
grants. An operator grants it membership in `mykeep_api` solely so FastAPI can
assume that restricted role with `SET LOCAL ROLE mykeep_api`. It must not be a
member of a service, migration, superuser, or `BYPASSRLS` role. The service
role is never used for member-scoped work.

The migration administrator (`postgres` in Supabase's local migration/test
environment) receives one-way membership in `mykeep_api` so the pgTAP suite
can execute as the restricted role. That administrative membership does not
give `mykeep_api` any ability to assume `postgres`, and FastAPI never uses the
administrator credential.

For every request, FastAPI must begin an explicit transaction, use
parameterized SQL to set only `mykeep.lookup_hash` or `mykeep.session_hash`,
call the restricted resolver, verify the enabled member and valid session
state, and only then set `mykeep.member_id`. It commits or rolls back before
returning the connection to the pool. No connection may be reused with an open
transaction. Rotation inserts the replacement session and marks the previous
session rotated with that replacement UUID in the same transaction.

These settings are trustworthy only through this FastAPI boundary. A party able
to execute arbitrary SQL with the runtime credential can set them too, so that
credential is never exposed to browsers, logs, CI output, or untrusted code.
The fixed `SECURITY DEFINER` resolver functions are administrator-owned,
pin their search path, accept no caller-supplied SQL, and return only a resolved
UUID after their required checks.
