# Supabase Schema and Migrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Add a versioned, RLS-protected Supabase PostgreSQL schema and CI verification for members, files, audit events, and sessions.

**Architecture:** A Supabase migration creates the application schema, a non-bypass runtime role, transaction-context helpers, constraints, grants, and operation-specific RLS policies. SQL integration tests exercise migration behavior in local Supabase; PR CI starts that disposable environment and runs the tests.

**Tech Stack:** Supabase CLI, PostgreSQL SQL/pgTAP, GitHub Actions, Python pytest/Ruff, npm/Vitest/Vite.

## Global Constraints

- Do not add Supabase Auth, direct browser database access, authentication endpoints, Storage policies, or provisioning UI.
- FastAPI remains the only identity-verification and authorization boundary.
- Never store raw LINE subjects, LINE ID tokens, session cookies, service keys, connection strings, filenames in audit records, object keys in audit records, or signed URLs.
- The runtime role must not own tables, inherit privileged roles, or have BYPASSRLS.
- Set context only with SET LOCAL inside an explicit transaction after FastAPI verification; use parameterized SQL.
- Retain the original main checkout and its untracked diff files; work only in this worktree.

---

### Task 1: Add Supabase local configuration and migration contract tests

**Files:**
- Create: supabase/config.toml
- Create: supabase/tests/schema_and_rls.test.sql
- Test: supabase/tests/schema_and_rls.test.sql

**Interfaces:**
- Consumes: migration-created app schema, mykeep_api role, transaction-local mykeep settings.
- Produces: local Supabase test configuration and failing tests for schema existence, RLS, grants, constraints, and isolation.

- [ ] **Step 1: Write the failing SQL tests**

Use pgTAP assertions for the expected tables, RLS state, grants, and policies:

~~~sql
select plan(24);

select has_table('app', 'members');
select has_table('app', 'files');
select has_table('app', 'audit_events');
select has_table('app', 'sessions');
select row_security_is_enabled('app', 'files');

set local role mykeep_api;
select set_config('mykeep.member_id', '11111111-1111-1111-1111-111111111111', true);
select lives_ok(
  $$insert into app.files (
      id, member_id, original_name, display_name, mime_type, byte_size,
      checksum_sha256, storage_key
    ) values (
      '22222222-2222-2222-2222-222222222222',
      '11111111-1111-1111-1111-111111111111',
      'test.txt', 'test.txt', 'text/plain', 0,
      decode(repeat('ab', 32), 'hex'),
      'members/11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222/blob'
    )$$,
  'member can create an owned file'
);
~~~

Include explicit throws_ok tests for duplicate lookup hash, invalid hash size, negative byte size, invalid storage key, cross-member update, direct anon access, disabled members, expired/revoked/rotated sessions, and audit actor mismatch.

- [ ] **Step 2: Verify tests fail before the migration exists**

Run: supabase test db

Expected: FAIL because app schema, tables, role, and policies do not exist.

### Task 2: Create the initial protected schema migration

**Files:**
- Create: supabase/migrations/20261014000000_create_mykeep_schema.sql
- Test: supabase/tests/schema_and_rls.test.sql

**Interfaces:**
- Consumes: verified HMAC lookup, hashed session cookie, and resolved member UUID supplied only by FastAPI transaction context.
- Produces: app.members, app.files, app.audit_events, app.sessions; app.current_member_id(), app.current_lookup_hash(), and app.current_session_hash() helper functions.

- [ ] **Step 1: Create schema, role, types, helpers, and tables**

The migration must create app schema; create mykeep_api NOLOGIN NOBYPASSRLS NOINHERIT; and define context functions which return NULL when their setting is absent. Create UUID primary keys, BYTEA hash checks of 32 bytes, enabled/disabled member status, timestamps, and required foreign keys.

Use a same-member rotation relation:

~~~sql
alter table app.sessions
  add constraint sessions_replacement_same_member_fk
  foreign key (replacement_session_id, member_id)
  references app.sessions (id, member_id);

alter table app.sessions
  add constraint sessions_rotation_state_check
  check ((rotated_at is null) = (replacement_session_id is null));
~~~

Create files.storage_key as a check equal to members/<member_id>/<file_id>/blob, active/deleted lifecycle indexes, unique lookup/session hashes, and session validity indexes.

