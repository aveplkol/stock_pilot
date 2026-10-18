import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../database/app_database.dart';

/// Handles bidirectional synchronization between the local Drift/SQLite
/// database and the remote Supabase Postgres database.
///
/// Authorization model: every synced row is scoped to the currently
/// authenticated user via `user_id`. Pushes stamp local rows with the
/// current user id; pulls only fetch rows belonging to that user. When
/// Supabase Row Level Security (RLS) is enabled server-side, the database
/// additionally enforces that a user can only read/write their own rows.
class SyncService {
  SyncService(this._db, this._client);

  final AppDatabase _db;
  final SupabaseClient _client;

  String? get _userId => _client.auth.currentUser?.id;

  bool get isSignedIn => _userId != null;

  /// Cached company code for the current user, resolved lazily on first push
  /// within a sync cycle. All pushed rows are stamped with this value so the
  /// server-side RLS `company_code = current_company_code()` check passes and
  /// data is correctly scoped to the user's company/tenant.
  String? _companyCode;

  /// Fetches (and caches) the logged-in user's company code from
  /// `user_profiles`. Returns `null` if unavailable; callers decide whether
  /// to proceed. The cache is cleared at the start of each sync entry point.
  Future<String?> _currentCompanyCode(String userId) async {
    if (_companyCode != null) return _companyCode;
    try {
      final row = await _client
          .from('user_profiles')
          .select('company_code')
          .eq('id', userId)
          .maybeSingle();
      _companyCode = row?['company_code'] as String?;
    } catch (_) {
      _companyCode = null;
    }
    return _companyCode;
  }

  /// Pushes all local data to Supabase after a local write.
  ///
  /// Returns `null` on success (or when not signed in / offline is a no-op),
  /// or a human-readable error message when the push failed so the caller
  /// can surface it. The data remains saved locally regardless, and will be
  /// retried on the next push/sync.
  Future<String?> autoPush() async {
    final userId = _userId;
    if (userId == null) {
      // Not signed in: cloud sync is simply unavailable; local save stands.
      return null;
    }
    _companyCode = null; // Re-resolve for the current user each cycle.
    try {
      await _pushSocieties(userId);
      await _pushCategories(userId);
      await _pushInventory(userId);
      await _pushStockTransactions(userId);
      await _pushCustomers(userId);
      await _pushOrders(userId);
      await _pushOrderItems(userId);
      await _pushPayments(userId);
      await _pushReplenishmentTemplates(userId);
      await _pushInventorySnapshots(userId);
      return null;
    } on PostgrestException catch (e) {
      // Most common cause: the remote schema is missing a column/table.
      // Surface a concise, actionable message.
      return 'Cloud sync failed: ${e.message}'
          '${e.hint != null ? ' (${e.hint})' : ''}';
    } catch (e) {
      return 'Cloud sync failed: $e';
    }
  }

  /// Runs a full sync cycle: push local changes up, then pull remote
  /// changes down.
  ///
  /// Each step is isolated so that a single failing table (e.g. a push
  /// blocked by a server constraint) does not prevent the remaining
  /// pushes/pulls from running. In particular, pulls always run so the
  /// local catalog is populated from the cloud even if a push failed.
  Future<SyncResult> syncAll() async {
    final userId = _userId;
    if (userId == null) {
      throw StateError('You must be signed in to sync.');
    }
    _companyCode = null; // Re-resolve for the current user each cycle.

    var pushed = 0;
    var pulled = 0;
    final errors = <String>[];

    Future<void> step(Future<int> Function() op, void Function(int) tally,
        String label) async {
      try {
        tally(await op());
      } catch (e) {
        errors.add('$label: $e');
      }
    }

    await step(() => _pushSocieties(userId), (n) => pushed += n, 'push societies');
    await step(() => _pushCategories(userId), (n) => pushed += n, 'push categories');
    await step(() => _pushInventory(userId), (n) => pushed += n, 'push inventory');
    await step(() => _pushStockTransactions(userId), (n) => pushed += n, 'push stock');
    await step(() => _pushCustomers(userId), (n) => pushed += n, 'push customers');
    await step(() => _pushOrders(userId), (n) => pushed += n, 'push orders');
    await step(() => _pushOrderItems(userId), (n) => pushed += n, 'push order items');
    await step(() => _pushPayments(userId), (n) => pushed += n, 'push payments');
    await step(() => _pushReplenishmentTemplates(userId), (n) => pushed += n, 'push templates');
    await step(() => _pushInventorySnapshots(userId), (n) => pushed += n, 'push snapshots');

    await step(() => _pullSocieties(userId), (n) => pulled += n, 'pull societies');
    await step(() => _pullCategories(userId), (n) => pulled += n, 'pull categories');
    await step(() => _pullInventory(userId), (n) => pulled += n, 'pull inventory');
    await step(() => _pullStockTransactions(userId), (n) => pulled += n, 'pull stock');
    await step(() => _pullCustomers(userId), (n) => pulled += n, 'pull customers');
    await step(() => _pullOrders(userId), (n) => pulled += n, 'pull orders');
    await step(() => _pullOrderItems(userId), (n) => pulled += n, 'pull order items');
    await step(() => _pullPayments(userId), (n) => pulled += n, 'pull payments');

    return SyncResult(pushed: pushed, pulled: pulled, errors: errors);
  }

