-- =====================================================================
-- Stock Pilot — Create / promote a SUPER ADMIN user profile
-- =====================================================================
-- Run this in the Supabase Dashboard → SQL Editor.
--
-- A "super admin" in this app = user_profiles.role = 'admin' AND
-- is_active = true. That combination unlocks User Management, Settings,
-- and the admin activation API (see is_active_admin()).
--
-- IMPORTANT: user_profiles.id references auth.users(id). So the person
-- must FIRST have an auth account. Create it one of these ways:
--   • Supabase Dashboard → Authentication → Users → "Add user"
--     (set email + password, and tick "Auto Confirm User"), OR
--   • Have them sign up once in the app.
--
-- Then run the block below to make that account a super admin. It will
-- INSERT the profile if missing, or UPDATE it if it already exists.
-- =====================================================================

-- 👇 EDIT THESE TWO VALUES before running.
--    - p_email        : the login email of the auth user to promote
--    - p_company_code : the company/tenant this admin owns
do $$
declare
  p_email        text := 'abhishek00555.com';   -- <-- change me
  p_company_code text := 'SATYA';             -- <-- change me
  v_user_id      uuid;
begin
  -- Find the auth user id for the given email.
  select id into v_user_id
  from auth.users
  where lower(email) = lower(p_email)
  limit 1;

  if v_user_id is null then
    raise exception
      'No auth user found for %. Create the account first (Authentication → Users).',
      p_email;
  end if;

  -- Insert the profile if it doesn't exist, else promote it in place.
  insert into public.user_profiles (id, email, role, name, company_code, is_active)
  values (v_user_id, p_email, 'admin', 'Super Admin', p_company_code, true)
  on conflict (id) do update
    set role         = 'admin',
        is_active    = true,
        company_code = excluded.company_code,
        updated_at   = now();

  raise notice 'Super admin ready: % (company %)', p_email, p_company_code;
end $$;

-- Verify.
select id, email, role, is_active, company_code
from public.user_profiles
where lower(email) = lower('admin@example.com');  -- <-- match p_email above