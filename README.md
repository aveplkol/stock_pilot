# Stock Pilot

Stock Pilot is a Flutter application for managing inventory, customers,
and orders. It uses Drift/SQLite for local data, Riverpod for dependency
management and state, Supabase for authentication, and GoRouter for
navigation.

## Features

### Dashboard

-   Inventory item count
-   Low-stock item count
-   Responsive summary cards
-   Live inventory data from the local database

### Inventory

-   Create inventory items
-   Track quantity and minimum quantity
-   Record stock adjustments
-   View stock transaction history
-   Categories
-   Purchase price and notes
-   Low-stock detection

Default categories: - Grocery - Toiletries - Cleaning - Medicines -
Household - Miscellaneous

### Customers

-   Create and update customers
-   Name, phone, email, address, and notes
-   Stream active customers from the local database

### Orders

-   Create orders with multiple lines
-   Associate orders with customers
-   Calculate subtotals and totals
-   Apply discounts
-   Validate available stock
-   Automatically deduct inventory
-   Record `USED` stock transactions

Order numbers use the form `ORD-<timestamp>`.

## Technology Stack

Technology      Purpose
  --------------- -------------------------------------------
Flutter         Application framework
Dart            Programming language
Riverpod        Dependency injection and state management
Drift           Local SQLite database layer
drift_flutter   Flutter database initialization
Supabase        Authentication/backend services
GoRouter        Application navigation
UUID            Entity and transaction identifiers

## Project Structure

``` text
stock_pilot/
├── lib/
│   ├── app/
│   │   ├── app.dart
│   │   ├── router.dart
│   │   └── theme.dart
│   ├── database/
│   │   ├── app_database.dart
│   │   ├── app_database.g.dart
│   │   ├── repositories.dart
│   │   └── tables.dart
│   ├── features/
│   │   ├── auth/
│   │   ├── dashboard/
│   │   ├── inventory/
│   │   ├── customers/
│   │   └── orders/
│   ├── providers.dart
│   └── main.dart
├── test/
│   └── widget_test.dart
├── pubspec.yaml
└── README.md
```

## Architecture

``` text
Flutter UI
    │
    ▼
Riverpod Providers
    │
    ├──────────────► Supabase Auth
    │
    ▼
Repositories
    │
    ▼
Drift / SQLite
```

Riverpod providers are defined in `lib/providers.dart`.

Main providers include:

-   `databaseProvider`
-   `inventoryRepositoryProvider`
-   `customersRepositoryProvider`
-   `ordersRepositoryProvider`
-   `supabaseClientProvider`
-   `authRepositoryProvider`
-   `authStateProvider`

The application root must be wrapped in a `ProviderScope`:

``` text
ProviderScope
└── StockPilotApp
    └── MaterialApp.router
        └── Feature pages
```

This allows widgets such as `DashboardPage` to call `ref.watch(...)`.

## Database

The local database is implemented with Drift.

`AppDatabase` currently uses schema version `1` and contains:

-   `Categories`
-   `InventoryItems`
-   `StockTransactions`
-   `Customers`
-   `Orders`
-   `OrderItems`

The database is initialized with:

``` text
driftDatabase(name: 'stock_pilot')
```

Repositories provide the application-level database operations so UI
widgets do not need to access Drift tables directly.

### Inventory Transactions

Stock changes are recorded as transactions such as:

-   `ADJUSTMENT`
-   `USED`

Inventory updates and transaction records are performed together inside
database transactions where appropriate.

Negative inventory is prevented by throwing:

``` text
StateError('Insufficient stock')
```

## Authentication

Supabase is initialized in `lib/main.dart` before the application
starts.

The application accesses the client through:

``` text
supabaseClientProvider
```

Authentication is exposed through:

``` text
authRepositoryProvider
authStateProvider
```

Only client-safe Supabase configuration should be included in the
Flutter application. Never put a Supabase service-role key in client
code.

## Requirements

Install:

-   Flutter SDK
-   Dart SDK included with Flutter
-   Android Studio or another supported Flutter development environment
-   A configured Flutter target such as Windows, Android, iOS, macOS, or
    web
-   A Supabase project for authentication

Check the Flutter installation:

