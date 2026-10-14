begin;

select plan(42);

select has_schema('app', 'creates the application schema');
select has_table('app', 'members', 'creates members');
select has_table('app', 'files', 'creates files');
select has_table('app', 'audit_events', 'creates audit events');
select has_table('app', 'sessions', 'creates sessions');
select ok(
  (select c.relrowsecurity from pg_class as c join pg_namespace as n on n.oid = c.relnamespace
   where n.nspname = 'app' and c.relname = 'members'),
  'enables RLS on members'
);
select ok(
  (select c.relrowsecurity from pg_class as c join pg_namespace as n on n.oid = c.relnamespace
   where n.nspname = 'app' and c.relname = 'files'),
  'enables RLS on files'
);
select ok(
  (select c.relrowsecurity from pg_class as c join pg_namespace as n on n.oid = c.relnamespace
   where n.nspname = 'app' and c.relname = 'audit_events'),
  'enables RLS on audit events'
);
select ok(
  (select c.relrowsecurity from pg_class as c join pg_namespace as n on n.oid = c.relnamespace
   where n.nspname = 'app' and c.relname = 'sessions'),
  'enables RLS on sessions'
);

select ok(
  not has_table_privilege('anon', 'app.files', 'select'),
  'anon has no direct file read privilege'
);
select ok(
  not has_table_privilege('authenticated', 'app.files', 'select'),
  'authenticated has no direct file read privilege'
);
select ok(
  has_table_privilege('mykeep_api', 'app.files', 'select'),
  'runtime role receives only the required file read grant'
);
select ok(
  not (select rolbypassrls from pg_roles where rolname = 'mykeep_api'),
  'runtime role cannot bypass RLS'
);
select ok(
  not (select rolcanlogin from pg_roles where rolname = 'mykeep_api'),
  'runtime role cannot log in directly'
);
select ok(
  not (select rolinherit from pg_roles where rolname = 'mykeep_api'),
  'runtime role does not inherit elevated privileges'
);

insert into app.members (id, lookup_hash, status) values
  ('11111111-1111-1111-1111-111111111111', decode(repeat('11', 32), 'hex'), 'enabled'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', decode(repeat('aa', 32), 'hex'), 'enabled'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', decode(repeat('dd', 32), 'hex'), 'disabled');

insert into app.files (
  id, member_id, original_name, display_name, mime_type, byte_size,
  checksum_sha256, storage_key
) values (
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  'disabled.txt', 'disabled.txt', 'text/plain', 0,
  decode(repeat('ee', 32), 'hex'),
  'members/dddddddd-dddd-dddd-dddd-dddddddddddd/eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee/blob'
);

insert into app.sessions (
  id, member_id, credential_hash, issued_at, expires_at, rotated_at, revoked_at,
  replacement_session_id
) values
  (
    '33333333-3333-3333-3333-333333333333',
    '11111111-1111-1111-1111-111111111111',
    decode(repeat('33', 32), 'hex'), clock_timestamp(), clock_timestamp() + interval '1 hour',
    null, null, null
  ),
  (
    '44444444-4444-4444-4444-444444444444',
    '11111111-1111-1111-1111-111111111111',
    decode(repeat('44', 32), 'hex'), clock_timestamp(), clock_timestamp() - interval '1 hour',
    null, null, null
  ),
  (
    '55555555-5555-5555-5555-555555555555',
    '11111111-1111-1111-1111-111111111111',
    decode(repeat('55', 32), 'hex'), clock_timestamp(), clock_timestamp() + interval '1 hour',
    null, clock_timestamp(), null
  ),
  (
    '66666666-6666-6666-6666-666666666666',
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    decode(repeat('66', 32), 'hex'), clock_timestamp(), clock_timestamp() + interval '1 hour',
    null, null, null
  ),
  (
    '77777777-7777-7777-7777-777777777777',
    '11111111-1111-1111-1111-111111111111',
    decode(repeat('77', 32), 'hex'), clock_timestamp(), clock_timestamp() + interval '1 hour',
    clock_timestamp(), null, '88888888-8888-8888-8888-888888888888'
  ),
  (
    '88888888-8888-8888-8888-888888888888',
    '11111111-1111-1111-1111-111111111111',
    decode(repeat('88', 32), 'hex'), clock_timestamp(), clock_timestamp() + interval '1 hour',
    null, null, null
  ),
  (
    '99999999-9999-9999-9999-999999999999',
    '11111111-1111-1111-1111-111111111111',
    decode(repeat('99', 32), 'hex'), clock_timestamp(), clock_timestamp() + interval '1 hour',
    null, null, null
  );

set local role mykeep_api;

