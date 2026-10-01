# Stock Pilot

**Stock Pilot** is an offline‑first inventory, customer and ordering app for small
neighbourhood retailers and home businesses that sell to residents of gated
**societies / apartment complexes**. Think of it as a **mini “BigBasket” for a
single shop**: you maintain a product catalog with prices and stock, keep a list
of customers grouped by their society, place orders on their behalf, and get
live sales reports.

Built with **Flutter** (mobile, web, desktop), a local **SQLite** database via
**Drift**, state management with **Riverpod**, routing with **go_router**, and
cloud sync + auth via **Supabase**.

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
- Default categories are seeded on first run.

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

### Cloud sync & auth
- Email/password **auth** via Supabase.
- **Local‑first**: every write is saved to the on‑device DB first, then pushed to Supabase (`autoPush`). Push failures are surfaced to the user (red SnackBar) rather than failing silently.
- **Pre‑population**: on launch and after login the app **pulls** your cloud data into the local DB (`pullAll`), so the catalog/customers are ready immediately — like a storefront loading its catalog.
- Per‑user data isolation via `user_id` + Supabase **Row Level Security (RLS)**.

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
  database/
    tables.dart                 # Drift table definitions
    app_database.dart           # Drift DB, schema version + migrations, web config
    repositories.dart           # Inventory/Societies/Customers/Orders repositories
  features/
    auth/                       # login + auth repository
    dashboard/                  # Overview + order report
    inventory/                  # inventory list + add/edit dialog
    customers/                  # customers list + add/edit dialog
    orders/                     # order builder + summary
    settings/
  services/sync/
    sync_service.dart           # push/pull + autoPush + pullAll + syncAll
  providers.dart                # Riverpod providers (DB, repos, auth, sync, startup sync)
supabase/
  rls_policies.sql              # RLS policies for all tables
  migrations/0001_new_db_changes.sql  # schema migration (idempotent)
  select_all_tables.sql         # handy SELECT queries for every table
```

### Data model (Drift / Postgres)
- `societies` (id, user_id, name, timestamps, deleted_at)
- `categories` (id, user_id, name, timestamps, deleted_at)
- `inventory_items` (id, user_id, name, category_id, quantity, unit, minimum_quantity, purchase_price, price, available_for_ordering, notes, image_url, timestamps, deleted_at)
- `stock_transactions` (id, user_id, inventory_item_id, transaction_type, quantity, unit, notes, transaction_date, device_id, created_at)
- `customers` (id, user_id, name, phone, email, address *(= Block Number)*, society, active, notes, timestamps, deleted_at)
- `orders` (id, user_id, customer_id, order_number, status, subtotal, discount, total, notes, order_date, timestamps, deleted_at)
- `order_items` (id, user_id, order_id, inventory_item_id, item_name, quantity, unit, unit_price, created_at)

Local schema version is **5** with incremental migrations (see `app_database.dart`).

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
In the Supabase Dashboard → **SQL Editor**:
1. Run **`supabase/migrations/0001_new_db_changes.sql`** — creates/updates all
   tables and columns (societies table; `inventory_items.price`,
   `available_for_ordering`; `customers.society`, `customers.active`;
   `order_items.user_id`; indexes). Idempotent and safe to re‑run.
2. Run **`supabase/rls_policies.sql`** — enables RLS and owner policies so each
   user only sees their own rows.

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
- **Launch / login** → `pullAll()` fetches your rows (scoped by `user_id`) into the local DB; drift streams update the UI automatically.
- **Full sync** (`syncAll`) pushes then pulls, and is resilient per‑table (one failing table won’t block the rest).
- Master tables (`societies`, `categories`) sync by **name**: existing names are updated, new names inserted — avoiding duplicate‑key and `ON CONFLICT` constraint issues regardless of server constraints.

---

## Troubleshooting
- **“Cloud sync failed: … column … does not exist”** → run `supabase/migrations/0001_new_db_changes.sql`.
- **Nothing syncs / stays local** → you’re not signed in (push/pull are no‑ops without a session). Log in.
- **Data doesn’t pre‑populate** → ensure you’re signed in and the rows in Supabase belong to that user (`user_id = auth.uid()`), and RLS policies are applied.
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
- **Auth**: password reset, OTP/social login, and session refresh handling.
- **Observability**: crash reporting + structured logging for sync failures.

**Business features**
- **Multi‑user / staff roles** per shop; **multiple shops** per owner.
- **Payments** (cash/UPI) tracking and outstanding balances per customer.
- **Notifications** (low stock, order ready) via push/email.
- **Delivery scheduling** by society/slot.

---

## License
Private project. All rights reserved (update as appropriate).
