# Stock Pilot

**Stock Pilot** is an offline‑first inventory, customer and ordering app for small
neighbourhood retailers and home businesses that sell to residents of gated
**societies / apartment complexes**. Think of it as a **mini “BigBasket” for a
single shop**: you maintain a product catalog with prices and stock, keep a list
of customers grouped by their society, place orders on their behalf, and get
live sales reports.

Built with **Flutter** (mobile, web, desktop), a local **SQLite** database via
**Drift**, state management with **Riverpod**, routing with **go_router**, and
cloud sync + auth via **Supabase**. It is **multi‑tenant** (data is isolated per
**company**) with **role‑based access** (admin / manager / staff).

---

## The “BigBasket” analogy

| BigBasket concept | Stock Pilot equivalent |
|-------------------|------------------------|
| Product catalog with prices | **Inventory** (name, price, unit, stock quantity, category, “available for ordering”) |
| Catalog loads instantly on open | **Local‑first**: data is cached in on‑device SQLite and **pre‑populated from the cloud** on launch/login |
| Browse by category | Orders screen groups available products by **category** |
| Delivery address / locality | **Society** + **Block Number** on each customer |
| Place an order in a cart | **Orders**: pick society → customer → add products → **Place order** |
| Order history & analytics | **Overview** report: totals and item breakdown, **All / By society / By customer**, filterable **All‑time / Monthly / Daily** |
| Account across devices | **Supabase auth** + bidirectional **sync** so the same data appears on every signed‑in device |

---

## Features

### Inventory
- Add/edit products: **name, price (₹, 2‑decimal precision), unit, stock quantity, minimum quantity, category, availability for ordering**.
- Directly **enter the quantity** when adding or editing (changes are recorded as stock `ADJUSTMENT` transactions).
- Quick **+1 / −1** stock buttons on each card (`PURCHASE` / `USED` transactions).
- **Low‑stock** indicator when quantity ≤ minimum quantity.
- **Emoji product icons**: each item shows an emoji auto‑assigned from its name/category, with an in‑app **emoji picker** to override it (`core/utils/product_icons.dart`).
- No default societies or categories are seeded — you create your own.

### Customers
- Add/edit customers: **full name, phone, Block Number, email, society, notes**.
- **Society** is a dynamic dropdown driven by the DB with an inline **“Add new society…”** action (no hard‑coded list).
- Filter the customer list by **society** (chips).
- **Activate / inactivate** customers: inactive customers are hidden by default (toggle in the app bar to show them), rendered dimmed with an “Inactive” badge, and can be toggled inline. Inactive customers don’t appear in the Orders customer picker.

### Orders
- Storefront‑style flow: **select society → select (active) customer → add products (grouped by category) → Place order**.
- Live order summary with per‑line and total amounts (2‑decimal precision).
- Placing an order decrements stock and records `USED` stock transactions atomically.

### Overview (reports)
- Inventory stat cards: **Inventory Items**, **Low Stock**.
- **Order report** with:
  - **Grouping**: `All`, `By society`, `By customer`.
  - **Period**: `All time`, `Monthly` (pick a month), `Daily` (pick a day).
  - **Item breakdown** per group (expand a card): `Egg - 10pcs - ₹100.00`, aggregated by item + unit.
  - Group and grand totals in ₹ (2‑decimal precision).

### Payments
- Record customer **payments** (amount, mode, reference, notes, date) and track collections.
- Scoped to the signed‑in user’s company like all other data.

### Auth & access control
- **Email + password** sign‑in via Supabase. The login screen is **sign‑in only** — there is no public “create account”; new users are provisioned by an admin.
- **Forgot password**: request a reset link by email; the in‑app reset screen handles the recovery deep link (web redirects to its own origin, native uses the `stockpilot://` scheme).
- **Role‑based access** (`admin` / `manager` / `staff`) enforced by a central permission matrix (`features/auth/user_profile.dart`):
  - **admin** — everything, incl. **User Management** and **Settings**.
  - **manager** — reports, inventory, customers (plus everything staff can do).
  - **staff** — dashboard, orders, payments.
- **User Management** (admin‑only): list users, change roles, and **add users**. The Add‑User dialog pre‑fills the **company code** from the signed‑in admin (read‑only), so new users always join the admin’s company.

### Multi‑tenancy (company codes)
- Every data table carries a **`company_code`**; users only read/write rows for **their own company** (enforced by RLS `company_code = current_company_code()`).
- The company code is **auto‑populated in code**: `SyncService` resolves the signed‑in user’s company from `user_profiles` and stamps it onto every pushed row — the client never has to supply it manually.
- The **first** user ever created bootstraps as an active admin; everyone else starts inactive until an admin activates them.

### Cloud sync & auth
- **Local‑first**: every write is saved to the on‑device DB first, then pushed to Supabase (`autoPush`). Push failures are surfaced to the user (red SnackBar) rather than failing silently.
- **Pre‑population**: on launch and after login the app **pulls** your cloud data into the local DB (`pullAll`), so the catalog/customers are ready immediately — like a storefront loading its catalog.
- Per‑user data isolation via `user_id`, per‑company isolation via `company_code`, both backed by Supabase **Row Level Security (RLS)**.

