import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Categories, InventoryItems, StockTransactions,
  Customers, Orders, OrderItems,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'stock_pilot'));
  @override int get schemaVersion => 1;
}
