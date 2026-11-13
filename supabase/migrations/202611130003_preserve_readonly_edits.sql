-- Preserve local offline edits as conflicts when edit permission is revoked.
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
     or jsonb_array_length(coalesce(p_changes, '[]'::jsonb)) > 100 then
    raise exception 'invalid_sync_batch';
  end if;

  -- A read-only device can pull remote changes, but never pushes stale local edits.
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
                            'permission', v_device.permission, 'role', v_device.role,
                            'has_more', (select exists(select 1 from public.bd_records r
                              where r.workspace_id = p_workspace_id and r.revision > v_cursor)));
end
$$;
revoke all on function public.bd_sync(uuid, uuid, text, jsonb, bigint, integer) from public;
grant execute on function public.bd_sync(uuid, uuid, text, jsonb, bigint, integer) to anon, authenticated;
