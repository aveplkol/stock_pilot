import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'database/app_database.dart';
import 'database/repositories.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/user_profile.dart';
import 'services/sync/sync_service.dart';

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

final societiesRepositoryProvider = Provider<SocietiesRepository>((ref) {
  return SocietiesRepository(
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

final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  return PaymentsRepository(
    ref.watch(databaseProvider),
  );
});

final replenishmentTemplatesRepositoryProvider =
    Provider<ReplenishmentTemplatesRepository>((ref) {
  return ReplenishmentTemplatesRepository(
    ref.watch(databaseProvider),
  );
});

final inventoryStockRepositoryProvider =
    Provider<InventoryStockRepository>((ref) {
  return InventoryStockRepository(
    ref.watch(databaseProvider),
  );
});

/// Alias for backward compatibility during migration.
final inventorySnapshotsRepositoryProvider = inventoryStockRepositoryProvider;

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

/// The currently signed-in user's profile (including role).
///
/// This is fetched once per session. Because it depends on
/// [authStateProvider], it is automatically re-fetched whenever the auth
/// state changes (sign-in / sign-out), which means **role changes take
/// effect after the user signs out and back in** — matching the intended
/// behaviour.
final currentUserProfileProvider = FutureProvider<UserProfile?>((ref) async {
  // Re-run whenever the auth state changes (login/logout).
  ref.watch(authStateProvider);
  final auth = ref.watch(authRepositoryProvider);
  if (auth.currentUser == null) return null;
  return auth.fetchCurrentUserProfile();
});

// ------------------------------------------------------------
// Cloud Sync
// ------------------------------------------------------------

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(databaseProvider),
    ref.watch(supabaseClientProvider),
  );
});

/// Pulls remote data into the local database whenever a user is signed in
/// (on app start and on every sign-in), so the catalog is pre-populated
/// from the cloud — similar to storefront apps that load their catalog on
/// launch. Watch this provider somewhere persistent (e.g. the app shell)
/// to keep it alive.
final startupSyncProvider = Provider<void>((ref) {
  final sync = ref.watch(syncServiceProvider);

  Future<void> pull() async {
    if (sync.isSignedIn) {
      final result = await sync.pullAll();
      // Log pull errors for debugging (visible in console/logs).
      if (result.hasErrors) {
        // ignore: avoid_print
        print('[SyncService] Pull errors: ${result.errors.join(', ')}');
      }
    }
  }

  // Initial pull for an already-restored session.
  // ignore: discarded_futures
  pull();

  // Re-pull on auth changes (e.g. after login).
  final sub = ref
      .watch(supabaseClientProvider)
      .auth
      .onAuthStateChange
      .listen((_) {
    // ignore: discarded_futures
    pull();
  });
  ref.onDispose(sub.cancel);
});
