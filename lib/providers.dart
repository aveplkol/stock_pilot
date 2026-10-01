import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database/app_database.dart';
import 'database/repositories.dart';
import 'features/auth/auth_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();

  ref.onDispose(db.close);

  return db;
});

final inventoryRepositoryProvider =
Provider<InventoryRepositoryBase>((ref) {
  return InventoryRepository(
    ref.watch(databaseProvider),
  );
});

final customersRepositoryProvider = Provider<CustomersRepository>((ref) {
  return CustomersRepository(
    ref.watch(databaseProvider),
  );
});

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return OrdersRepository(
    ref.watch(databaseProvider),
  );
});

// ------------------------------------------------------------
// Supabase
// ------------------------------------------------------------

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(supabaseClientProvider),
  );
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});