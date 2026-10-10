-- =====================================================================
-- Stock Pilot — DELETE all records from all tables (RLS-safe)
-- =====================================================================
-- ⚠️  DANGER: This permanently deletes EVERY row in these tables for ALL
--     users. Table structures, columns, indexes and RLS policies are kept.
--     Run this in the Supabase Dashboard → SQL Editor.
--
-- Why disable RLS first?
--   With Row Level Security enabled, a plain DELETE only removes rows the
--   current user owns (auth.uid() = user_id), so it can appear to "run"
--   but leave data behind. The SQL Editor runs as the table owner, so we
--   temporarily DISABLE RLS, delete everything, then RE-ENABLE it to keep
--   your security rules intact.
--
--   NOTE on user_profiles: these rows map 1:1 to auth.users and are
--   normally created by a trigger when a user signs up. Deleting them does
--   NOT delete the auth account; the row may be recreated on next login.
--   To fully remove a user, delete them under Authentication → Users.
-- =====================================================================

-- 1) Disable RLS on every table so DELETE affects ALL rows.
alter table public.order_items        disable row level security;
alter table public.orders             disable row level security;
alter table public.stock_transactions disable row level security;
alter table public.inventory_items    disable row level security;
alter table public.categories         disable row level security;
alter table public.payments           disable row level security;
alter table public.customers          disable row level security;
alter table public.societies          disable row level security;
alter table public.user_profiles      disable row level security;

-- 2) Delete rows in FK-safe order (children before parents).
delete from public.order_items;
delete from public.orders;
delete from public.stock_transactions;
delete from public.inventory_items;
delete from public.categories;
delete from public.payments;
delete from public.customers;
delete from public.societies;
delete from public.user_profiles;

-- 3) Re-enable RLS so your policies stay enforced for the app.
alter table public.order_items        enable row level security;
alter table public.orders             enable row level security;
alter table public.stock_transactions enable row level security;
alter table public.inventory_items    enable row level security;
alter table public.categories         enable row level security;
alter table public.payments           enable row level security;
alter table public.customers          enable row level security;
alter table public.societies          enable row level security;
alter table public.user_profiles      enable row level security;

-- 4) Verify everything is empty (every count should be 0).
select 'societies'          as table_name, count(*) from public.societies
union all select 'categories',          count(*) from public.categories
union all select 'inventory_items',     count(*) from public.inventory_items
union all select 'stock_transactions',  count(*) from public.stock_transactions
union all select 'customers',           count(*) from public.customers
union all select 'orders',              count(*) from public.orders
union all select 'order_items',         count(*) from public.order_items
union all select 'payments',            count(*) from public.payments
union all select 'user_profiles',       count(*) from public.user_profiles
order by table_name;