- [ ] **Step 2: Add grants, revocations, RLS, and policies**

Revoke all table and sequence privileges from public, anon, and authenticated. Grant mykeep_api only required schema, table, and sequence privileges. Enable and force RLS on every app table.

Create separate SELECT, INSERT, UPDATE, and DELETE policies. File policies use current_member_id() for both USING and WITH CHECK. Session resolution requires current_session_hash() and checks enabled member, expiry, revocation, and rotation state. Audit INSERT permits either null actor with no member context or actor_member_id equal to current_member_id(); grant no audit UPDATE or DELETE.

- [ ] **Step 3: Run the database tests**

Run: supabase db reset && supabase test db

Expected: PASS after all schema, validation, privilege, lifecycle, and isolation assertions are implemented.

### Task 3: Add disposable migration rollback verification

**Files:**
- Create: supabase/tests/migration_rollback.test.sql
- Modify: supabase/tests/schema_and_rls.test.sql

**Interfaces:**
- Consumes: the initial migration and an empty local database.
- Produces: a test-only verification that rollback cleanup and reapplication are safe in a disposable environment.

- [ ] **Step 1: Write the failing rollback test**

Assert that the test cleanup removes app tables, policies, and runtime role after migration application, then assert the standard reset/reapply path restores all expected objects.

- [ ] **Step 2: Run it and observe the failure**

Run: supabase test db

Expected: FAIL until the disposable rollback fixture is implemented.

- [ ] **Step 3: Implement test-only cleanup fixture**

Use transaction-scoped or disposable-database cleanup that drops only objects created by this migration. Do not add an automatic production rollback command.

- [ ] **Step 4: Verify reset, rollback fixture, and reapply**

Run: supabase db reset && supabase test db && supabase db reset && supabase test db

Expected: every command exits 0.

### Task 4: Add CI database verification

**Files:**
- Modify: .github/workflows/ci.yml
- Modify: apps/api/tests/test_ci_workflow.py
- Test: apps/api/tests/test_ci_workflow.py

**Interfaces:**
- Consumes: Supabase local configuration and SQL test suite.
- Produces: PR database-quality job using only disposable local Supabase services.

- [ ] **Step 1: Extend the workflow contract test first**

Add required snippets for a database job, pinned Supabase CLI setup, Supabase start, db reset, and test db. Add a negative test removing supabase test db.

- [ ] **Step 2: Verify the contract test fails**

Run: python -m pytest apps/api/tests/test_ci_workflow.py -q

Expected: FAIL because the workflow lacks the database job.

- [ ] **Step 3: Add the CI job**

Add a database job on ubuntu-24.04 that checks out the repository, installs a pinned Supabase CLI, starts local Supabase, resets migrations, and runs supabase test db. Do not add hosted credentials, project URLs, service keys, or secret inputs.

- [ ] **Step 4: Verify the contract test passes**

Run: python -m pytest apps/api/tests/test_ci_workflow.py -q

Expected: PASS.

### Task 5: Run complete validation and deliver Issue #4

**Files:**
- Modify: only Issue #4 schema, tests, CI, and documentation artifacts.

- [ ] **Step 1: Run local quality and application checks**

Run: npm run lint; npm run typecheck; npm run test:run; npm run build; python -m ruff format --check apps/api; python -m ruff check apps/api; python -m pytest apps/api/tests -q

Expected: all commands exit 0.

- [ ] **Step 2: Run security and migration checks**

Run: npm audit --audit-level=high; python -m pip_audit --skip-editable; supabase db reset; supabase test db

Expected: no high-or-critical npm findings, no known audited Python vulnerability, and passing migration/RLS tests.

- [ ] **Step 3: Review the final diff and secrets**

Run: git diff --check main...HEAD; git diff --stat main...HEAD; rg -n --ignore-case 'service[_-]?role|api[_-]?key|password|token|postgres(ql)?://|supabase.*secret' supabase .github apps docs

Expected: no committed credential, raw identity, session material, or unrelated changes.

- [ ] **Step 4: Commit, push, and open the PR**

Use Conventional Commits, push feat/4-supabase-schema, and create a PR targeting main with Closes #4. Include exact validation evidence, RLS/role design, migration impact, and confirmation that no Storage policies or application authentication endpoints were added. Do not merge or deploy.

