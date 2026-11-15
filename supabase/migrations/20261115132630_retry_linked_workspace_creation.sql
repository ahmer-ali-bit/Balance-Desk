-- Make owner-workspace creation safe to retry after a lost response. The
-- client retains the pending secret until local config is saved, so a repeated
-- call with that capability can recover the already-created owner workspace.
-- If an older interrupted attempt left the device UUID occupied by another
-- capability, allocate a new server-side UUID rather than failing the retry.
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
  v_existing_device public.bd_devices;
  v_token text;
  v_device_id uuid;
begin
  if length(coalesce(p_device_token, '')) < 40 then
    raise exception 'invalid_device_credential';
  end if;
  if p_name is null or length(trim(p_name)) not between 1 and 120 then
    raise exception 'invalid_workspace_name';
  end if;
  if p_device_name is null or length(trim(p_device_name)) not between 1 and 100 then
    raise exception 'invalid_device_name';
  end if;
  if p_platform not in ('android', 'ios', 'macos', 'windows', 'linux', 'web', 'unknown') then
    raise exception 'invalid_platform';
  end if;

  v_token := public.bd_token_hash(p_device_token);

  -- A caller proving possession of an existing owner capability is retrying
  -- an operation whose response was lost. Return its original workspace.
  select * into v_existing_device
    from public.bd_devices
   where token_hash = v_token;
  if found then
    if v_existing_device.role <> 'owner' or not v_existing_device.is_active then
      raise exception 'credential_already_registered';
    end if;
    select * into v_workspace
      from public.bd_workspaces
     where id = v_existing_device.workspace_id;
    if not found then
      raise exception 'workspace_unavailable';
    end if;
    return jsonb_build_object(
      'workspace_id', v_workspace.id,
      'workspace_name', v_workspace.name,
      'device_id', v_existing_device.id,
      'role', 'owner',
      'permission', v_existing_device.permission
    );
  end if;

  -- A prior client version may have persisted the UUID after the server
  -- committed but lost its response, then generated a new token on retry.
  -- Never take over that existing device; give this fresh capability a new ID.
  v_device_id := p_device_id;
  if exists (select 1 from public.bd_devices where id = v_device_id) then
    v_device_id := pg_catalog.gen_random_uuid();
  end if;

  insert into public.bd_workspaces(name)
    values (trim(p_name))
    returning * into v_workspace;
  insert into public.bd_devices(id, workspace_id, token_hash, name, platform, role)
    values (v_device_id, v_workspace.id, v_token, trim(p_device_name), p_platform, 'owner');

  return jsonb_build_object(
    'workspace_id', v_workspace.id,
    'workspace_name', v_workspace.name,
    'device_id', v_device_id,
    'role', 'owner',
    'permission', 'edit'
  );
end
$$;