---

## Architecture

```
lib/
  main.dart                     # Supabase.initialize + runApp
  app/
    app.dart                    # MaterialApp.router
    router.dart                 # go_router + auth redirects + startup sync
    theme.dart                  # Material 3 theme + global InputDecorationTheme
  core/config/
    supabase_config.dart        # SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY (dart-define)
  core/utils/
    product_icons.dart          # emoji catalog + auto-assignment by name/category
  database/
    tables.dart                 # Drift table definitions
    app_database.dart           # Drift DB, schema version + migrations, web config
    repositories.dart           # Inventory/Societies/Customers/Orders/Payments repositories
  features/
    admin/                      # user management (admin-only): list/roles/add user
    auth/                       # login, forgot/reset password, auth repository, user_profile (roles + permissions)
    dashboard/                  # Overview + order report
    inventory/                  # inventory list + add/edit dialog + emoji icon picker
    customers/                  # customers list + add/edit dialog
    orders/                     # order builder + summary
    payments/                   # record customer payments
    settings/                   # settings, societies, (admin) user management entry
  services/sync/
    sync_service.dart           # push/pull + autoPush + pullAll + syncAll (stamps company_code)
  providers.dart                # Riverpod providers (DB, repos, auth, currentUserProfile, sync)
supabase/
  rls_policies.sql              # RLS policies for all tables
  migrations/
    0001_new_db_changes.sql           # base schema (idempotent)
    0002_user_profiles.sql            # user_profiles + roles + handle_new_user trigger
    0003_user_permissions.sql         # role/permission helpers
    0004_multitenancy_and_auth.sql    # company_code on all tables + per-company RLS
    0005_login_identifier_and_phone.sql # username/phone login helpers
  create_super_admin.sql        # promote an auth user to an active super admin
  select_all_tables.sql         # handy SELECT queries for every table
  truncate_all_tables.sql       # wipe all data (dev)
```

### Data model (Drift / Postgres)
Every table below also carries a **`company_code`** (multi‑tenancy) in Postgres.
- `user_profiles` (id → auth.users, email, role, name, company_code, username, is_active, timestamps)
- `societies` (id, user_id, company_code, name, timestamps, deleted_at)
- `categories` (id, user_id, company_code, name, timestamps, deleted_at)
- `inventory_items` (id, user_id, company_code, name, category_id, quantity, unit, minimum_quantity, purchase_price, price, available_for_ordering, notes, image_url, icon_name, timestamps, deleted_at)
- `stock_transactions` (id, user_id, company_code, inventory_item_id, transaction_type, quantity, unit, notes, transaction_date, device_id, created_at)
- `customers` (id, user_id, company_code, name, phone, email, address *(= Block Number)*, society, active, notes, timestamps, deleted_at)
- `orders` (id, user_id, company_code, customer_id, order_number, status, subtotal, discount, total, notes, order_date, timestamps, deleted_at)
- `order_items` (id, user_id, company_code, order_id, inventory_item_id, item_name, quantity, unit, unit_price, created_at)
- `payments` (id, user_id, company_code, customer_id, amount, payment_mode, reference, notes, payment_date, timestamps)

The local schema version is maintained with incremental migrations (see `app_database.dart`).

---

## Getting started

### Prerequisites
- Flutter SDK (Dart 3.x). This repo was developed with Flutter at `~/flutter`.
- A Supabase project (URL + publishable/anon key).
- For iOS Simulator: full **Xcode** (not just Command Line Tools).

### Install & generate code
```bash
flutter pub get
# Regenerate Drift code after changing tables.dart:
dart run build_runner build
```

