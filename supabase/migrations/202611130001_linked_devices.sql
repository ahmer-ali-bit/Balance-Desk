-- Balance Desk linked workspaces — capability-based device auth.
-- No service-role key is shipped in the client. Data tables have no client
-- grants; clients can only use the narrow SECURITY DEFINER RPCs below, each of
-- which validates a per-install 256-bit capability whose SHA-256 hash is stored.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.bd_workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 120),
  created_at timestamptz not null default now()
);

create table if not exists public.bd_devices (
  id uuid primary key,
  workspace_id uuid not null references public.bd_workspaces(id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  name text not null check (char_length(name) between 1 and 100),
  platform text not null check (platform in ('android', 'ios', 'macos', 'windows', 'linux', 'web', 'unknown')),
  role text not null check (role in ('owner', 'linked')),
  permission text not null default 'edit' check (permission in ('edit', 'read_only')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz
);
create index if not exists bd_devices_workspace_active_idx
  on public.bd_devices(workspace_id, is_active, created_at);

create table if not exists public.bd_invites (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.bd_workspaces(id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references public.bd_devices(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  claimed_at timestamptz,
  claimed_by uuid
);
create index if not exists bd_invites_expiry_idx on public.bd_invites(expires_at);

create table if not exists public.bd_records (
  workspace_id uuid not null references public.bd_workspaces(id) on delete cascade,
  entity text not null check (entity in ('customers', 'entries', 'summary_snapshots', 'ledger_years', 'app_settings')),
  record_id text not null check (char_length(record_id) between 1 and 160),
  payload jsonb not null default '{}'::jsonb,
  is_deleted boolean not null default false,
  revision bigint generated always as identity,
  updated_at timestamptz not null default now(),
  changed_by uuid not null references public.bd_devices(id),
  primary key (workspace_id, entity, record_id)
);
create index if not exists bd_records_pull_idx on public.bd_records(workspace_id, revision);

alter table public.bd_workspaces enable row level security;
alter table public.bd_devices enable row level security;
alter table public.bd_invites enable row level security;
alter table public.bd_records enable row level security;
revoke all on public.bd_workspaces, public.bd_devices, public.bd_invites, public.bd_records from public, anon, authenticated;

create or replace function public.bd_token_hash(p_token text)
returns text
language sql immutable strict
set search_path = ''
as $$
  select encode(extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'), 'hex')
$$;
revoke all on function public.bd_token_hash(text) from public, anon, authenticated;

create or replace function public.bd_create_workspace(
  p_name text,
  p_device_id uuid,
  p_device_token text,
  p_device_name text,
  p_platform text
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_workspace public.bd_workspaces;
  v_token text;
begin
  if length(coalesce(p_device_token, '')) < 40 then raise exception 'invalid_device_credential'; end if;
  if p_name is null or length(trim(p_name)) not between 1 and 120 then raise exception 'invalid_workspace_name'; end if;
  if p_device_name is null or length(trim(p_device_name)) not between 1 and 100 then raise exception 'invalid_device_name'; end if;
  if p_platform not in ('android', 'ios', 'macos', 'windows', 'linux', 'web', 'unknown') then raise exception 'invalid_platform'; end if;
  v_token := public.bd_token_hash(p_device_token);
  if exists (select 1 from public.bd_devices d where d.token_hash = v_token) then raise exception 'credential_already_registered'; end if;

  insert into public.bd_workspaces(name) values (trim(p_name)) returning * into v_workspace;
  insert into public.bd_devices(id, workspace_id, token_hash, name, platform, role)
    values (p_device_id, v_workspace.id, v_token, trim(p_device_name), p_platform, 'owner');
  return jsonb_build_object('workspace_id', v_workspace.id, 'workspace_name', v_workspace.name,
                            'device_id', p_device_id, 'role', 'owner', 'permission', 'edit');
end
$$;

create or replace function public.bd_issue_invite(
  p_workspace_id uuid,
  p_device_id uuid,
  p_device_token text,
  p_invite_token text
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare v_device public.bd_devices; v_expires timestamptz;
begin
  select * into v_device from public.bd_devices
   where id = p_device_id and workspace_id = p_workspace_id
     and token_hash = public.bd_token_hash(p_device_token) and is_active for update;
  if not found or v_device.role <> 'owner' then raise exception 'owner_device_required'; end if;
  if length(coalesce(p_invite_token, '')) < 28 then raise exception 'invalid_invite_secret'; end if;
  v_expires := now() + interval '5 minutes';
  insert into public.bd_invites(workspace_id, token_hash, created_by, expires_at)
    values (p_workspace_id, public.bd_token_hash(p_invite_token), p_device_id, v_expires);
  update public.bd_devices set last_seen_at = now() where id = p_device_id;
  return jsonb_build_object('expires_at', v_expires);
end
$$;

create or replace function public.bd_claim_invite(
  p_invite_token text,
  p_device_id uuid,
  p_device_token text,
  p_device_name text,
  p_platform text
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare v_invite public.bd_invites; v_workspace public.bd_workspaces; v_token text;
begin
  if length(coalesce(p_device_token, '')) < 40 then raise exception 'invalid_device_credential'; end if;
  if p_device_name is null or length(trim(p_device_name)) not between 1 and 100 then raise exception 'invalid_device_name'; end if;
  if p_platform not in ('android', 'ios', 'macos', 'windows', 'linux', 'web', 'unknown') then raise exception 'invalid_platform'; end if;
  v_token := public.bd_token_hash(p_device_token);
  if exists (select 1 from public.bd_devices d where d.token_hash = v_token or d.id = p_device_id) then raise exception 'device_already_registered'; end if;

  update public.bd_invites
     set claimed_at = now(), claimed_by = p_device_id
   where id = (
     select i.id from public.bd_invites i
      where i.token_hash = public.bd_token_hash(p_invite_token)
        and i.claimed_at is null and i.expires_at > now()
      for update skip locked limit 1
   )
   returning * into v_invite;
  if not found then raise exception 'invite_invalid_expired_or_used'; end if;

  select * into v_workspace from public.bd_workspaces where id = v_invite.workspace_id;
  if not found then raise exception 'workspace_unavailable'; end if;
  insert into public.bd_devices(id, workspace_id, token_hash, name, platform, role)
    values (p_device_id, v_workspace.id, v_token, trim(p_device_name), p_platform, 'linked');
  return jsonb_build_object('workspace_id', v_workspace.id, 'workspace_name', v_workspace.name,
                            'device_id', p_device_id, 'role', 'linked', 'permission', 'edit');
end
$$;

create or replace function public.bd_list_devices(
  p_workspace_id uuid, p_device_id uuid, p_device_token text
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare v_device public.bd_devices;
begin
  select * into v_device from public.bd_devices
   where id = p_device_id and workspace_id = p_workspace_id
     and token_hash = public.bd_token_hash(p_device_token) and is_active;
  if not found or v_device.role <> 'owner' then raise exception 'owner_device_required'; end if;
  update public.bd_devices set last_seen_at = now() where id = p_device_id;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', d.id, 'name', d.name, 'platform', d.platform, 'role', d.role,
    'permission', d.permission, 'is_active', d.is_active, 'created_at', d.created_at,
    'last_seen_at', d.last_seen_at, 'revoked_at', d.revoked_at
  ) order by d.created_at) from public.bd_devices d where d.workspace_id = p_workspace_id), '[]'::jsonb);
end
$$;

create or replace function public.bd_set_device_permission(
  p_workspace_id uuid, p_device_id uuid, p_device_token text,
  p_target_device_id uuid, p_permission text
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare v_owner public.bd_devices;
begin
  select * into v_owner from public.bd_devices
   where id = p_device_id and workspace_id = p_workspace_id
     and token_hash = public.bd_token_hash(p_device_token) and is_active;
  if not found or v_owner.role <> 'owner' then raise exception 'owner_device_required'; end if;
  if p_permission not in ('edit', 'read_only') then raise exception 'invalid_permission'; end if;
  update public.bd_devices set permission = p_permission
   where id = p_target_device_id and workspace_id = p_workspace_id
     and role <> 'owner' and is_active;
  if not found then raise exception 'device_not_found'; end if;
  return jsonb_build_object('ok', true);
end
$$;

create or replace function public.bd_revoke_device(
  p_workspace_id uuid, p_device_id uuid, p_device_token text,
  p_target_device_id uuid
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare v_owner public.bd_devices;
begin
  select * into v_owner from public.bd_devices
   where id = p_device_id and workspace_id = p_workspace_id
     and token_hash = public.bd_token_hash(p_device_token) and is_active;
  if not found or v_owner.role <> 'owner' then raise exception 'owner_device_required'; end if;
  update public.bd_devices set is_active = false, revoked_at = now()
   where id = p_target_device_id and workspace_id = p_workspace_id
     and role <> 'owner' and is_active;
  if not found then raise exception 'device_not_found'; end if;
  return jsonb_build_object('ok', true);
end
$$;

create or replace function public.bd_sync(
  p_workspace_id uuid,
  p_device_id uuid,
  p_device_token text,
  p_changes jsonb,
  p_cursor bigint default 0,
  p_limit integer default 300
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_device public.bd_devices;
  v_change jsonb;
  v_existing public.bd_records;
  v_ack jsonb := '[]'::jsonb;
  v_conflicts jsonb := '[]'::jsonb;
  v_changes jsonb := '[]'::jsonb;
  v_row public.bd_records;
  v_rev bigint;
  v_limit integer := least(greatest(coalesce(p_limit, 300), 1), 500);
  v_cursor bigint := greatest(coalesce(p_cursor, 0), 0);
begin
  select * into v_device from public.bd_devices
   where id = p_device_id and workspace_id = p_workspace_id
     and token_hash = public.bd_token_hash(p_device_token) and is_active for update;
  if not found then raise exception 'device_revoked_or_invalid'; end if;
  if jsonb_typeof(coalesce(p_changes, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_changes, '[]'::jsonb)) > 100 then raise exception 'invalid_sync_batch'; end if;
  -- A newly read-only device can still pull while any stale offline changes
  -- remain local. They are never uploaded, and permission is returned below so
  -- the client can immediately enforce its local write guard.
  if v_device.permission <> 'read_only' then
  for v_change in select value from jsonb_array_elements(coalesce(p_changes, '[]'::jsonb))
  loop
    if v_change->>'entity' not in ('customers', 'entries', 'summary_snapshots', 'ledger_years', 'app_settings')
       or coalesce(length(v_change->>'record_id'), 0) not between 1 and 160
       or jsonb_typeof(v_change->'payload') is distinct from 'object'
       or jsonb_typeof(v_change->'is_deleted') is distinct from 'boolean' then
      raise exception 'invalid_sync_record';
    end if;

    select * into v_existing from public.bd_records r
     where r.workspace_id = p_workspace_id
       and r.entity = v_change->>'entity'
       and r.record_id = v_change->>'record_id'
     for update;
    v_rev := coalesce((v_change->>'base_revision')::bigint, 0);

    if (not found and v_rev <> 0) or (found and v_existing.revision <> v_rev) then
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'entity', v_change->>'entity', 'record_id', v_change->>'record_id',
        'cloud', case when found then jsonb_build_object(
          'payload', v_existing.payload, 'is_deleted', v_existing.is_deleted,
          'revision', v_existing.revision, 'updated_at', v_existing.updated_at
        ) else null end
      ));
    else
      insert into public.bd_records(workspace_id, entity, record_id, payload, is_deleted, changed_by)
      values (p_workspace_id, v_change->>'entity', v_change->>'record_id',
              v_change->'payload', (v_change->>'is_deleted')::boolean, p_device_id)
      on conflict (workspace_id, entity, record_id) do update
        set payload = excluded.payload,
            is_deleted = excluded.is_deleted,
            revision = nextval(pg_get_serial_sequence('public.bd_records', 'revision')::regclass),
            updated_at = now(), changed_by = p_device_id
      returning revision into v_rev;
      v_ack := v_ack || jsonb_build_array(jsonb_build_object(
        'entity', v_change->>'entity', 'record_id', v_change->>'record_id', 'revision', v_rev
      ));
    end if;
  end loop;
  else
    -- Permission may have been downgraded while this device was offline. Keep
    -- its unpushed local version visible as a conflict instead of overwriting it.
    for v_change in select value from jsonb_array_elements(coalesce(p_changes, '[]'::jsonb))
    loop
      if v_change->>'entity' not in ('customers', 'entries', 'summary_snapshots', 'ledger_years', 'app_settings')
         or coalesce(length(v_change->>'record_id'), 0) not between 1 and 160
         or jsonb_typeof(v_change->'payload') is distinct from 'object'
         or jsonb_typeof(v_change->'is_deleted') is distinct from 'boolean' then
        raise exception 'invalid_sync_record';
      end if;
      select * into v_existing from public.bd_records r
       where r.workspace_id = p_workspace_id
         and r.entity = v_change->>'entity'
         and r.record_id = v_change->>'record_id';
      v_conflicts := v_conflicts || jsonb_build_array(jsonb_build_object(
        'entity', v_change->>'entity', 'record_id', v_change->>'record_id',
        'cloud', case when found then jsonb_build_object(
          'payload', v_existing.payload, 'is_deleted', v_existing.is_deleted,
          'revision', v_existing.revision, 'updated_at', v_existing.updated_at
        ) else jsonb_build_object(
          'payload', '{}'::jsonb, 'is_deleted', true, 'revision', 0
        ) end
      ));
    end loop;
  end if;

  for v_row in
    select * from public.bd_records r
     where r.workspace_id = p_workspace_id and r.revision > v_cursor
     order by r.revision asc limit v_limit
  loop
    v_changes := v_changes || jsonb_build_array(jsonb_build_object(
      'entity', v_row.entity, 'record_id', v_row.record_id, 'payload', v_row.payload,
      'is_deleted', v_row.is_deleted, 'revision', v_row.revision,
      'updated_at', v_row.updated_at, 'changed_by', v_row.changed_by
    ));
    v_cursor := greatest(v_cursor, v_row.revision);
  end loop;

  update public.bd_devices set last_seen_at = now() where id = p_device_id;
  return jsonb_build_object('accepted', v_ack, 'conflicts', v_conflicts,
                            'changes', v_changes, 'cursor', v_cursor,
                            'permission', v_device.permission,
                            'has_more', (select exists(select 1 from public.bd_records r
                              where r.workspace_id = p_workspace_id and r.revision > v_cursor)));
end
$$;

create or replace function public.bd_stop_sharing(
  p_workspace_id uuid, p_device_id uuid, p_device_token text
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare v_device public.bd_devices;
begin
  select * into v_device from public.bd_devices
   where id = p_device_id and workspace_id = p_workspace_id
     and token_hash = public.bd_token_hash(p_device_token) and is_active for update;
  if not found or v_device.role <> 'owner' then raise exception 'owner_device_required'; end if;
  delete from public.bd_workspaces where id = p_workspace_id;
  return jsonb_build_object('ok', true);
end
$$;

create or replace function public.bd_leave_workspace(
  p_workspace_id uuid, p_device_id uuid, p_device_token text
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare v_device public.bd_devices;
begin
  select * into v_device from public.bd_devices
   where id = p_device_id and workspace_id = p_workspace_id
     and token_hash = public.bd_token_hash(p_device_token) and is_active for update;
  if not found or v_device.role <> 'linked' then raise exception 'linked_device_required'; end if;
  update public.bd_devices set is_active = false, revoked_at = now() where id = p_device_id;
  return jsonb_build_object('ok', true);
end
$$;

-- Grant only the capability-checked entry points. The hash helper and all data
-- tables remain inaccessible through PostgREST.
revoke all on function public.bd_create_workspace(text, uuid, text, text, text) from public;
revoke all on function public.bd_issue_invite(uuid, uuid, text, text) from public;
revoke all on function public.bd_claim_invite(text, uuid, text, text, text) from public;
revoke all on function public.bd_list_devices(uuid, uuid, text) from public;
revoke all on function public.bd_set_device_permission(uuid, uuid, text, uuid, text) from public;
revoke all on function public.bd_revoke_device(uuid, uuid, text, uuid) from public;
revoke all on function public.bd_sync(uuid, uuid, text, jsonb, bigint, integer) from public;
revoke all on function public.bd_stop_sharing(uuid, uuid, text) from public;
revoke all on function public.bd_leave_workspace(uuid, uuid, text) from public;
grant execute on function public.bd_create_workspace(text, uuid, text, text, text) to anon, authenticated;
grant execute on function public.bd_issue_invite(uuid, uuid, text, text) to anon, authenticated;
grant execute on function public.bd_claim_invite(text, uuid, text, text, text) to anon, authenticated;
grant execute on function public.bd_list_devices(uuid, uuid, text) to anon, authenticated;
grant execute on function public.bd_set_device_permission(uuid, uuid, text, uuid, text) to anon, authenticated;
grant execute on function public.bd_revoke_device(uuid, uuid, text, uuid) to anon, authenticated;
grant execute on function public.bd_sync(uuid, uuid, text, jsonb, bigint, integer) to anon, authenticated;
grant execute on function public.bd_stop_sharing(uuid, uuid, text) to anon, authenticated;
grant execute on function public.bd_leave_workspace(uuid, uuid, text) to anon, authenticated;
