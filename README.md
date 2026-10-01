# Stock Pilot

Flutter offline-first starter for Inventory, Customers and Orders.

Run:
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run -d windows

The local database is Drift/SQLite. Supabase authentication and synchronization
are intentionally separated for the next integration stage because they require
your Supabase project credentials and RLS policies.
