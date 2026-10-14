begin;

create schema if not exists app;
create extension if not exists pgcrypto with schema extensions;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'mykeep_api') then
    create role mykeep_api
      nologin
      noinherit
      nosuperuser
      nocreatedb
      nocreaterole
      noreplication
      nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'mykeep_file_lifecycle') then
    create role mykeep_file_lifecycle
      nologin
      noinherit
      nosuperuser
      nocreatedb
      nocreaterole
      noreplication
      bypassrls;
  end if;
end;
$$;

create type app.member_status as enum ('enabled', 'disabled');
create type app.audit_outcome as enum ('allowed', 'denied', 'failed');

create function app.current_member_id()
returns uuid
language sql
stable
security invoker
set search_path = pg_catalog
as $$
  select case
    when coalesce(current_setting('mykeep.member_id', true), '')
      ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then current_setting('mykeep.member_id', true)::uuid
    else null
  end
$$;

create function app.current_lookup_hash()
returns bytea
language sql
stable
security invoker
set search_path = pg_catalog
as $$
  select case
    when coalesce(current_setting('mykeep.lookup_hash', true), '') ~ '^[0-9a-f]{64}$'
    then decode(current_setting('mykeep.lookup_hash', true), 'hex')
    else null
  end
$$;

create function app.current_session_hash()
returns bytea
language sql
stable
security invoker
set search_path = pg_catalog
as $$
  select case
    when coalesce(current_setting('mykeep.session_hash', true), '') ~ '^[0-9a-f]{64}$'
    then decode(current_setting('mykeep.session_hash', true), 'hex')
    else null
  end
$$;

create table app.members (
  id uuid primary key default extensions.gen_random_uuid(),
  lookup_hash bytea not null unique,
  status app.member_status not null default 'enabled',
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint members_lookup_hash_size_check check (octet_length(lookup_hash) = 32)
);

create table app.files (
  id uuid primary key default extensions.gen_random_uuid(),
  member_id uuid not null references app.members(id),
  original_name text not null,
  display_name text not null,
  mime_type text not null,
  byte_size bigint not null,
  checksum_sha256 bytea not null,
  storage_key text not null unique,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz,
  constraint files_original_name_check check (length(original_name) between 1 and 255),
  constraint files_display_name_check check (length(display_name) between 1 and 255),
  constraint files_mime_type_check check (mime_type ~ '^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$'),
  constraint files_byte_size_check check (byte_size >= 0),
  constraint files_checksum_size_check check (octet_length(checksum_sha256) = 32),
  constraint files_storage_key_check
    check (storage_key = format('members/%s/%s/blob', member_id, id)),
  constraint files_deleted_at_check check (deleted_at is null or deleted_at >= created_at)
);

create table app.sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  member_id uuid not null references app.members(id),
  credential_hash bytea not null unique,
  issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  rotated_at timestamptz,
  revoked_at timestamptz,
  replacement_session_id uuid,
  constraint sessions_id_member_unique unique (id, member_id),
  constraint sessions_credential_hash_size_check check (octet_length(credential_hash) = 32),
  constraint sessions_expiry_after_issue_check check (expires_at > issued_at),
  constraint sessions_rotated_after_issue_check check (rotated_at is null or rotated_at >= issued_at),
  constraint sessions_revoked_after_issue_check check (revoked_at is null or revoked_at >= issued_at),
  constraint sessions_rotation_state_check
    check ((rotated_at is null) = (replacement_session_id is null)),
  constraint sessions_replacement_not_self_check
    check (replacement_session_id is null or replacement_session_id <> id),
  constraint sessions_replacement_same_member_fk
    foreign key (replacement_session_id, member_id)
    references app.sessions (id, member_id)
    deferrable initially deferred
);

create table app.audit_events (
  id uuid primary key default extensions.gen_random_uuid(),
  actor_member_id uuid references app.members(id) on delete set null,
  event_type text not null,
  outcome app.audit_outcome not null,
  request_id uuid not null,
  occurred_at timestamptz not null default clock_timestamp(),
  constraint audit_events_type_check check (
    event_type in (
      'authentication_failed', 'authentication_succeeded', 'session_revoked',
      'file_created', 'file_deleted', 'file_restored', 'file_downloaded'
    )
  )
);

create index files_active_member_created_idx
  on app.files (member_id, created_at desc)
  where deleted_at is null;
create index files_deleted_member_deleted_at_idx
  on app.files (member_id, deleted_at)
  where deleted_at is not null;
create index sessions_active_credential_idx
  on app.sessions (credential_hash)
  where revoked_at is null and rotated_at is null;
create index sessions_member_active_idx
  on app.sessions (member_id, expires_at)
  where revoked_at is null and rotated_at is null;
create index audit_events_actor_occurred_idx
  on app.audit_events (actor_member_id, occurred_at desc);

-- These SECURITY DEFINER functions are owned by the migration administrator.
-- They expose only a resolved UUID after applying the complete first- and
-- second-stage checks; the runtime role cannot modify their definitions.
create function app.resolve_verified_lookup()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, app
as $$
  select m.id
  from app.members as m
  where m.lookup_hash = app.current_lookup_hash()
    and m.status = 'enabled'
$$;

create function app.current_member_is_enabled()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, app
as $$
  select exists (
    select 1
    from app.members as m
    where m.id = app.current_member_id()
      and m.status = 'enabled'
  )