  /// Pulls remote data into the local database (remote -> local only).
  /// Used on startup/login so the catalog is pre-populated like a storefront.
  /// Resilient: a failing table does not stop the others.
  Future<int> pullAll() async {
    final userId = _userId;
    if (userId == null) return 0;

    var pulled = 0;
    Future<void> step(Future<int> Function() op) async {
      try {
        pulled += await op();
      } catch (_) {
        // Ignore individual table failures during background pull.
      }
    }

    await step(() => _pullSocieties(userId));
    await step(() => _pullCategories(userId));
    await step(() => _pullInventory(userId));
    await step(() => _pullStockTransactions(userId));
    await step(() => _pullCustomers(userId));
    await step(() => _pullOrders(userId));
    await step(() => _pullOrderItems(userId));
    await step(() => _pullPayments(userId));
    await step(() => _pullReplenishmentTemplates(userId));
    await step(() => _pullInventorySnapshots(userId));
    return pulled;
  }

  // --------------------------------------------------------------------
  // PUSH (local -> remote)
  // --------------------------------------------------------------------

  /// Upserts "name-keyed" master data (societies/categories) robustly.
  ///
  /// These tables may have a server-side unique constraint on
  /// (user_id, name). To avoid both the "duplicate key" (23505) and the
  /// "no matching ON CONFLICT constraint" (42P10) errors across differing
  /// server schemas, we only push rows whose name does not already exist
  /// remotely, and update existing ones in place. This needs no special
  /// constraint and never aborts the wider sync.
  Future<int> _pushNameKeyed(
    String table,
    String userId,
    String? companyCode,
    List<({String id, String name, DateTime createdAt, DateTime updatedAt, DateTime? deletedAt})> rows,
  ) async {
    if (rows.isEmpty) return 0;

    // Find which names already exist remotely for this user.
    final existing = await _client
        .from(table)
        .select('id,name')
        .eq('user_id', userId) as List<dynamic>;
    final existingIdByName = <String, String>{
      for (final e in existing.cast<Map<String, dynamic>>())
        e['name'] as String: e['id'] as String,
    };

    final toInsert = <Map<String, dynamic>>[];
    final toUpdate = <Map<String, dynamic>>[];
    for (final r in rows) {
      final base = {
        'user_id': userId,
        if (companyCode != null) 'company_code': companyCode,
        'name': r.name,
        'created_at': r.createdAt.toIso8601String(),
        'updated_at': r.updatedAt.toIso8601String(),
        'deleted_at': r.deletedAt?.toIso8601String(),
      };
      final remoteId = existingIdByName[r.name];
      if (remoteId == null) {
        toInsert.add({'id': r.id, ...base});
      } else {
        // Update the existing remote row (matched by its own id) in place.
        toUpdate.add({'id': remoteId, ...base});
      }
    }

    if (toInsert.isNotEmpty) {
      await _client.from(table).upsert(toInsert); // conflict on primary key id
    }
    for (final u in toUpdate) {
      await _client.from(table).update(u).eq('id', u['id'] as String);
    }
    return toInsert.length + toUpdate.length;
  }

  Future<int> _pushSocieties(String userId) async {
    final companyCode = await _currentCompanyCode(userId);
    final rows = await _db.select(_db.societies).get();
    return _pushNameKeyed(
      'societies',
      userId,
      companyCode,
      rows
          .map((r) => (
                id: r.id,
                name: r.name,
                createdAt: r.createdAt,
                updatedAt: r.updatedAt,
                deletedAt: r.deletedAt,
              ))
          .toList(),
    );
  }

