-- =====================================================================
-- Stock Pilot — Supabase Row Level Security (RLS) Policies
-- =====================================================================
-- Apply this in the Supabase Dashboard → SQL Editor.
--
-- This enforces server-side authorization so that each authenticated
-- user can only read and write their OWN rows. It complements the
-- client-side per-user scoping performed by `SyncService`.
--
-- Assumptions:
--   * Each table (except order_items) has a `user_id uuid` column that
--     references auth.users(id).
--   * order_items is authorized indirectly through its parent order.
-- =====================================================================

-- ----- Enable RLS on all tables ----------------------------------------
alter table public.categories          enable row level security;
alter table public.inventory_items     enable row level security;
alter table public.stock_transactions  enable row level security;
alter table public.customers           enable row level security;
alter table public.orders              enable row level security;
alter table public.order_items         enable row level security;

-- ----- Helper: generic owner policy -----------------------------------
-- categories
drop policy if exists "categories_owner" on public.categories;
create policy "categories_owner" on public.categories
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- inventory_items
drop policy if exists "inventory_owner" on public.inventory_items;
create policy "inventory_owner" on public.inventory_items
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- stock_transactions
drop policy if exists "stock_tx_owner" on public.stock_transactions;
create policy "stock_tx_owner" on public.stock_transactions
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- customers
drop policy if exists "customers_owner" on public.customers;
create policy "customers_owner" on public.customers
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- orders
drop policy if exists "orders_owner" on public.orders;
create policy "orders_owner" on public.orders
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- order_items (authorized through the parent order's user_id)
drop policy if exists "order_items_owner" on public.order_items;
create policy "order_items_owner" on public.order_items
  for all
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and o.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and o.user_id = auth.uid()
    )
  );

-- =====================================================================
-- NOTE: If any of the `user_id` columns do not yet exist, add them:
--
--   alter table public.categories         add column user_id uuid references auth.users(id);
--   alter table public.inventory_items    add column user_id uuid references auth.users(id);
--   alter table public.stock_transactions add column user_id uuid references auth.users(id);
--   alter table public.customers          add column user_id uuid references auth.users(id);
--   alter table public.orders             add column user_id uuid references auth.users(id);
-- =====================================================================