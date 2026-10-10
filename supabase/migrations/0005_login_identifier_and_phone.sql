-- =====================================================================
-- Stock Pilot — Flexible login (email / mobile / username) support.
-- =====================================================================
-- Apply this in the Supabase Dashboard → SQL Editor. All statements are
-- idempotent so the script can be re-run safely.
--
-- Overview
--  * Adds a `phone` column to user_profiles (captured at sign-up from the
--    user's auth metadata).
--  * Captures `phone` in the new-user trigger alongside company_code and
--    username.
--  * Adds an `email_for_identifier(text)` RPC that resolves a username OR
--    mobile number OR email to the account email, used by the single-field
--    login screen.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. user_profiles: phone column + unique index
-- ---------------------------------------------------------------------
alter table public.user_profiles
  add column if not exists phone text;

-- Phone numbers must be unique when present.
create unique index if not exists uq_user_profiles_phone
  on public.user_profiles (phone)
  where phone is not null;

-- ---------------------------------------------------------------------
-- 2. Capture phone in the new-user trigger.
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
  v_phone text;
  v_active boolean;
begin
  select count(*) into existing_count from public.user_profiles;

  v_company  := nullif(new.raw_user_meta_data ->> 'company_code', '');
  v_username := nullif(new.raw_user_meta_data ->> 'username', '');
  v_phone    := nullif(new.raw_user_meta_data ->> 'phone', '');

  assigned_role := coalesce(
    nullif(new.raw_user_meta_data ->> 'role', ''),
    case when existing_count = 0 then 'admin' else 'staff' end
  );

  -- First user bootstraps as an active admin; all others start inactive.
  v_active := (existing_count = 0);

  insert into public.user_profiles
    (id, email, role, name, company_code, username, phone, is_active)
  values (
    new.id,
    new.email,
    assigned_role,
    nullif(new.raw_user_meta_data ->> 'name', ''),
    v_company,
    v_username,
    v_phone,
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
-- 3. Resolve a username OR mobile number OR email to the account email.
--    Callable by anonymous users (the login screen) so it is SECURITY
--    DEFINER and only returns the email, nothing else.
-- ---------------------------------------------------------------------
create or replace function public.email_for_identifier(p_identifier text)
returns text
language sql
security definer
set search_path = public
as $$
  select email from public.user_profiles
  where lower(username) = lower(p_identifier)
     or phone = p_identifier
     or lower(email) = lower(p_identifier)
  limit 1;
$$;

grant execute on function public.email_for_identifier(text)
  to anon, authenticated;