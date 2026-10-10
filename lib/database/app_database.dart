import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Societies, Categories, InventoryItems, StockTransactions,
  Customers, Orders, OrderItems, Payments,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  static QueryExecutor _open() {
    // On the web, drift requires explicit locations for the sqlite3 WASM
    // binary and the drift worker. These files must be served from the web
    // root (see web/README or run `dart run drift_dev make-generated` /
    // copy them into the `web/` directory).
    return driftDatabase(
      name: 'stock_pilot',
      web: kIsWeb
          ? DriftWebOptions(
              sqlite3Wasm: Uri.parse('sqlite3.wasm'),
              driftWorker: Uri.parse('drift_worker.js'),
            )
          : null,
    );
  }

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2: inventory selling price + availability-for-ordering flag.
            await m.addColumn(inventoryItems, inventoryItems.price);
            await m.addColumn(
              inventoryItems,
              inventoryItems.availableForOrdering,
            );
          }
          if (from < 3) {
            // v3: customer society.
            await m.addColumn(customers, customers.society);
          }
          if (from < 4) {
            // v4: societies master table (user-managed, syncable).
            await m.createTable(societies);
          }
          if (from < 5) {
            // v5: customer active/inactive flag.
            await m.addColumn(customers, customers.active);
          }
          if (from < 6) {
            // v6: customer flat number (name is now nullable).
            await m.addColumn(customers, customers.flatNumber);
          }
          if (from < 7) {
            // v7: payments table (payment records).
            await m.createTable(payments);
          }
          if (from < 8) {
            // v8: user-selectable Material icon for inventory items.
            await m.addColumn(inventoryItems, inventoryItems.iconName);
          }
        },
      );
}
