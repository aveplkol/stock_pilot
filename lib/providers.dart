import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database/app_database.dart';
import 'database/repositories.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final inventoryRepositoryProvider =
    Provider((ref) => InventoryRepository(ref.watch(databaseProvider)));

final customersRepositoryProvider =
    Provider((ref) => CustomersRepository(ref.watch(databaseProvider)));

final ordersRepositoryProvider =
    Provider((ref) => OrdersRepository(ref.watch(databaseProvider)));