  Future<int> _pushCategories(String userId) async {
    final companyCode = await _currentCompanyCode(userId);
    final rows = await _db.select(_db.categories).get();
    return _pushNameKeyed(
      'categories',
      userId,
      companyCode,
      rows
          .map((r) => (
                id: r.id,
                name: r.name,
                createdAt: r.createdAt,
                updatedAt: r.updatedAt,
                deletedAt: r.deletedAt,
              ))
          .toList(),
    );
  }

  Future<int> _pushInventory(String userId) async {
    final companyCode = await _currentCompanyCode(userId);
    final rows = await _db.select(_db.inventoryItems).get();
    if (rows.isEmpty) return 0;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': userId,
              if (companyCode != null) 'company_code': companyCode,
              'name': r.name,
              'category_id': r.categoryId,
              'quantity': r.quantity,
              'unit': r.unit,
              'minimum_quantity': r.minimumQuantity,
              'purchase_price': r.purchasePrice,
              'price': r.price,
              'available_for_ordering': r.availableForOrdering,
              'notes': r.notes,
              'image_url': r.imageUrl,
              'icon_name': r.iconName,
              'default_quantity': r.defaultQuantity,
              'created_at': r.createdAt.toIso8601String(),
              'updated_at': r.updatedAt.toIso8601String(),
              'deleted_at': r.deletedAt?.toIso8601String(),
            })
        .toList();
    await _client.from('inventory_items').upsert(payload);
    return payload.length;
  }

  Future<int> _pushStockTransactions(String userId) async {
    final companyCode = await _currentCompanyCode(userId);
    final rows = await _db.select(_db.stockTransactions).get();
    if (rows.isEmpty) return 0;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': userId,
              if (companyCode != null) 'company_code': companyCode,
              'inventory_item_id': r.inventoryItemId,
              'transaction_type': r.transactionType,
              // The remote table enforces a positive-quantity check
              // constraint; direction is conveyed by `transaction_type`
              // (e.g. USED vs PURCHASE), so store the magnitude only.
              'quantity': r.quantity.abs(),
              'unit': r.unit,
              'notes': r.notes,
              'transaction_date': r.transactionDate.toIso8601String(),
              'device_id': r.deviceId,
              'created_at': r.createdAt.toIso8601String(),
            })
        .toList();
    await _client.from('stock_transactions').upsert(payload);
    return payload.length;
  }

  Future<int> _pushCustomers(String userId) async {
    final companyCode = await _currentCompanyCode(userId);
    final rows = await _db.select(_db.customers).get();
    if (rows.isEmpty) return 0;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': userId,
              if (companyCode != null) 'company_code': companyCode,
              'name': r.name,
              'phone': r.phone,
              'email': r.email,
              'block': r.block,
              'society': r.society,
              'flat_number': r.flatNumber,
              'active': r.active,
              'notes': r.notes,
              'created_at': r.createdAt.toIso8601String(),
              'updated_at': r.updatedAt.toIso8601String(),
              'deleted_at': r.deletedAt?.toIso8601String(),
            })
        .toList();
    await _client.from('customers').upsert(payload);
    return payload.length;
  }

  Future<int> _pushOrders(String userId) async {
    final companyCode = await _currentCompanyCode(userId);
    final rows = await _db.select(_db.orders).get();
    if (rows.isEmpty) return 0;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': userId,
              if (companyCode != null) 'company_code': companyCode,
              'customer_id': r.customerId,
              'order_number': r.orderNumber,
              'status': r.status,
              'subtotal': r.subtotal,
              'discount': r.discount,
              'total': r.total,
              'notes': r.notes,
              'order_date': r.orderDate.toIso8601String(),
              'created_at': r.createdAt.toIso8601String(),
              'updated_at': r.updatedAt.toIso8601String(),
              'deleted_at': r.deletedAt?.toIso8601String(),
            })
        .toList();
    await _client.from('orders').upsert(payload);
    return payload.length;
  }

  Future<int> _pushOrderItems(String userId) async {
    final companyCode = await _currentCompanyCode(userId);
    final rows = await _db.select(_db.orderItems).get();
    if (rows.isEmpty) return 0;

    // The remote `order_items` table denormalizes the item name, so build
    // a lookup of inventory item id -> name.
    final items = await _db.select(_db.inventoryItems).get();
    final nameById = {for (final i in items) i.id: i.name};

    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': userId,
              if (companyCode != null) 'company_code': companyCode,
              'order_id': r.orderId,
              'inventory_item_id': r.inventoryItemId,
              'item_name': nameById[r.inventoryItemId] ?? 'Unknown item',
              'quantity': r.quantity,
              'unit': r.unit,
              'unit_price': r.unitPrice,
              // Note: the remote `order_items` table does not define a
              // `total` column (it is derivable as quantity * unit_price),
              // so it is intentionally omitted from the push payload.
              'created_at': r.createdAt.toIso8601String(),
            })
        .toList();
    await _client.from('order_items').upsert(payload);
    return payload.length;
  }

  Future<int> _pushPayments(String userId) async {
    final companyCode = await _currentCompanyCode(userId);
    final rows = await _db.select(_db.payments).get();
    if (rows.isEmpty) return 0;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': userId,
              if (companyCode != null) 'company_code': companyCode,
              'customer_id': r.customerId,
              'amount': r.amount,
              'payment_mode': r.paymentMode,
              'reference': r.reference,
              'notes': r.notes,
              'payment_date': r.paymentDate.toIso8601String(),
              'created_at': r.createdAt.toIso8601String(),
              'updated_at': r.updatedAt.toIso8601String(),
            })
        .toList();
    await _client.from('payments').upsert(payload);
    return payload.length;
  }

  // --------------------------------------------------------------------
  // PULL (remote -> local)
  // --------------------------------------------------------------------

  DateTime _date(dynamic v) => DateTime.parse(v as String);
  DateTime? _dateN(dynamic v) =>
      v == null ? null : DateTime.parse(v as String);
  double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
  double? _dN(dynamic v) => (v as num?)?.toDouble();

  Future<int> _pullSocieties(String userId) async {
    final data = await _client
        .from('societies')
        .select()
        .eq('user_id', userId) as List<dynamic>;
    for (final row in data.cast<Map<String, dynamic>>()) {
      await _db.into(_db.societies).insertOnConflictUpdate(
            SocietiesCompanion.insert(
              id: row['id'] as String,
              userId: Value(userId),
              name: row['name'] as String,
              createdAt: _date(row['created_at']),
              updatedAt: _date(row['updated_at']),
              deletedAt: Value(_dateN(row['deleted_at'])),
            ),
          );
    }
    return data.length;
  }

  Future<int> _pullCategories(String userId) async {
    final data = await _client
        .from('categories')
        .select()
        .eq('user_id', userId) as List<dynamic>;
    for (final row in data.cast<Map<String, dynamic>>()) {
      await _db.into(_db.categories).insertOnConflictUpdate(
            CategoriesCompanion.insert(
              id: row['id'] as String,
              userId: Value(userId),
              name: row['name'] as String,
              createdAt: _date(row['created_at']),
              updatedAt: _date(row['updated_at']),
              deletedAt: Value(_dateN(row['deleted_at'])),
            ),
          );
    }
    return data.length;
  }

  Future<int> _pullInventory(String userId) async {
    final data = await _client
        .from('inventory_items')
        .select()
        .eq('user_id', userId) as List<dynamic>;
    for (final row in data.cast<Map<String, dynamic>>()) {
      await _db.into(_db.inventoryItems).insertOnConflictUpdate(
            InventoryItemsCompanion.insert(
              id: row['id'] as String,
              userId: Value(userId),
              name: row['name'] as String,
              categoryId: Value(row['category_id'] as String?),
              quantity: Value(_d(row['quantity'])),
              unit: row['unit'] as String,
              minimumQuantity: Value(_d(row['minimum_quantity'])),
              purchasePrice: Value(_dN(row['purchase_price'])),
              price: Value(_dN(row['price'])),
              availableForOrdering:
                  Value((row['available_for_ordering'] as bool?) ?? true),
              notes: Value(row['notes'] as String?),
              imageUrl: Value(row['image_url'] as String?),
              iconName: Value(row['icon_name'] as String?),
              defaultQuantity: Value(_dN(row['default_quantity'])),
              createdAt: _date(row['created_at']),
              updatedAt: _date(row['updated_at']),
              deletedAt: Value(_dateN(row['deleted_at'])),
            ),
          );
    }
    return data.length;
  }

  Future<int> _pullStockTransactions(String userId) async {
    final data = await _client
        .from('stock_transactions')
        .select()
        .eq('user_id', userId) as List<dynamic>;
    for (final row in data.cast<Map<String, dynamic>>()) {
      await _db.into(_db.stockTransactions).insertOnConflictUpdate(
            StockTransactionsCompanion.insert(
              id: row['id'] as String,
              userId: Value(userId),
              inventoryItemId: row['inventory_item_id'] as String,
              transactionType: row['transaction_type'] as String,
              quantity: _d(row['quantity']),
              unit: row['unit'] as String,
              notes: Value(row['notes'] as String?),
              transactionDate: _date(row['transaction_date']),
              deviceId: Value(row['device_id'] as String?),
              createdAt: _date(row['created_at']),
            ),
          );
    }
    return data.length;
  }

  Future<int> _pullCustomers(String userId) async {
    final data = await _client
        .from('customers')
        .select()
        .eq('user_id', userId) as List<dynamic>;
    for (final row in data.cast<Map<String, dynamic>>()) {
      await _db.into(_db.customers).insertOnConflictUpdate(
            CustomersCompanion.insert(
              id: row['id'] as String,
              userId: Value(userId),
              name: Value(row['name'] as String?),
              phone: Value(row['phone'] as String?),
              email: Value(row['email'] as String?),
              block: Value(row['block'] as String?),
              society: Value(row['society'] as String?),
              flatNumber: Value(row['flat_number'] as String?),
              active: Value((row['active'] as bool?) ?? true),
              notes: Value(row['notes'] as String?),
              createdAt: _date(row['created_at']),
              updatedAt: _date(row['updated_at']),
              deletedAt: Value(_dateN(row['deleted_at'])),
            ),
          );
    }
    return data.length;
  }

  Future<int> _pullOrders(String userId) async {
    final data = await _client
        .from('orders')
        .select()
        .eq('user_id', userId) as List<dynamic>;
    for (final row in data.cast<Map<String, dynamic>>()) {
      await _db.into(_db.orders).insertOnConflictUpdate(
            OrdersCompanion.insert(
              id: row['id'] as String,
              userId: Value(userId),
              customerId: Value(row['customer_id'] as String?),
              orderNumber: row['order_number'] as String,
              status: row['status'] as String,
              subtotal: Value(_d(row['subtotal'])),
              discount: Value(_d(row['discount'])),
              total: Value(_d(row['total'])),
              notes: Value(row['notes'] as String?),
              orderDate: _date(row['order_date']),
              createdAt: _date(row['created_at']),
              updatedAt: _date(row['updated_at']),
              deletedAt: Value(_dateN(row['deleted_at'])),
            ),
          );
    }
    return data.length;
  }

  Future<int> _pullOrderItems(String userId) async {
    final data = await _client
        .from('order_items')
        .select()
        .eq('user_id', userId) as List<dynamic>;

    for (final row in data.cast<Map<String, dynamic>>()) {
      final quantity = _d(row['quantity']);
      final unitPrice = _d(row['unit_price']);
      await _db.into(_db.orderItems).insertOnConflictUpdate(
            OrderItemsCompanion.insert(
              id: row['id'] as String,
              orderId: row['order_id'] as String,
              inventoryItemId: row['inventory_item_id'] as String,
              quantity: quantity,
              unit: row['unit'] as String,
              unitPrice: unitPrice,
              // `total` is not stored remotely; derive it locally.
              total: row['total'] == null
                  ? quantity * unitPrice
                  : _d(row['total']),
              createdAt: _date(row['created_at']),
            ),
          );
    }
    return data.length;
  }

  Future<int> _pullPayments(String userId) async {
    final data = await _client
        .from('payments')
        .select()
        .eq('user_id', userId) as List<dynamic>;
    for (final row in data.cast<Map<String, dynamic>>()) {
      await _db.into(_db.payments).insertOnConflictUpdate(
            PaymentsCompanion.insert(
              id: row['id'] as String,
              userId: Value(userId),
              customerId: row['customer_id'] as String,
              amount: _d(row['amount']),
              paymentMode: row['payment_mode'] as String,
              reference: Value(row['reference'] as String?),
              notes: Value(row['notes'] as String?),
              paymentDate: _date(row['payment_date']),
              createdAt: _date(row['created_at']),
              updatedAt: _date(row['updated_at']),
            ),
          );
    }
    return data.length;
  }

  // --------------------------------------------------------------------
  // Replenishment Templates (push/pull) - one row per customer with JSON items
  // --------------------------------------------------------------------

  Future<int> _pushReplenishmentTemplates(String userId) async {
    final companyCode = await _currentCompanyCode(userId);
    final rows = await _db.select(_db.replenishmentTemplates).get();
    if (rows.isEmpty) return 0;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': userId,
              if (companyCode != null) 'company_code': companyCode,
              'customer_id': r.customerId,
              'items': r.items, // JSON string: [{"id": "...", "qty": 2}, ...]
              'created_at': r.createdAt.toIso8601String(),
              'updated_at': r.updatedAt.toIso8601String(),
            })
        .toList();
    await _client.from('replenishment_templates').upsert(payload);
    return payload.length;
  }

  Future<int> _pullReplenishmentTemplates(String userId) async {
    final data = await _client
        .from('replenishment_templates')
        .select()
        .eq('user_id', userId) as List<dynamic>;
    for (final row in data.cast<Map<String, dynamic>>()) {
      // Handle `items` as either JSON string or already-parsed JSONB
      final itemsRaw = row['items'];
      final itemsJson = itemsRaw is String ? itemsRaw : '[]';
      
      await _db.into(_db.replenishmentTemplates).insertOnConflictUpdate(
            ReplenishmentTemplatesCompanion.insert(
              id: row['id'] as String,
              userId: Value(userId),
              customerId: row['customer_id'] as String,
              items: Value(itemsJson),
              createdAt: _date(row['created_at']),
              updatedAt: _date(row['updated_at']),
            ),
          );
    }
    return data.length;
  }

  // --------------------------------------------------------------------
  // Inventory Stock (push/pull) - daily opening/closing stock per item
  // Note: Supabase table is named 'inventory_stock' with 'stock_date' column
  // --------------------------------------------------------------------

  Future<int> _pushInventoryStock(String userId) async {
    final companyCode = await _currentCompanyCode(userId);
    final rows = await _db.select(_db.inventoryStock).get();
    if (rows.isEmpty) return 0;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': userId,
              if (companyCode != null) 'company_code': companyCode,
              'inventory_item_id': r.inventoryItemId,
              // Convert DateTime to DATE string (YYYY-MM-DD) for Supabase
              'stock_date': '${r.stockDate.year}-${r.stockDate.month.toString().padLeft(2, '0')}-${r.stockDate.day.toString().padLeft(2, '0')}',
              'opening_stock': r.openingStock,
              'closing_stock': r.closingStock,
              'created_at': r.createdAt.toIso8601String(),
              'updated_at': r.updatedAt.toIso8601String(),
            })
        .toList();
    // Use onConflict to handle the UNIQUE(inventory_item_id, stock_date) constraint
    await _client.from('inventory_stock').upsert(
      payload,
      onConflict: 'inventory_item_id,stock_date',
    );
    return payload.length;
  }

  Future<int> _pullInventoryStock(String userId) async {
    final data = await _client
        .from('inventory_stock')
        .select()
        .eq('user_id', userId) as List<dynamic>;
    for (final row in data.cast<Map<String, dynamic>>()) {
      // Parse stock_date which is a DATE (YYYY-MM-DD) from Supabase
      final stockDateStr = row['stock_date'] as String;
      final stockDate = DateTime.parse(stockDateStr);
      
      await _db.into(_db.inventoryStock).insertOnConflictUpdate(
            InventoryStockCompanion.insert(
              id: row['id'] as String,
              userId: Value(userId),
              companyCode: Value(row['company_code'] as String?),
              inventoryItemId: row['inventory_item_id'] as String,
              stockDate: DateTime.utc(
                stockDate.year,
                stockDate.month,
                stockDate.day,
              ),
              openingStock: Value(_d(row['opening_stock'])),
              closingStock: Value(_d(row['closing_stock'])),
              createdAt: _date(row['created_at']),
              updatedAt: _date(row['updated_at']),
            ),
          );
    }
    return data.length;
  }

  // Backward-compatible aliases (will be removed after full migration)
  Future<int> _pushInventorySnapshots(String userId) => _pushInventoryStock(userId);
  Future<int> _pullInventorySnapshots(String userId) => _pullInventoryStock(userId);
}

/// Summary of a completed sync cycle.
class SyncResult {
  const SyncResult({
    required this.pushed,
    required this.pulled,
    this.errors = const [],
  });

  final int pushed;
  final int pulled;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() {
    final base = 'Synced: pushed $pushed, pulled $pulled record(s).';
    if (errors.isEmpty) return base;
    return '$base (${errors.length} issue(s))';
  }
}
