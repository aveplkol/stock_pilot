-- =====================================================================
-- Stock Pilot — Supabase Schema Migration (New DB Changes)
-- =====================================================================
-- Apply this in the Supabase Dashboard → SQL Editor.
--
-- This migration brings the remote Postgres schema in line with the
-- latest local Drift schema (lib/database/tables.dart) and the fields
-- the client SyncService pushes/pulls (lib/services/sync/sync_service.dart).
--
-- All statements are idempotent (IF NOT EXISTS / IF EXISTS) so the
-- script can be re-run safely.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. societies: user-managed master list of societies
--    (synced via _pushSocieties/_pullSocieties; referenced by
--     customers.society by name)
-- ---------------------------------------------------------------------
create table if not exists public.societies (
  id         text primary key,
  user_id    uuid references auth.users(id),
  name       text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

alter table public.societies enable row level security;

drop policy if exists "societies_owner" on public.societies;
create policy "societies_owner" on public.societies
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Unique (user_id, name) so the client can upsert societies by name
-- (onConflict: 'user_id,name'). Guarded so it is safe to re-run.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'societies_user_name_unique'
  ) then
    alter table public.societies
      add constraint societies_user_name_unique unique (user_id, name);
  end if;
end $$;

-- Ensure categories has the matching unique (user_id, name) constraint too,
-- so the client upsert onConflict target exists on both tables.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'categories_user_name_unique'
  ) then
    alter table public.categories
      add constraint categories_user_name_unique unique (user_id, name);
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. inventory_items: add selling `price` column
--    (pushed by _pushInventory; previously absent remotely)
-- ---------------------------------------------------------------------
alter table public.inventory_items
  add column if not exists price double precision;

-- ---------------------------------------------------------------------
-- 2. inventory_items: add `available_for_ordering` flag
--    (pushed by _pushInventory; defaults to true)
-- ---------------------------------------------------------------------
alter table public.inventory_items
  add column if not exists available_for_ordering boolean not null default true;

-- ---------------------------------------------------------------------
-- 3. customers: add `society` column
--    (pushed by _pushCustomers; previously absent remotely)
-- ---------------------------------------------------------------------
alter table public.customers
  add column if not exists society text;

-- ---------------------------------------------------------------------
-- 3b. customers: add `active` flag (active/inactive customer)
--     (pushed by _pushCustomers; defaults to true)
-- ---------------------------------------------------------------------
alter table public.customers
  add column if not exists active boolean not null default true;

-- ---------------------------------------------------------------------
-- 3c. customers: add `flat_number`; `name` becomes optional.
--     `society` is used as the Block Name.
-- ---------------------------------------------------------------------
alter table public.customers
  add column if not exists flat_number text;

-- Make name nullable if it was previously NOT NULL.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'customers'
      and column_name = 'name'
      and is_nullable = 'NO'
  ) then
    alter table public.customers alter column name drop not null;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 4. order_items: add `user_id` column
--    (pushed by _pushOrderItems and used for the pull filter
--     `.eq('user_id', userId)`). References auth.users(id).
-- ---------------------------------------------------------------------
alter table public.order_items
  add column if not exists user_id uuid references auth.users(id);

-- Backfill user_id on existing order_items from the parent order so the
-- pull filter returns historical rows.
update public.order_items oi
set user_id = o.user_id
from public.orders o
where oi.order_id = o.id
  and oi.user_id is null;

-- ---------------------------------------------------------------------
-- 5. Helpful indexes for the per-user sync filters
-- ---------------------------------------------------------------------
create index if not exists idx_societies_user_id          on public.societies(user_id);
create index if not exists idx_categories_user_id         on public.categories(user_id);
create index if not exists idx_inventory_items_user_id    on public.inventory_items(user_id);
create index if not exists idx_stock_transactions_user_id on public.stock_transactions(user_id);
create index if not exists idx_customers_user_id          on public.customers(user_id);
create index if not exists idx_orders_user_id             on public.orders(user_id);
create index if not exists idx_order_items_user_id        on public.order_items(user_id);
create index if not exists idx_order_items_order_id       on public.order_items(order_id);

-- =====================================================================
-- 6. payments: Payment records from customers
--    (pushed by _pushPayments; pulled by _pullPayments)
-- =====================================================================
create table if not exists public.payments (
  id             text primary key,
  user_id        uuid references auth.users(id),
  customer_id    text not null,
  amount         double precision not null,
  payment_mode   text not null,
  reference      text,
  notes          text,
  payment_date   timestamptz not null,
  created_at     timestamptz not null,
  updated_at     timestamptz not null
);

alter table public.payments enable row level security;

drop policy if exists "payments_owner" on public.payments;
create policy "payments_owner" on public.payments
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists idx_payments_user_id       on public.payments(user_id);
create index if not exists idx_payments_customer_id   on public.payments(customer_id);
create index if not exists idx_payments_payment_date  on public.payments(payment_date desc);

-- =====================================================================
-- OPTIONAL: Update order_items RLS to also allow direct user_id checks
-- (keeps the existing parent-order check, adds a user_id fast path).
-- Only run this if you want order_items to be filterable directly by
-- user_id in addition to the parent-order relationship.
-- =====================================================================
-- drop policy if exists "order_items_owner" on public.order_items;
-- create policy "order_items_owner" on public.order_items
--   for all
--   using (
--     auth.uid() = user_id
--     or exists (
--       select 1 from public.orders o
--       where o.id = order_items.order_id
--         and o.user_id = auth.uid()
--     )
--   )
--   with check (
--     auth.uid() = user_id
--     or exists (
--       select 1 from public.orders o
--       where o.id = order_items.order_id
--         and o.user_id = auth.uid()
--     )
--   );
-- =====================================================================