select ok(app.current_member_id() is null, 'missing member context resolves to null');
select ok(app.current_lookup_hash() is null, 'missing lookup context resolves to null');
select ok(app.current_session_hash() is null, 'missing session context resolves to null');
select set_config('mykeep.lookup_hash', encode(decode(repeat('11', 32), 'hex'), 'hex'), true);
select ok(
  app.resolve_verified_lookup() is not distinct from '11111111-1111-1111-1111-111111111111'::uuid,
  'verified enabled lookup resolves a member UUID'
);
select set_config('mykeep.lookup_hash', encode(decode(repeat('dd', 32), 'hex'), 'hex'), true);
select ok(app.resolve_verified_lookup() is null, 'disabled lookup does not resolve a member UUID');

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
select throws_ok(
  $$insert into app.files (
      id, member_id, original_name, display_name, mime_type, byte_size,
      checksum_sha256, storage_key
    ) values (
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'other.txt', 'other.txt', 'text/plain', 0,
      decode(repeat('bc', 32), 'hex'),
      'members/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/blob'
    )$$,
  '42501',
  null,
  'member cannot create another member file'
);
select throws_ok(
  $$update app.files
      set member_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    where id = '22222222-2222-2222-2222-222222222222'$$,
  '42501',
  null,
  'member cannot reassign file ownership'
);
select throws_ok(
  $$insert into app.files (
      id, member_id, original_name, display_name, mime_type, byte_size,
      checksum_sha256, storage_key
    ) values (
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      '11111111-1111-1111-1111-111111111111',
      'bad.txt', 'bad.txt', 'text/plain', -1,
      decode(repeat('cd', 32), 'hex'),
      'invalid-key'
    )$$,
  '23514',
  null,
  'file constraints reject invalid metadata'
);
select throws_ok(
  $$insert into app.audit_events (event_type, outcome, request_id, actor_member_id)
      values ('authentication_failed', 'denied', '11111111-1111-1111-1111-111111111111',
              'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')$$,
  '42501',
  null,
  'runtime cannot attribute an audit event to another member'
);
select lives_ok(
  $$with replacement as (
      insert into app.sessions (id, member_id, credential_hash, issued_at, expires_at)
      values (
        'ffffffff-ffff-ffff-ffff-ffffffffffff',
        '11111111-1111-1111-1111-111111111111',
        decode(repeat('ff', 32), 'hex'), clock_timestamp(), clock_timestamp() + interval '1 hour'
      )
      returning id
    )
    update app.sessions as previous
    set rotated_at = clock_timestamp(), replacement_session_id = replacement.id
    from replacement
    where previous.id = '99999999-9999-9999-9999-999999999999'$$,
  'rotation atomically creates a replacement and retires the previous session'
);
select set_config('mykeep.member_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);
select ok(
  (select count(*) from app.files) = 0,
  'member B cannot read member A files'
);
select ok(
  (with changed as (
    update app.files
    set deleted_at = clock_timestamp()
    where id = '22222222-2222-2222-2222-222222222222'
    returning id
  ) select count(*) from changed) = 0,
  'member B cannot soft-delete member A file'
);
select set_config('mykeep.member_id', '11111111-1111-1111-1111-111111111111', true);
select lives_ok(
  $$update app.files
      set deleted_at = clock_timestamp()
    where id = '22222222-2222-2222-2222-222222222222'$$,
  'member can soft-delete an owned file'
);
select ok(
  (select count(*) from app.files) = 0,
  'soft-deleted files are hidden from normal listing'
);
select lives_ok(
  $$update app.files
      set deleted_at = null
    where id = '22222222-2222-2222-2222-222222222222'$$,
  'member can restore an owned file'
);
select set_config('mykeep.member_id', 'dddddddd-dddd-dddd-dddd-dddddddddddd', true);
select ok(
  (select count(*) from app.files) = 0,
  'disabled members cannot access files even if context is set incorrectly'
);
select set_config('mykeep.member_id', '', true);
select lives_ok(
  $$insert into app.audit_events (event_type, outcome, request_id, actor_member_id)
      values ('authentication_failed', 'denied', '22222222-2222-2222-2222-222222222222', null)$$,
  'runtime can append a bounded unauthenticated audit event'
);
select throws_ok(
  $$insert into app.audit_events (event_type, outcome, request_id, actor_member_id)
      values ('unbounded_payload', 'denied', '33333333-3333-3333-3333-333333333333', null)$$,
  '23514',
  null,
  'audit event type is bounded'
);

reset role;
select set_config('mykeep.member_id', '', true);
set local role mykeep_api;
select set_config('mykeep.session_hash', encode(decode(repeat('33', 32), 'hex'), 'hex'), true);
select ok(
  (select id from app.resolve_presented_session())
    is not distinct from '33333333-3333-3333-3333-333333333333'::uuid,
  'active session resolves through restricted runtime role'
);
select set_config('mykeep.session_hash', encode(decode(repeat('44', 32), 'hex'), 'hex'), true);
select ok((select id from app.resolve_presented_session()) is null, 'expired session does not resolve');
select set_config('mykeep.session_hash', encode(decode(repeat('55', 32), 'hex'), 'hex'), true);
select ok((select id from app.resolve_presented_session()) is null, 'revoked session does not resolve');
select set_config('mykeep.session_hash', encode(decode(repeat('66', 32), 'hex'), 'hex'), true);
select ok((select id from app.resolve_presented_session()) is null, 'disabled member session does not resolve');
select set_config('mykeep.session_hash', encode(decode(repeat('77', 32), 'hex'), 'hex'), true);
select ok((select id from app.resolve_presented_session()) is null, 'rotated session does not resolve');
select set_config('mykeep.session_hash', encode(decode(repeat('88', 32), 'hex'), 'hex'), true);
select ok(
  (select id from app.resolve_presented_session())
    is not distinct from '88888888-8888-8888-8888-888888888888'::uuid,
  'replacement session resolves after rotation'
);
select set_config('mykeep.session_hash', encode(decode(repeat('99', 32), 'hex'), 'hex'), true);
select ok((select id from app.resolve_presented_session()) is null, 'atomically rotated credential does not resolve');
select set_config('mykeep.session_hash', encode(decode(repeat('ff', 32), 'hex'), 'hex'), true);
select ok(
  (select id from app.resolve_presented_session())
    is not distinct from 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid,
  'atomically created replacement credential resolves'
);

select * from finish();
rollback;
