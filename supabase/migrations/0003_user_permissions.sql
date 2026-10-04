-- =====================================================================
-- Stock Pilot — Customizable Per-User Module Permissions
-- =====================================================================
-- Apply this in the Supabase Dashboard → SQL Editor (after 0002).
--
-- Adds a JSONB `permissions` column to `user_profiles` so admins can
-- customize exactly which modules each user can view, independent of
-- their coarse role. The role still provides a sensible default, but the
-- per-user permissions object is the source of truth the app checks.
--
-- Permission keys (all booleans):
--   inventory  - view/manage the Inventory module
--   customers  - view/manage the Customers module
--   orders     - view/manage the Orders module
--   payments   - view/manage the Payments module
--   settings   - view the Settings module (admin-style)
--
-- Note: the Dashboard/Overview is always available to every signed-in
-- user and is intentionally NOT part of this permission set.
--
-- All statements are idempotent so the script can be re-run safely.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Add the JSONB permissions column (defaults to empty object).
-- ---------------------------------------------------------------------
alter table public.user_profiles
  add column if not exists permissions jsonb not null default '{}'::jsonb;

-- ---------------------------------------------------------------------
-- 2. Helper: default permissions object for a given role.
--    - admin   : everything
--    - manager : inventory + customers + orders + payments
--    - staff   : orders + payments only
-- ---------------------------------------------------------------------
create or replace function public.default_permissions_for_role(p_role text)
returns jsonb
language sql
immutable
as $$
  select case p_role
    when 'admin' then jsonb_build_object(
      'inventory', true,
      'customers', true,
      'orders',    true,
      'payments',  true,
      'settings',  true
    )
    when 'manager' then jsonb_build_object(
      'inventory', true,
      'customers', true,
      'orders',    true,
      'payments',  true,
      'settings',  false
    )
    else jsonb_build_object(
      'inventory', false,
      'customers', false,
      'orders',    true,
      'payments',  true,
      'settings',  false
    )
  end;
$$;

-- ---------------------------------------------------------------------
-- 3. Backfill: give every existing profile a permissions object that
--    matches its current role, but only where it has not been
--    customized yet (i.e. still the empty default).
-- ---------------------------------------------------------------------
update public.user_profiles
set permissions = public.default_permissions_for_role(role)
where permissions = '{}'::jsonb;

-- ---------------------------------------------------------------------
-- 4. Recreate handle_new_user so new users also get a permissions
--    object. If the inviter supplied a `permissions` object in the user
--    metadata, that is used verbatim; otherwise defaults for the role.
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  assigned_role  text;
  existing_count int;
  assigned_perms jsonb;
begin
  select count(*) into existing_count from public.user_profiles;

  assigned_role := coalesce(
    nullif(new.raw_user_meta_data ->> 'role', ''),
    case when existing_count = 0 then 'admin' else 'staff' end
  );

  -- Prefer an explicit permissions object from metadata, else defaults.
  if (new.raw_user_meta_data ? 'permissions')
     and jsonb_typeof(new.raw_user_meta_data -> 'permissions') = 'object'
  then
    assigned_perms := new.raw_user_meta_data -> 'permissions';
  else
    assigned_perms := public.default_permissions_for_role(assigned_role);
  end if;

  insert into public.user_profiles (id, email, role, name, permissions)
  values (
    new.id,
    new.email,
    assigned_role,
    nullif(new.raw_user_meta_data ->> 'name', ''),
    assigned_perms
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- 5. (Optional convenience) Admin RPC to set a user's permissions.
--    The app can also just UPDATE the column directly (RLS already
--    permits admins to update any profile). This helper validates the
--    caller is an admin and merges the provided keys.
-- ---------------------------------------------------------------------
create or replace function public.set_user_permissions(
  p_user_id uuid,
  p_permissions jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can change permissions';
  end if;

  update public.user_profiles
  set permissions = coalesce(permissions, '{}'::jsonb) || p_permissions,
      updated_at  = now()
  where id = p_user_id;
end;
$$;