``` powershell
flutter doctor
```

## Getting Started

Install dependencies:

``` powershell
flutter pub get
```

Generate Drift/build-runner files after changing database definitions:

``` powershell
dart run build_runner build --delete-conflicting-outputs
```

Run static analysis:

``` powershell
flutter analyze
```

Run tests:

``` powershell
flutter test
```

Run the application:

``` powershell
flutter run
```

For Windows desktop:

``` powershell
flutter run -d windows
```

## Testing

Widget tests use Riverpod's `ProviderScope`.

Database-backed providers should generally be overridden in widget tests
when the widget under test does not require a real database. This keeps
tests deterministic and avoids opening a real Drift database
unnecessarily.

The dashboard test uses a fake inventory repository so it can verify the
UI without creating a real database or leaving Drift timers pending.

The dashboard test verifies:

-   `Overview` is rendered.
-   The dashboard description is rendered.
-   Inventory summary is rendered.
-   Low-stock summary is rendered.

## Development Commands

### Install dependencies

``` powershell
flutter pub get
```

### Analyze

``` powershell
flutter analyze
```

### Test

``` powershell
flutter test
```

### Run a specific test

``` powershell
flutter test test/widget_test.dart
```

### Generate Drift/build-runner files

``` powershell
dart run build_runner build --delete-conflicting-outputs
```

### Clean and rebuild

``` powershell
flutter clean
flutter pub get
```

## Troubleshooting

### `Bad state: No ProviderScope found`

A Riverpod consumer is being built outside a `ProviderScope`.

The application root should use:

``` dart
runApp(
  const ProviderScope(
    child: StockPilotApp(),
  ),
);
```

Tests containing Riverpod consumers should also provide a
`ProviderScope`.

### `You must initialize the supabase instance before calling Supabase.instance`

This happens when code accesses `Supabase.instance` before
`Supabase.initialize(...)` has completed.

The production application initializes Supabase in `main()` before
calling `runApp()`.

Widget tests do not automatically execute the application's `main()`
function. Tests that construct components depending directly on
`Supabase.instance` therefore need appropriate test initialization or
provider overrides.

### Pending Drift timer during tests

A real `AppDatabase` created through `drift_flutter` can create timers
that remain active during a widget test.

For simple widget tests, override repository providers with fakes rather
than opening a real database.

## Repository Design

### `InventoryRepository`

Provides:

-   `watchItems()`
-   `createItem(...)`
-   `addTransaction(...)`
-   `watchHistory(...)`
-   `ensureDefaultCategories()`

### `CustomersRepository`

Provides:

-   `watchCustomers()`
-   `save(...)`

### `OrdersRepository`

Provides:

-   `watchOrders()`
-   `createOrder(...)`

The repository layer is the appropriate place for business rules such as
stock validation, order total calculation, inventory deduction,
transaction creation, and default category initialization.

## Order Data Flow

Order creation is performed inside a database transaction:

``` text
Create order
    │
    ├── Validate order lines
    ├── Calculate subtotal
    ├── Validate discount
    ├── Create order
    ├── Validate inventory
    ├── Create order lines
    ├── Deduct inventory
    └── Record USED stock transactions
```

If an operation fails inside the transaction, the database transaction
can roll back instead of leaving partially completed order data.

## Security Notes

Do not commit:

-   Supabase service-role keys
-   Private API keys
-   Database passwords
-   Other privileged credentials

For production deployment, review Supabase Row Level Security (RLS),
authentication policies, database permissions, and environment-specific
configuration.

## Development Guidelines

When adding a feature:

1.  Add feature-specific UI under `lib/features/`.
2.  Keep database access inside repositories.
3.  Expose repositories and services through Riverpod providers where
    appropriate.
4.  Keep widgets focused on presentation and user interaction.
5.  Add or update unit/widget tests.
6.  Run:

``` powershell
flutter analyze
flutter test
```

before committing.

## Current Status

The project currently contains the foundation for:

-   Dashboard
-   Inventory management
-   Customer management
-   Order management
-   Local database persistence
-   Authentication integration
-   Riverpod dependency management
-   Basic widget testing

The application is under active development.

## License

Add the project's license information here before distributing the
application.
