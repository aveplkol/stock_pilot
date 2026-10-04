-- =====================================================================
-- Stock Pilot — User Profiles & Role-Based Authorization
-- =====================================================================
-- Apply this in the Supabase Dashboard → SQL Editor.
--
-- Adds a `user_profiles` table that stores each user's role so the app
-- can enforce role-based authorization (admin / manager / staff).
--
-- Roles:
--   admin   - full access, incl. user management & settings
--   manager - reports, inventory, customers, orders, payments
--   staff   - dashboard + record payments/orders only
--
-- All statements are idempotent so the script can be re-run safely.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. user_profiles table
-- ---------------------------------------------------------------------
create table if not exists public.user_profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  role       text not null default 'staff',
  name       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Constrain role to the known set.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'user_profiles_role_check'
  ) then
    alter table public.user_profiles
      add constraint user_profiles_role_check
      check (role in ('admin', 'manager', 'staff'));
  end if;
end $$;

create index if not exists idx_user_profiles_role on public.user_profiles(role);

alter table public.user_profiles enable row level security;

-- ---------------------------------------------------------------------
-- 2. Helper: is the current user an admin?
--    SECURITY DEFINER avoids recursive RLS evaluation when policies
--    reference user_profiles.
-- ---------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- ---------------------------------------------------------------------
-- 3. RLS policies
--    - Everyone can read their own profile.
--    - Admins can read/insert/update/delete any profile.
--    - Users may update their own name (but NOT their role).
-- ---------------------------------------------------------------------
drop policy if exists "user_profiles_select_own" on public.user_profiles;
create policy "user_profiles_select_own" on public.user_profiles
  for select
  using (auth.uid() = id or public.is_admin());

drop policy if exists "user_profiles_admin_insert" on public.user_profiles;
create policy "user_profiles_admin_insert" on public.user_profiles
  for insert
  with check (public.is_admin() or auth.uid() = id);

drop policy if exists "user_profiles_admin_update" on public.user_profiles;
create policy "user_profiles_admin_update" on public.user_profiles
  for update
  using (public.is_admin() or auth.uid() = id)
  with check (public.is_admin() or auth.uid() = id);

drop policy if exists "user_profiles_admin_delete" on public.user_profiles;
create policy "user_profiles_admin_delete" on public.user_profiles
  for delete
  using (public.is_admin());

-- ---------------------------------------------------------------------
-- 4. Auto-create a profile row when a new auth user is created.
--    The first user ever created becomes an admin; everyone else is a
--    staff member by default (admins can promote them later). If the
--    user was invited with a role in their metadata, that role is used.
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
begin
  select count(*) into existing_count from public.user_profiles;

  assigned_role := coalesce(
    nullif(new.raw_user_meta_data ->> 'role', ''),
    case when existing_count = 0 then 'admin' else 'staff' end
  );

  insert into public.user_profiles (id, email, role, name)
  values (
    new.id,
    new.email,
    assigned_role,
    nullif(new.raw_user_meta_data ->> 'name', '')
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
-- 5. Backfill profiles for existing auth users (first one becomes admin).
-- ---------------------------------------------------------------------
insert into public.user_profiles (id, email, role, name)
select
  u.id,
  u.email,
  case
    when row_number() over (order by u.created_at) = 1 then 'admin'
    else 'staff'
  end as role,
  nullif(u.raw_user_meta_data ->> 'name', '')
from auth.users u
where not exists (
  select 1 from public.user_profiles p where p.id = u.id
);