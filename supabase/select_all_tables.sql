-- =====================================================================
-- Stock Pilot — SELECT helpers for all tables
-- =====================================================================
-- Run any of these in the Supabase Dashboard → SQL Editor to inspect
-- data. When RLS is enabled, the SQL Editor runs as the table owner and
-- bypasses RLS, so you'll see all rows. (From the client, each user only
-- sees their own rows via the `user_id` filter / RLS policies.)
-- =====================================================================

-- ----- Societies -----------------------------------------------------
select * from public.societies order by name;

-- ----- Categories ----------------------------------------------------
select * from public.categories order by name;

-- ----- Inventory items -----------------------------------------------
select * from public.inventory_items order by name;

-- ----- Stock transactions --------------------------------------------
select * from public.stock_transactions order by transaction_date desc;

-- ----- Customers -----------------------------------------------------
select * from public.customers order by name;

-- ----- Orders --------------------------------------------------------
select * from public.orders order by order_date desc;

-- ----- Order items ---------------------------------------------------
select * from public.order_items order by created_at desc;


-- =====================================================================
-- Convenience: scope to the signed-in user (auth.uid()).
-- Useful when testing with RLS as a specific authenticated user.
-- =====================================================================
-- select * from public.societies          where user_id = auth.uid() order by name;
-- select * from public.categories         where user_id = auth.uid() order by name;
-- select * from public.inventory_items    where user_id = auth.uid() order by name;
-- select * from public.stock_transactions where user_id = auth.uid() order by transaction_date desc;
-- select * from public.customers          where user_id = auth.uid() order by name;
-- select * from public.orders             where user_id = auth.uid() order by order_date desc;
-- select * from public.order_items         where user_id = auth.uid() order by created_at desc;


-- =====================================================================
-- Convenience: row counts for every table in one result.
-- =====================================================================
-- select 'societies'          as table_name, count(*) from public.societies
-- union all select 'categories',          count(*) from public.categories
-- union all select 'inventory_items',     count(*) from public.inventory_items
-- union all select 'stock_transactions',  count(*) from public.stock_transactions
-- union all select 'customers',           count(*) from public.customers
-- union all select 'orders',              count(*) from public.orders
-- union all select 'order_items',         count(*) from public.order_items
-- order by table_name;


-- =====================================================================
-- Convenience: a joined, human-readable order report
-- (orders → customers, with society and per-order line items).
-- =====================================================================
-- select
--   o.order_number,
--   o.order_date,
--   o.status,
--   coalesce(c.name, 'Walk-in / Unknown')  as customer,
--   coalesce(nullif(c.society, ''), 'No society') as society,
--   oi.item_name,
--   oi.quantity,
--   oi.unit,
--   oi.unit_price,
--   (oi.quantity * oi.unit_price)          as line_total,
--   o.total                                as order_total
-- from public.orders o
-- left join public.customers c   on c.id = o.customer_id
-- left join public.order_items oi on oi.order_id = o.id
-- where o.deleted_at is null
-- order by o.order_date desc, o.order_number, oi.item_name;