### Configure Supabase
Credentials are provided at build/run time via `--dart-define` (defaults exist in
`lib/core/config/supabase_config.dart` for local dev):
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx
```
or use a file: `--dart-define-from-file=dart_define.json`
(see `dart_define.example.json`).

### Apply the database schema (once)
In the Supabase Dashboard → **SQL Editor**, run the following in order (all are
idempotent and safe to re‑run):
1. **`supabase/migrations/0001_new_db_changes.sql`** — base tables/columns and indexes.
2. **`supabase/rls_policies.sql`** — enables RLS and owner policies.
3. **`supabase/migrations/0002_user_profiles.sql`** — `user_profiles`, roles, and the
   `handle_new_user` trigger (the **first** user becomes an active admin).
4. **`supabase/migrations/0003_user_permissions.sql`** — role/permission helpers.
5. **`supabase/migrations/0004_multitenancy_and_auth.sql`** — adds `company_code` to
   every table and switches RLS to per‑company isolation.
6. **`supabase/migrations/0005_login_identifier_and_phone.sql`** — username/phone login helpers.

### Create the first admin
The very first registered user is bootstrapped as an active admin automatically.
To promote an **existing** auth user to an active super admin (role `admin`,
`is_active = true`) and assign their company, edit and run
**`supabase/create_super_admin.sql`** (set `p_email` and `p_company_code`). The
auth account must already exist (create it under **Authentication → Users** or by
signing in once). Thereafter that admin creates everyone else via **User Management**.

### Run
```bash
# Web (SQLite WASM assets are already in web/)
flutter run -d chrome
# macOS desktop
flutter run -d macos
# iOS simulator (requires Xcode installed & selected)
open -a Simulator
flutter run -d iPhone
# Android emulator
flutter emulators --launch <id> && flutter run -d android
```

> Web note: `web/sqlite3.wasm` and `web/drift_worker.js` must match the installed
> `sqlite3` / `drift` package versions. If you upgrade those packages, re‑download
> the matching files into `web/`.

### Inspect data
Use `supabase/select_all_tables.sql` in the SQL Editor to `SELECT * FROM` every
table, see per‑table row counts, or a joined human‑readable order report.

---

## How sync works
- **Write** → saved locally → `autoPush()` upserts to Supabase (errors surfaced to the UI).
- **Company stamping** → on every push, `SyncService` resolves the signed‑in user’s `company_code` from `user_profiles` (cached per cycle) and stamps it onto **all** pushed rows, satisfying the per‑company RLS insert check.
- **Launch / login** → `pullAll()` fetches your rows (scoped by `user_id`) into the local DB; drift streams update the UI automatically.
- **Full sync** (`syncAll`) pushes then pulls, and is resilient per‑table (one failing table won’t block the rest).
- Master tables (`societies`, `categories`) sync by **name**: existing names are updated, new names inserted — avoiding duplicate‑key and `ON CONFLICT` constraint issues regardless of server constraints.

---

## Troubleshooting
- **“Cloud sync failed: … column … does not exist”** → apply the migrations in order (see *Apply the database schema*); the `company_code` columns come from `0004_multitenancy_and_auth.sql`.
- **Nothing syncs / stays local** → you’re not signed in (push/pull are no‑ops without a session). Log in.
- **Push fails with an RLS / `company_code` violation** → the signed‑in user has no `company_code` on their `user_profiles` row. Assign one (e.g. via `create_super_admin.sql` or User Management).
- **New user can’t sign in / see data** → non‑admin users start **inactive**; an admin must activate them, and they must belong to the same company.
- **Data doesn’t pre‑populate** → ensure you’re signed in and the rows in Supabase belong to that user/company, and RLS policies are applied.
- **Web crash: “the `web` parameter needs to be set”** → ensure `web/sqlite3.wasm` and `web/drift_worker.js` exist (they do by default) and match package versions.

---

## Scope of improvement / Roadmap

Ideas to make Stock Pilot more production‑ready and closer to a full BigBasket‑like
experience:

**Sync & data integrity**
- **Real‑time / continuous sync**: Supabase Realtime subscriptions or periodic background pulls so changes from other devices appear live (today pulls happen on launch/login).
- **Conflict resolution**: last‑write‑wins via `updated_at`, or field‑level merge, plus a pending‑changes outbox so offline writes reliably retry.
- **Soft‑delete propagation**: honor `deleted_at` on pull (currently rows are upserted; deletions aren’t removed locally).
- **Pagination / incremental sync**: only fetch rows changed since the last sync for large catalogs.

**Catalog & ordering (BigBasket parity)**
- **Product images** (image_url is modeled but not surfaced): upload to Supabase Storage and show thumbnails.
- **Search & filters** on inventory and the order builder; barcode scanning.
- **Cart persistence**, order editing, cancellations/returns, and order statuses (DRAFT → CONFIRMED → DELIVERED).
- **Discounts / taxes / delivery charges**, multiple price tiers, and units with pack sizes.
- **Reorder suggestions** and automatic low‑stock purchase lists.

**Reports & insights**
- **Date‑range picker** (custom from–to) and **weekly** reports in addition to daily/monthly.
- **Export** reports to CSV/PDF and share/print (customer‑wise bills, society‑wise delivery sheets).
- **Charts** (revenue trend, top products/customers), profit using `purchase_price` vs `price`.

**UX & platform**
- **Product images**, empty‑states, pull‑to‑refresh, and a manual **Sync** button with status.
- **Dark mode** and localization (currency/number/date formatting via `intl`).
- **Deep links** and shareable order links.

**Quality & security**
- **Automated tests**: unit tests for repositories/sync, widget tests for the key flows.
- **Input validation** hardening and server‑side constraints/checks.
- **Auth**: ~~password reset~~ (done), OTP/social login, and session refresh handling.
- **Observability**: crash reporting + structured logging for sync failures.

**Business features**
- ~~**Multi‑user / staff roles** per shop~~ (done — admin/manager/staff with per‑company multi‑tenancy); multiple companies per deployment supported.
- ~~**Payments** tracking~~ (done — basic recording); add outstanding balances per customer and cash/UPI reconciliation.
- **Notifications** (low stock, order ready) via push/email.
- **Delivery scheduling** by society/slot.

---

## License
Private project. All rights reserved (update as appropriate).
