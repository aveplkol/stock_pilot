-- =====================================================================
-- Stock Pilot — Multi-tenancy (company codes), username login,
-- admin activation, and username→email resolution.
-- =====================================================================
-- Apply this in the Supabase Dashboard → SQL Editor. All statements are
-- idempotent so the script can be re-run safely.
--
-- Overview
--  * Adds a `company_code` (string) to user_profiles and every data table.
--  * New registrations are inactive until an admin activates them.
--  * Users may sign in by username (resolved to their email server-side).
--  * RLS is tightened so users only see rows for THEIR company_code.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. user_profiles: company_code, username, is_active
-- ---------------------------------------------------------------------
alter table public.user_profiles
  add column if not exists company_code text,
  add column if not exists username     text,
  add column if not exists is_active     boolean not null default false;

-- Usernames must be unique when present.
create unique index if not exists uq_user_profiles_username
  on public.user_profiles (lower(username))
  where username is not null;

-- Fast lookups by company.
create index if not exists idx_user_profiles_company
  on public.user_profiles (company_code);

-- ---------------------------------------------------------------------
-- 2. company_code on all data tables
-- ---------------------------------------------------------------------
do $$
declare
  t text;
  tables text[] := array[
    'societies','categories','inventory_items','stock_transactions',
    'customers','orders','order_items','payments'
  ];
begin
  foreach t in array tables loop
    execute format(
      'alter table public.%I add column if not exists company_code text;', t
    );
    execute format(
      'create index if not exists idx_%s_company on public.%I (company_code);',
      t, t
    );
  end loop;
end $$;

-- Also add the inventory icon column used by the app (safe if present).
alter table public.inventory_items
  add column if not exists icon_name text;

-- ---------------------------------------------------------------------
-- 3. Helper functions
-- ---------------------------------------------------------------------

-- Current user's company_code (SECURITY DEFINER avoids RLS recursion).
create or replace function public.current_company_code()
returns text
language sql
security definer
set search_path = public
as $$
  select company_code from public.user_profiles where id = auth.uid();
$$;

-- Is the current user an active admin?
create or replace function public.is_active_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_profiles
    where id = auth.uid() and role = 'admin' and is_active = true
  );
$$;

-- Resolve a username to its email for the username login flow. Callable by
-- anonymous users (the login screen) so it is SECURITY DEFINER and only
-- returns the email, nothing else.
create or replace function public.email_for_username(p_username text)
returns text
language sql
security definer
set search_path = public
as $$
  select email from public.user_profiles
  where lower(username) = lower(p_username)
  limit 1;
$$;

grant execute on function public.email_for_username(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. New-user trigger: capture company_code + username from metadata,
--    keep the very first user as an active admin, everyone else inactive
--    until an admin activates them.
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  assigned_role text;
  existing_count int;
  v_company text;
  v_username text;
  v_active boolean;
begin
  select count(*) into existing_count from public.user_profiles;

  v_company  := nullif(new.raw_user_meta_data ->> 'company_code', '');
  v_username := nullif(new.raw_user_meta_data ->> 'username', '');

  assigned_role := coalesce(
    nullif(new.raw_user_meta_data ->> 'role', ''),
    case when existing_count = 0 then 'admin' else 'staff' end
  );

  -- First user bootstraps as an active admin; all others start inactive.
  v_active := (existing_count = 0);

  insert into public.user_profiles
    (id, email, role, name, company_code, username, is_active)
  values (
    new.id,
    new.email,
    assigned_role,
    nullif(new.raw_user_meta_data ->> 'name', ''),
    v_company,
    v_username,
    v_active
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
-- 5. Admin activation API: activate/deactivate users within the admin's
--    own company only.
-- ---------------------------------------------------------------------
create or replace function public.set_user_active(
  p_user_id uuid,
  p_active  boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_active_admin() then
    raise exception 'Only an active admin may change activation';
  end if;

  update public.user_profiles
     set is_active = p_active,
         updated_at = now()
   where id = p_user_id
     and company_code is not distinct from public.current_company_code();
end;
$$;

grant execute on function public.set_user_active(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------------
-- 6. Tighten user_profiles RLS: company isolation + activation.
-- ---------------------------------------------------------------------
drop policy if exists "user_profiles_select_own" on public.user_profiles;
create policy "user_profiles_select_own" on public.user_profiles
  for select
  using (
    auth.uid() = id
    or (
      public.is_active_admin()
      and company_code is not distinct from public.current_company_code()
    )
  );

-- ---------------------------------------------------------------------
-- 7. Per-table RLS: a user may only read/write rows for their own
--    company_code. Applies to all data tables. These policies replace
--    any prior user_id-only policies for SELECT/INSERT/UPDATE/DELETE.
--
--    New rows must carry the caller's company_code (enforced in WITH CHECK).
-- ---------------------------------------------------------------------
do $$
declare
  t text;
  tables text[] := array[
    'societies','categories','inventory_items','stock_transactions',
    'customers','orders','order_items','payments'
  ];
begin
  foreach t in array tables loop
    execute format('alter table public.%I enable row level security;', t);

    execute format('drop policy if exists "%s_company_select" on public.%I;', t, t);
    execute format(
      'create policy "%s_company_select" on public.%I for select using '
      '(company_code is not distinct from public.current_company_code());',
      t, t
    );

    execute format('drop policy if exists "%s_company_insert" on public.%I;', t, t);
    execute format(
      'create policy "%s_company_insert" on public.%I for insert with check '
      '(company_code is not distinct from public.current_company_code());',
      t, t
    );

    execute format('drop policy if exists "%s_company_update" on public.%I;', t, t);
    execute format(
      'create policy "%s_company_update" on public.%I for update using '
      '(company_code is not distinct from public.current_company_code()) '
      'with check (company_code is not distinct from public.current_company_code());',
      t, t
    );

    execute format('drop policy if exists "%s_company_delete" on public.%I;', t, t);
    execute format(
      'create policy "%s_company_delete" on public.%I for delete using '
      '(company_code is not distinct from public.current_company_code());',
      t, t
    );
  end loop;
end $$;

-- =====================================================================
-- NOTE: Backfilling company_code for existing rows
-- ---------------------------------------------------------------------
-- If you already have data, assign a company_code to existing users and
-- rows before relying on the policies above, e.g.:
--
--   update public.user_profiles set company_code = 'COMP001',
--     is_active = true where company_code is null;
--   update public.inventory_items set company_code = 'COMP001'
--     where company_code is null;  -- repeat per table
-- =====================================================================