$$;

create function app.resolve_presented_session()
returns table (id uuid, member_id uuid)
language sql
volatile
security definer
set search_path = pg_catalog, app
as $$
  select s.id, s.member_id
  from app.sessions as s
  join app.members as m on m.id = s.member_id
  where s.credential_hash = app.current_session_hash()
    and m.status = 'enabled'
    and s.expires_at > clock_timestamp()
    and s.revoked_at is null
    and s.rotated_at is null
    and s.replacement_session_id is null
$$;

-- Deleted files are deliberately not selectable through the runtime role. This
-- fixed function is the only lifecycle path: it returns no row data, requires
-- the resolved enabled owner, and makes foreign, absent, or invalid-state
-- requests indistinguishable with a false result.
create function app.set_file_deleted_state(p_file_id uuid, p_delete boolean)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, app
as $$
declare
  changed boolean;
begin
  update app.files
  set deleted_at = case when p_delete then clock_timestamp() else null end,
      updated_at = clock_timestamp()
  where id = p_file_id
    and member_id = app.current_member_id()
    and app.current_member_is_enabled()
    and exists (
      select 1
      from app.resolve_presented_session() as session_context
      where session_context.member_id = app.current_member_id()
    )
    and case when p_delete then deleted_at is null else deleted_at is not null end
  returning true into changed;

  return coalesce(changed, false);
end;
$$;

revoke all on schema app from public, anon, authenticated;
revoke all on all tables in schema app from public, anon, authenticated;
revoke all on all sequences in schema app from public, anon, authenticated;
revoke all on all functions in schema app from public, anon, authenticated;
revoke all on type app.member_status, app.audit_outcome from public, anon, authenticated;

-- This non-login owner has only the file privileges needed by the fixed
-- lifecycle function. Its RLS bypass is confined to function execution;
-- neither the runtime role nor browser-facing roles can assume it.
grant usage, create on schema app to mykeep_file_lifecycle;
grant select, update on app.files to mykeep_file_lifecycle;
grant execute on function app.current_member_id() to mykeep_file_lifecycle;
grant execute on function app.current_member_is_enabled() to mykeep_file_lifecycle;
grant execute on function app.resolve_presented_session() to mykeep_file_lifecycle;
alter function app.set_file_deleted_state(uuid, boolean) owner to mykeep_file_lifecycle;
revoke create on schema app from mykeep_file_lifecycle;

grant usage on schema app to mykeep_api;
grant usage on type app.audit_outcome to mykeep_api;
grant select, insert, update on app.files to mykeep_api;
grant select, insert, update on app.sessions to mykeep_api;
grant insert on app.audit_events to mykeep_api;
grant execute on function app.current_member_id() to mykeep_api;
grant execute on function app.current_lookup_hash() to mykeep_api;
grant execute on function app.current_session_hash() to mykeep_api;
grant execute on function app.current_member_is_enabled() to mykeep_api;
grant execute on function app.resolve_verified_lookup() to mykeep_api;
grant execute on function app.resolve_presented_session() to mykeep_api;
grant execute on function app.set_file_deleted_state(uuid, boolean) to mykeep_api;

-- The Supabase migration/test administrator can assume the restricted role to
-- exercise RLS. This membership is deliberately one-way: mykeep_api cannot
-- assume postgres, and FastAPI never connects as postgres.
grant mykeep_api to postgres;

alter table app.members enable row level security;
alter table app.members force row level security;
alter table app.files enable row level security;
alter table app.files force row level security;
alter table app.sessions enable row level security;
alter table app.sessions force row level security;
alter table app.audit_events enable row level security;
alter table app.audit_events force row level security;

create policy members_no_runtime_access on app.members
  as restrictive
  for all to mykeep_api
  using (false)
  with check (false);

create policy files_select_owned_active on app.files
  for select to mykeep_api
  using (
    member_id = app.current_member_id()
    and app.current_member_is_enabled()
    and deleted_at is null
  );
create policy files_insert_owned on app.files
  for insert to mykeep_api
  with check (
    member_id = app.current_member_id()
    and app.current_member_is_enabled()
    and deleted_at is null
  );
create policy files_update_owned on app.files
  for update to mykeep_api
  using (member_id = app.current_member_id() and app.current_member_is_enabled())
  with check (
    member_id = app.current_member_id()
    and app.current_member_is_enabled()
    and deleted_at is null
  );
create policy files_delete_denied on app.files
  as restrictive
  for delete to mykeep_api
  using (false);

create policy sessions_select_owned on app.sessions
  for select to mykeep_api
  using (member_id = app.current_member_id() and app.current_member_is_enabled());
create policy sessions_insert_owned on app.sessions
  for insert to mykeep_api
  with check (member_id = app.current_member_id() and app.current_member_is_enabled());
create policy sessions_update_owned on app.sessions
  for update to mykeep_api
  using (member_id = app.current_member_id() and app.current_member_is_enabled())
  with check (member_id = app.current_member_id() and app.current_member_is_enabled());
create policy sessions_delete_denied on app.sessions
  as restrictive
  for delete to mykeep_api
  using (false);

create policy audit_events_insert_bounded on app.audit_events
  for insert to mykeep_api
  with check (
    (app.current_member_id() is null and actor_member_id is null)
    or (
      actor_member_id = app.current_member_id()
      and app.current_member_is_enabled()
    )
  );

commit;
