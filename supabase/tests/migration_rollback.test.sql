select plan(4);

-- The disposable pgTAP database must make its assertion extension visible to
-- the restricted role. This grant is revoked before the test connection ends.
grant usage on schema extensions to mykeep_api;

begin;
set local role mykeep_api;
select set_config('mykeep.member_id', '11111111-1111-1111-1111-111111111111', true);
select ok(
  app.current_member_id() is not distinct from '11111111-1111-1111-1111-111111111111'::uuid,
  'transaction-local member context is available inside its transaction'
);
commit;

select ok(
  app.current_member_id() is null,
  'member context is cleared after commit on the same connection'
);

begin;
set local role mykeep_api;
select set_config('mykeep.member_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);
select ok(
  app.current_member_id() is not distinct from 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
  'a later transaction can set a different member context'
);
rollback;

select ok(
  app.current_member_id() is null,
  'member context is cleared after rollback on the same connection'
);

revoke usage on schema extensions from mykeep_api;
select * from finish();
