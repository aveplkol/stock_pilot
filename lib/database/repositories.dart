import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';

const _uuid = Uuid();

abstract class InventoryRepositoryBase {
  Stream<List<InventoryItem>> watchItems();

  /// Streams only soft-deleted inventory items (for the recovery view).
  Stream<List<InventoryItem>> watchDeletedItems();

  Stream<List<Category>> watchCategories();

  /// Streams only soft-deleted categories (for the recovery view).
  Stream<List<Category>> watchDeletedCategories();

  /// Adds a new category by name, preventing duplicates (case-insensitive).
  /// Returns the existing category if one with the same name already exists.
  Future<Category> addCategory(String name);

  /// Soft-deletes a category (sets deletedAt).
  Future<void> deleteCategory(String categoryId);

  /// Restores a soft-deleted category (clears deletedAt).
  Future<void> restoreCategory(String categoryId);

  /// Permanently removes a soft-deleted category from the local DB.
  Future<void> purgeCategory(String categoryId);

  Future<InventoryItem> createItem({
    required String name,
    required String unit,
    double quantity,
    double minimumQuantity,
    double? purchasePrice,
    double? price,
    bool availableForOrdering,
    String? notes,
    String? categoryId,
    String? iconName,
    double? defaultQuantity,
  });

  Future<void> updateItem({
    required String id,
    required String name,
    required String unit,
    double? minimumQuantity,
    double? purchasePrice,
    double? price,
    bool? availableForOrdering,
    String? notes,
    String? categoryId,
    String? iconName,
    double? defaultQuantity,
  });

  Future<void> addTransaction(
      String itemId,
      double delta,
      String type, {
        required String unit,
        String? notes,
      });

  /// Sets the on-hand quantity to an absolute value, recording an
  /// ADJUSTMENT transaction for the difference.
  Future<void> setQuantity(String itemId, double target);

  /// Soft-deletes an inventory item (sets deletedAt).
  Future<void> deleteItem(String itemId);

  /// Restores a soft-deleted inventory item (clears deletedAt).
  Future<void> restoreItem(String itemId);

  /// Permanently removes a soft-deleted inventory item from the local DB.
  Future<void> purgeItem(String itemId);

  Stream<List<StockTransaction>> watchHistory(String itemId);

  Future<void> ensureDefaultCategories();
}

class InventoryRepository implements InventoryRepositoryBase {
  InventoryRepository(this.db);

  final AppDatabase db;

  @override
  Stream<List<InventoryItem>> watchItems() {
    return (db.select(db.inventoryItems)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
            (t) => OrderingTerm(
          expression: t.name,
        ),
      ]))
        .watch();
  }

  @override
  Stream<List<InventoryItem>> watchDeletedItems() {
    return (db.select(db.inventoryItems)
      ..where((t) => t.deletedAt.isNotNull())
      ..orderBy([
            (t) => OrderingTerm(
          expression: t.deletedAt,
          mode: OrderingMode.desc,
        ),
      ]))
        .watch();
  }

  @override
  Stream<List<Category>> watchCategories() {
    return (db.select(db.categories)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
            (t) => OrderingTerm(expression: t.name),
      ]))
        .watch();
  }

  @override
  Stream<List<Category>> watchDeletedCategories() {
    return (db.select(db.categories)
      ..where((t) => t.deletedAt.isNotNull())
      ..orderBy([
            (t) => OrderingTerm(
          expression: t.deletedAt,
          mode: OrderingMode.desc,
        ),
      ]))
        .watch();
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    final now = DateTime.now();
    await (db.update(db.categories)..where((t) => t.id.equals(categoryId)))
        .write(
      CategoriesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> restoreCategory(String categoryId) async {
    await (db.update(db.categories)..where((t) => t.id.equals(categoryId)))
        .write(
      CategoriesCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> purgeCategory(String categoryId) async {
    await (db.delete(db.categories)..where((t) => t.id.equals(categoryId)))
        .go();
  }

  @override
  Future<Category> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Category name cannot be empty');
    }

    // Prevent duplicates (case-insensitive) among non-deleted categories.
    final existing = await (db.select(db.categories)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final lower = trimmed.toLowerCase();
    final dup = existing.where((c) => c.name.toLowerCase() == lower).toList();
    if (dup.isNotEmpty) {
      throw StateError('A category named "$trimmed" already exists.');
    }

    final now = DateTime.now();
    final id = _uuid.v4();
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: id,
            name: trimmed,
            createdAt: now,
            updatedAt: now,
          ),
        );

    return (db.select(db.categories)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  @override
  Future<InventoryItem> createItem({
    required String name,
    required String unit,
    double quantity = 0,
    double minimumQuantity = 0,
    double? purchasePrice,
    double? price,
    bool availableForOrdering = true,
    String? notes,
    String? categoryId,
    String? iconName,
    double? defaultQuantity,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();

    await db.into(db.inventoryItems).insert(
      InventoryItemsCompanion.insert(
        id: id,
        name: name,
        unit: unit,
        quantity: Value(quantity),
        minimumQuantity: Value(minimumQuantity),
        purchasePrice: Value(purchasePrice),
        price: Value(price),
        availableForOrdering: Value(availableForOrdering),
        notes: Value(notes),
        categoryId: Value(categoryId),
        iconName: Value(iconName),
        defaultQuantity: Value(defaultQuantity),
        createdAt: now,
        updatedAt: now,
      ),
    );

    if (quantity != 0) {
      await addTransaction(
        id,
        quantity,
        'ADJUSTMENT',
        unit: unit,
        notes: 'Initial quantity',
      );
    }

    return (db.select(db.inventoryItems)
      ..where((t) => t.id.equals(id)))
        .getSingle();
  }

  @override
  Future<void> updateItem({
    required String id,
    required String name,
    required String unit,
    double? minimumQuantity,
    double? purchasePrice,
    double? price,
    bool? availableForOrdering,
    String? notes,
    String? categoryId,
    String? iconName,
    double? defaultQuantity,
  }) async {
    final now = DateTime.now();

    await (db.update(db.inventoryItems)
          ..where((t) => t.id.equals(id)))
        .write(
      InventoryItemsCompanion(
        name: Value(name),
        unit: Value(unit),
        minimumQuantity: minimumQuantity == null
            ? const Value.absent()
            : Value(minimumQuantity),
        purchasePrice: Value(purchasePrice),
        price: Value(price),
        availableForOrdering: availableForOrdering == null
            ? const Value.absent()
            : Value(availableForOrdering),
        notes: Value(notes),
        categoryId: Value(categoryId),
        iconName: Value(iconName),
        defaultQuantity: Value(defaultQuantity),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<void> addTransaction(
      String itemId,
      double delta,
      String type, {
        required String unit,
        String? notes,
      }) async {
    if (delta == 0) {
      return;
    }

    await db.transaction(() async {
      final item = await (db.select(db.inventoryItems)
        ..where((t) => t.id.equals(itemId)))
          .getSingle();

      final next = item.quantity + delta;

      if (next < 0) {
        throw StateError('Insufficient stock');
      }

      final now = DateTime.now();

      await db.into(db.stockTransactions).insert(
        StockTransactionsCompanion.insert(
          id: _uuid.v4(),
          inventoryItemId: itemId,
          transactionType: type,
          quantity: delta,
          unit: unit,
          notes: Value(notes),
          transactionDate: now,
          createdAt: now,
        ),
      );

      await (db.update(db.inventoryItems)
        ..where((t) => t.id.equals(itemId)))
          .write(
        InventoryItemsCompanion(
          quantity: Value(next),
          updatedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<void> setQuantity(String itemId, double target) async {
    if (target < 0) {
      throw StateError('Quantity cannot be negative');
    }
    final item = await (db.select(db.inventoryItems)
          ..where((t) => t.id.equals(itemId)))
        .getSingle();
    final delta = target - item.quantity;
    if (delta == 0) return;
    await addTransaction(
      itemId,
      delta,
      'ADJUSTMENT',
      unit: item.unit,
      notes: 'Manual quantity set',
    );
  }

  @override
  Future<void> deleteItem(String itemId) async {
    await (db.update(db.inventoryItems)..where((t) => t.id.equals(itemId)))
        .write(
      InventoryItemsCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> restoreItem(String itemId) async {
    await (db.update(db.inventoryItems)..where((t) => t.id.equals(itemId)))
        .write(
      InventoryItemsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> purgeItem(String itemId) async {
    await (db.delete(db.inventoryItems)..where((t) => t.id.equals(itemId)))
        .go();
  }

  @override
  Stream<List<StockTransaction>> watchHistory(
      String itemId,
      ) {
    return (db.select(db.stockTransactions)
      ..where(
            (t) => t.inventoryItemId.equals(itemId),
      )
      ..orderBy([
            (t) => OrderingTerm(
          expression: t.transactionDate,
          mode: OrderingMode.desc,
        ),
      ]))
        .watch();
  }

  @override
  Future<void> ensureDefaultCategories() async {
    // No default categories are seeded — users create their own from the
    // inventory screen. Kept as a no-op so existing callers remain valid.
    const names = <String>[];

    final existing = await db.select(db.categories).get();

    final have = existing.map((e) => e.name).toSet();

    for (final name in names.where(
          (name) => !have.contains(name),
    )) {
      final now = DateTime.now();

      await db.into(db.categories).insert(
        CategoriesCompanion.insert(
          id: _uuid.v4(),
          name: name,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }
}

class SocietiesRepository {
  SocietiesRepository(this.db);

  final AppDatabase db;

  Stream<List<Society>> watchSocieties() {
    return (db.select(db.societies)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.name),
          ]))
        .watch();
  }

  Future<List<Society>> getSocieties() {
    return (db.select(db.societies)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm(expression: t.name),
          ]))
        .get();
  }

  /// Streams only soft-deleted (inactive) societies for the recovery view.
  Stream<List<Society>> watchDeletedSocieties() {
    return (db.select(db.societies)
          ..where((t) => t.deletedAt.isNotNull())
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.deletedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .watch();
  }

  /// Soft-deletes (deactivates) a society by setting deletedAt.
  Future<void> deleteSociety(String id) async {
    final now = DateTime.now();
    await (db.update(db.societies)..where((t) => t.id.equals(id))).write(
      SocietiesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Restores a soft-deleted society by clearing deletedAt.
  Future<void> restoreSociety(String id) async {
    await (db.update(db.societies)..where((t) => t.id.equals(id))).write(
      SocietiesCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Permanently removes a soft-deleted society from the local DB.
  Future<void> purgeSociety(String id) async {
    await (db.delete(db.societies)..where((t) => t.id.equals(id))).go();
  }

  /// Adds a new society by name. Rejects duplicates (case-insensitive)
  /// among non-deleted societies by throwing a [StateError].
  Future<Society> addSociety(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Society name cannot be empty');
    }

    final all = await (db.select(db.societies)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    final lower = trimmed.toLowerCase();
    if (all.any((s) => s.name.toLowerCase() == lower)) {
      throw StateError('A society named "$trimmed" already exists.');
    }

    final now = DateTime.now();
    final id = _uuid.v4();
    await db.into(db.societies).insert(
          SocietiesCompanion.insert(
            id: id,
            name: trimmed,
            createdAt: now,
            updatedAt: now,
          ),
        );

    return (db.select(db.societies)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  /// Seeds the default set of societies if the table is empty.
  ///
  /// There are intentionally no default societies — users add their own
  /// from Settings → Societies. This is kept as a no-op so any existing
  /// callers remain valid.
  Future<void> ensureDefaultSocieties() async {
    const names = <String>[];

    final existing = await db.select(db.societies).get();
    final have = existing.map((e) => e.name).toSet();

    for (final name in names.where((n) => !have.contains(n))) {
      final now = DateTime.now();
      await db.into(db.societies).insert(
            SocietiesCompanion.insert(
              id: _uuid.v4(),
              name: name,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
  }
}

class CustomersRepository {
  CustomersRepository(this.db);

  final AppDatabase db;

  Stream<List<Customer>> watchCustomers() {
    return (db.select(db.customers)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
            (t) => OrderingTerm(expression: t.society),
            (t) => OrderingTerm(expression: t.flatNumber),
            (t) => OrderingTerm(expression: t.name),
      ]))
        .watch();
  }

  Future<void> save({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? block,
    String? society,
    String? flatNumber,
    bool active = true,
    String? notes,
  }) async {
    final now = DateTime.now();

    if (id == null) {
      await db.into(db.customers).insert(
        CustomersCompanion.insert(
          id: _uuid.v4(),
          name: Value(name),
          phone: Value(phone),
          email: Value(email),
          block: Value(block),
          society: Value(society),
          flatNumber: Value(flatNumber),
          active: Value(active),
          notes: Value(notes),
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      await (db.update(db.customers)
        ..where((t) => t.id.equals(id)))
          .write(
        CustomersCompanion(
          name: Value(name),
          phone: Value(phone),
          email: Value(email),
          block: Value(block),
          society: Value(society),
          flatNumber: Value(flatNumber),
          active: Value(active),
          notes: Value(notes),
          updatedAt: Value(now),
        ),
      );
    }
  }

  /// Toggles a customer's active/inactive state.
  Future<void> setActive(String id, bool active) async {
    await (db.update(db.customers)..where((t) => t.id.equals(id))).write(
      CustomersCompanion(
        active: Value(active),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

/// A single line item within an order (for the detailed report).
class OrderReportItem {
  const OrderReportItem({
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.purchasePrice,
    required this.total,
    this.categoryName,
  });

  final String itemName;
  final double quantity;
  final String unit;

  /// Selling price per unit at the time of reporting (from the order line).
  final double unitPrice;

  /// Purchase (cost) price per unit, looked up from the inventory item.
  final double purchasePrice;

  /// Line revenue = quantity * unitPrice.
  final double total;

  /// Category name for grouping in reports.
  final String? categoryName;

  /// Line cost = quantity * purchasePrice.
  double get cost => quantity * purchasePrice;

  /// Line profit = revenue - cost.
  double get profit => total - cost;
}

/// A single order with the denormalized customer name, society and the
/// list of line items, used for building the Overview order report.
class OrderReportRow {
  const OrderReportRow({
    required this.orderId,
    required this.orderNumber,
    required this.orderDate,
    required this.total,
    required this.customerId,
    required this.customerName,
    required this.society,
    required this.items,
  });

  final String orderId;
  final String orderNumber;
  final DateTime orderDate;
  final double total;
  final String? customerId;
  final String customerName;
  final String society;
  final List<OrderReportItem> items;
}

class NewOrderLine {
  const NewOrderLine({
    required this.inventoryItemId,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
  });

  final String inventoryItemId;
  final double quantity;
  final String unit;
  final double unitPrice;
}

/// An existing order loaded for editing: the order plus a map of
/// inventoryItemId -> ordered quantity.
class ExistingOrder {
  const ExistingOrder({required this.order, required this.quantities});

  final Order order;
  final Map<String, double> quantities;
}

class OrdersRepository {
  OrdersRepository(this.db);

  final AppDatabase db;

  Stream<List<Order>> watchOrders() {
    return (db.select(db.orders)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
            (t) => OrderingTerm(
          expression: t.orderDate,
          mode: OrderingMode.desc,
        ),
      ]))
        .watch();
  }

  /// Streams all (non-deleted) orders joined to their customer and line
  /// items so the Overview can report totals and item breakdowns
  /// All / Society-wise / Customer-wise (optionally per month).
  ///
  /// The stream re-emits whenever orders change; on each emission it loads
  /// the matching order items and inventory names to build the breakdown.
  Stream<List<OrderReportRow>> watchOrderReport() {
    final ordersStream = (db.select(db.orders).join([
      leftOuterJoin(
        db.customers,
        db.customers.id.equalsExp(db.orders.customerId),
      ),
    ])
          ..where(db.orders.deletedAt.isNull())
          ..orderBy([
            OrderingTerm(
              expression: db.orders.orderDate,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();

    return ordersStream.asyncMap((rows) async {
      // Load all order items, inventory details and categories once per emission.
      final allItems = await db.select(db.orderItems).get();
      final inventory = await db.select(db.inventoryItems).get();
      final categories = await (db.select(db.categories)
            ..where((t) => t.deletedAt.isNull()))
          .get();

      final nameById = {for (final i in inventory) i.id: i.name};
      final purchaseById = {
        for (final i in inventory) i.id: i.purchasePrice ?? 0.0,
      };
      final categoryIdById = {for (final i in inventory) i.id: i.categoryId};
      final categoryNameById = {for (final c in categories) c.id: c.name};

      final itemsByOrder = <String, List<OrderReportItem>>{};
      for (final it in allItems) {
        final catId = categoryIdById[it.inventoryItemId];
        final catName = catId != null ? categoryNameById[catId] : null;
        itemsByOrder.putIfAbsent(it.orderId, () => []).add(
              OrderReportItem(
                itemName:
                    nameById[it.inventoryItemId] ?? 'Unknown item',
                quantity: it.quantity,
                unit: it.unit,
                unitPrice: it.unitPrice,
                purchasePrice: purchaseById[it.inventoryItemId] ?? 0.0,
                total: it.total,
                categoryName: catName,
              ),
            );
      }

      return rows.map((row) {
        final order = row.readTable(db.orders);
        final customer = row.readTableOrNull(db.customers);
        final flat = (customer?.flatNumber ?? '').trim();
        final cname = (customer?.name ?? '').trim();
        final label = flat.isNotEmpty && cname.isNotEmpty
            ? '$flat - $cname'
            : flat.isNotEmpty
                ? flat
                : cname.isNotEmpty
                    ? cname
                    : 'Walk-in / Unknown';
        return OrderReportRow(
          orderId: order.id,
          orderNumber: order.orderNumber,
          orderDate: order.orderDate,
          total: order.total,
          customerId: order.customerId,
          customerName: label,
          society: (customer?.society == null || customer!.society!.isEmpty)
              ? 'No block'
              : customer.society!,
          items: itemsByOrder[order.id] ?? const [],
        );
      }).toList();
    });
  }

  /// Finds the most recent non-deleted order for [customerId] placed on the
  /// same calendar day as [date], returning it with its item quantities so
  /// the UI can pre-fill and update it. Returns null if none exists.
  Future<ExistingOrder?> findOrderForCustomerOnDate(
    String customerId,
    DateTime date,
  ) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final order = await (db.select(db.orders)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.customerId.equals(customerId) &
              t.orderDate.isBiggerOrEqualValue(dayStart) &
              t.orderDate.isSmallerThanValue(dayEnd))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(1))
        .getSingleOrNull();

    if (order == null) return null;

    final items = await (db.select(db.orderItems)
          ..where((t) => t.orderId.equals(order.id)))
        .get();

    return ExistingOrder(
      order: order,
      quantities: {
        for (final it in items) it.inventoryItemId: it.quantity,
      },
    );
  }

  /// Helper method to get available stock for an item on a specific date.
  /// Returns closing stock from inventory_stock if exists, otherwise falls back
  /// to item.quantity for today, or 0 for other dates.
  Future<double> _getAvailableStock(String itemId, DateTime orderDate) async {
    final stockRepo = InventoryStockRepository(db);
    final stockRecord = await stockRepo.getStockRecord(itemId, orderDate);
    
    if (stockRecord != null) {
      return stockRecord.closingStock;
    }
    
    // No stock record — check if it's today
    final now = DateTime.now();
    final isToday = orderDate.year == now.year &&
        orderDate.month == now.month &&
        orderDate.day == now.day;
    
    if (isToday) {
      // Fall back to live inventory_items.quantity
      final item = await (db.select(db.inventoryItems)
            ..where((t) => t.id.equals(itemId)))
          .getSingleOrNull();
      return item?.quantity ?? 0;
    }
    
    // For other dates with no stock record, availability is 0
    return 0;
  }

  /// Replaces all line items of an existing order with [lines], restoring and
  /// re-applying stock accordingly. Recomputes totals.
  /// Also recalculates closing stock for affected items on the order date.
  Future<void> updateOrder({
    required String orderId,
    required List<NewOrderLine> lines,
    double discount = 0,
    String? notes,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('Order must contain at least one item');
    }

    // Collect all item IDs affected (both old and new lines)
    final affectedItemIds = <String>{};
    DateTime? orderDate;

    await db.transaction(() async {
      final now = DateTime.now();

      // Get the order to find its date
      final order = await (db.select(db.orders)
            ..where((t) => t.id.equals(orderId)))
          .getSingle();
      orderDate = order.orderDate;

      // Restore stock from existing lines, then delete them.
      final existing = await (db.select(db.orderItems)
            ..where((t) => t.orderId.equals(orderId)))
          .get();
      for (final e in existing) {
        affectedItemIds.add(e.inventoryItemId);
        await (db.update(db.inventoryItems)
              ..where((t) => t.id.equals(e.inventoryItemId)))
            .write(
          InventoryItemsCompanion.custom(
            quantity: db.inventoryItems.quantity + Variable(e.quantity),
            updatedAt: Variable(now),
          ),
        );
      }
      await (db.delete(db.orderItems)
            ..where((t) => t.orderId.equals(orderId)))
          .go();

      final subtotal = lines.fold<double>(
        0,
        (sum, line) => sum + line.quantity * line.unitPrice,
      );
      if (discount > subtotal) {
        throw ArgumentError('Discount cannot exceed subtotal');
      }

      // Apply new lines - validate against date-specific stock
      for (final line in lines) {
        affectedItemIds.add(line.inventoryItemId);
        final item = await (db.select(db.inventoryItems)
              ..where((t) => t.id.equals(line.inventoryItemId)))
            .getSingle();
        
        // For validation, use the item.quantity which has been restored
        // This is the source of truth since we just restored the quantities
        final availableStock = item.quantity;
        
        if (line.quantity <= 0 || availableStock < line.quantity) {
          throw StateError('Insufficient stock for ${item.name}');
        }
        await db.into(db.orderItems).insert(
              OrderItemsCompanion.insert(
                id: _uuid.v4(),
                orderId: orderId,
                inventoryItemId: item.id,
                quantity: line.quantity,
                unit: line.unit,
                unitPrice: line.unitPrice,
                total: line.quantity * line.unitPrice,
                createdAt: now,
              ),
            );
        await (db.update(db.inventoryItems)
              ..where((t) => t.id.equals(item.id)))
            .write(
          InventoryItemsCompanion(
            quantity: Value(item.quantity - line.quantity),
            updatedAt: Value(now),
          ),
        );
        await db.into(db.stockTransactions).insert(
              StockTransactionsCompanion.insert(
                id: _uuid.v4(),
                inventoryItemId: item.id,
                transactionType: 'USED',
                quantity: -line.quantity,
                unit: line.unit,
                notes: Value('Order ${order.orderNumber} (updated)'),
                transactionDate: now,
                createdAt: now,
              ),
            );
      }

      await (db.update(db.orders)..where((t) => t.id.equals(orderId))).write(
        OrdersCompanion(
          subtotal: Value(subtotal),
          discount: Value(discount),
          total: Value(subtotal - discount),
          notes: Value(notes),
          updatedAt: Value(now),
        ),
      );
    });

    // Recalculate closing stock for all affected items on the order date.
    // NOTE: This only updates inventory_stock.closing_stock, NOT inventory_items.quantity
    // The transaction above already correctly updated inventory_items.quantity.
    if (orderDate != null && affectedItemIds.isNotEmpty) {
      final stockRepo = InventoryStockRepository(db);
      for (final itemId in affectedItemIds) {
        await stockRepo.recalculateClosingStock(itemId, orderDate!);
      }
    }
  }

  /// Creates a new order with the given lines.
  /// Validates stock against inventory_items.quantity (the source of truth for deduction).
  /// Also recalculates closing stock for all affected items on the order date.
  Future<String> createOrder({
    String? customerId,
    required List<NewOrderLine> lines,
    String status = 'DRAFT',
    double discount = 0,
    String? notes,
    DateTime? orderDate,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError(
        'Order must contain at least one item',
      );
    }

    final effectiveOrderDate = orderDate ?? DateTime.now();
    final affectedItemIds = lines.map((l) => l.inventoryItemId).toSet();

    final orderId = await db.transaction(() async {
      final txnNow = DateTime.now();
      final id = _uuid.v4();

      final subtotal = lines.fold<double>(
        0,
            (sum, line) => sum + line.quantity * line.unitPrice,
      );

      if (discount > subtotal) {
        throw ArgumentError(
          'Discount cannot exceed subtotal',
        );
      }

      final number = 'ORD-${txnNow.millisecondsSinceEpoch}';

      await db.into(db.orders).insert(
        OrdersCompanion.insert(
          id: id,
          customerId: Value(customerId),
          orderNumber: number,
          status: status,
          subtotal: Value(subtotal),
          discount: Value(discount),
          total: Value(subtotal - discount),
          notes: Value(notes),
          orderDate: effectiveOrderDate,
          createdAt: txnNow,
          updatedAt: txnNow,
        ),
      );

      for (final line in lines) {
        final item = await (db.select(db.inventoryItems)
          ..where(
                (t) => t.id.equals(line.inventoryItemId),
          ))
            .getSingle();

        // Validate against inventory_items.quantity - this is the source of truth
        // since it's what gets deducted. This ensures consistency.
        final availableStock = item.quantity;

        if (line.quantity <= 0 || availableStock < line.quantity) {
          throw StateError(
            'Insufficient stock for ${item.name}',
          );
        }

        await db.into(db.orderItems).insert(
          OrderItemsCompanion.insert(
            id: _uuid.v4(),
            orderId: id,
            inventoryItemId: item.id,
            quantity: line.quantity,
            unit: line.unit,
            unitPrice: line.unitPrice,
            total: line.quantity * line.unitPrice,
            createdAt: txnNow,
          ),
        );

        await (db.update(db.inventoryItems)
          ..where((t) => t.id.equals(item.id)))
            .write(
          InventoryItemsCompanion(
            quantity: Value(
              item.quantity - line.quantity,
            ),
            updatedAt: Value(txnNow),
          ),
        );

        await db.into(db.stockTransactions).insert(
          StockTransactionsCompanion.insert(
            id: _uuid.v4(),
            inventoryItemId: item.id,
            transactionType: 'USED',
            quantity: -line.quantity,
            unit: line.unit,
            notes: Value('Order $number'),
            transactionDate: txnNow,
            createdAt: txnNow,
          ),
        );
      }

      return id;
    });

    // Recalculate closing stock for all affected items on the order date.
    // NOTE: This only updates inventory_stock.closing_stock, NOT inventory_items.quantity
    // The transaction above already correctly updated inventory_items.quantity.
    if (affectedItemIds.isNotEmpty) {
      final stockRepo = InventoryStockRepository(db);
      for (final itemId in affectedItemIds) {
        await stockRepo.recalculateClosingStock(itemId, effectiveOrderDate);
      }
    }

    return orderId;
  }

  /// Fetches all orders for a customer (used for ledger/outstanding calculation).
  Future<List<Order>> getOrdersForCustomer(String customerId) {
    return (db.select(db.orders)
          ..where((t) => t.deletedAt.isNull() & t.customerId.equals(customerId))
          ..orderBy([(t) => OrderingTerm(expression: t.orderDate, mode: OrderingMode.desc)]))
        .get();
  }

  /// Returns distinct customer IDs that have orders on the given date.
  Future<Set<String>> getCustomersWithOrdersOnDate(DateTime date) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final orders = await (db.select(db.orders)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.orderDate.isBiggerOrEqualValue(dayStart) &
              t.orderDate.isSmallerThanValue(dayEnd)))
        .get();

    return orders.map((o) => o.customerId).whereType<String>().toSet();
  }

  /// Finds the most recent non-deleted order for [customerId] placed before
  /// [beforeDate]. Used to pre-fill quantities from previous orders.
  Future<ExistingOrder?> findMostRecentOrderBefore(
    String customerId,
    DateTime beforeDate,
  ) async {
    final order = await (db.select(db.orders)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.customerId.equals(customerId) &
              t.orderDate.isSmallerThanValue(beforeDate))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.orderDate,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(1))
        .getSingleOrNull();

    if (order == null) return null;

    final items = await (db.select(db.orderItems)
          ..where((t) => t.orderId.equals(order.id)))
        .get();

    return ExistingOrder(
      order: order,
      quantities: {
        for (final it in items) it.inventoryItemId: it.quantity,
      },
    );
  }
}

class PaymentsRepository {
  PaymentsRepository(this.db);

  final AppDatabase db;

  /// Adds a new payment record.
  Future<void> addPayment({
    required String customerId,
    required double amount,
    required String paymentMode,
    String? reference,
    String? notes,
    DateTime? paymentDate,
  }) async {
    final now = DateTime.now();
    await db.into(db.payments).insert(
      PaymentsCompanion.insert(
        id: _uuid.v4(),
        customerId: customerId,
        amount: amount,
        paymentMode: paymentMode,
        reference: Value(reference),
        notes: Value(notes),
        paymentDate: paymentDate ?? now,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Fetches recent payments for a customer (up to [limit] records).
  /// Only called on "View Ledger" click, as per requirements.
  Future<List<Payment>> getRecentPaymentsForCustomer(
    String customerId, {
    int limit = 10,
  }) {
    return (db.select(db.payments)
          ..where((t) => t.customerId.equals(customerId))
          ..orderBy([(t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc)])
          ..limit(limit))
        .get();
  }
}

// ---------------------------------------------------------------------------
// Replenishment Templates (one row per customer with JSON items array)
// ---------------------------------------------------------------------------

/// A single item in a template (inventory item + quantity).
class TemplateItem {
  const TemplateItem({required this.inventoryItemId, required this.quantity});
  
  final String inventoryItemId;
  final double quantity;
  
  Map<String, dynamic> toJson() => {'id': inventoryItemId, 'qty': quantity};
  
  factory TemplateItem.fromJson(Map<String, dynamic> json) {
    return TemplateItem(
      inventoryItemId: json['id'] as String,
      quantity: (json['qty'] as num).toDouble(),
    );
  }
}

// ---------------------------------------------------------------------------
// Inventory Stock (daily opening/closing stock per item)
// ---------------------------------------------------------------------------

class InventoryStockRepository {
  InventoryStockRepository(this.db);

  final AppDatabase db;

  /// Normalizes a DateTime to midnight UTC for consistent date storage.
  DateTime _normalizeDate(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);

  /// Check if a date is today.
  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Watch all stock records for a given date.
  Stream<List<InventoryStockData>> watchStockForDateRaw(DateTime date) {
    final normalized = _normalizeDate(date);
    return (db.select(db.inventoryStock)
          ..where((t) => t.stockDate.equals(normalized)))
        .watch();
  }

  /// Get a specific stock record for an item on a date.
  Future<InventoryStockData?> getStockRecord(String itemId, DateTime date) {
    final normalized = _normalizeDate(date);
    return (db.select(db.inventoryStock)
          ..where((t) =>
              t.inventoryItemId.equals(itemId) &
              t.stockDate.equals(normalized)))
        .getSingleOrNull();
  }

  /// Get all stock records for a date as a map of itemId -> record.
  Future<Map<String, InventoryStockData>> getStockMapForDateRaw(
      DateTime date) async {
    final normalized = _normalizeDate(date);
    final records = await (db.select(db.inventoryStock)
          ..where((t) => t.stockDate.equals(normalized)))
        .get();
    return {for (final r in records) r.inventoryItemId: r};
  }

  /// Get the total ordered quantity for an item on a given date.
  /// Sums order_items.quantity for all non-deleted orders on that date.
  Future<double> getOrderedQty(String itemId, DateTime date) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    // Get all non-deleted orders on that date
    final ordersOnDate = await (db.select(db.orders)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.orderDate.isBiggerOrEqualValue(dayStart) &
              t.orderDate.isSmallerThanValue(dayEnd)))
        .get();

    if (ordersOnDate.isEmpty) return 0;

    final orderIds = ordersOnDate.map((o) => o.id).toSet();
    final allOrderItems = await db.select(db.orderItems).get();

    double total = 0;
    for (final oi in allOrderItems) {
      if (orderIds.contains(oi.orderId) && oi.inventoryItemId == itemId) {
        total += oi.quantity;
      }
    }
    return total;
  }

  /// Get ordered quantities for all items on a given date.
  /// Returns a map of inventoryItemId -> totalOrderedQty.
  Future<Map<String, double>> getOrderedQtyMapForDate(DateTime date) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    // Get all non-deleted orders on that date
    final ordersOnDate = await (db.select(db.orders)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.orderDate.isBiggerOrEqualValue(dayStart) &
              t.orderDate.isSmallerThanValue(dayEnd)))
        .get();

    if (ordersOnDate.isEmpty) return {};

    final orderIds = ordersOnDate.map((o) => o.id).toSet();
    final allOrderItems = await db.select(db.orderItems).get();

    final result = <String, double>{};
    for (final oi in allOrderItems) {
      if (orderIds.contains(oi.orderId)) {
        result[oi.inventoryItemId] =
            (result[oi.inventoryItemId] ?? 0) + oi.quantity;
      }
    }
    return result;
  }

  /// Check if default stock has already been applied for a date.
  /// Returns true if any inventory_stock row exists for that date.
  Future<bool> hasDefaultStockBeenApplied(DateTime date) async {
    final normalized = _normalizeDate(date);
    final records = await (db.select(db.inventoryStock)
          ..where((t) => t.stockDate.equals(normalized))
          ..limit(1))
        .get();
    return records.isNotEmpty;
  }

  /// Apply default stock for a date.
  /// Creates inventory_stock rows for ALL items with defaultQuantity set.
  /// Sets opening_stock = closing_stock = defaultQuantity.
  /// Skips items that already have a stock record for that date.
  /// **For today's date, also updates inventory_items.quantity** to keep in sync.
  /// Returns the number of items for which stock was applied.
  Future<int> applyDefaultStock(DateTime date) async {
    final normalized = _normalizeDate(date);
    final now = DateTime.now();
    final isToday = _isToday(date);

    // Get all non-deleted items with defaultQuantity set
    final items = await (db.select(db.inventoryItems)
          ..where((t) => t.deletedAt.isNull() & t.defaultQuantity.isNotNull()))
        .get();

    // Get existing stock records for this date
    final existingRecords = await getStockMapForDateRaw(date);

    int applied = 0;
    for (final item in items) {
      // Skip if already has a stock record for this date
      if (existingRecords.containsKey(item.id)) continue;

      final defaultQty = item.defaultQuantity;
      if (defaultQty == null || defaultQty <= 0) continue;

      // Create stock record with opening = closing = defaultQuantity
      final id = _uuid.v4();
      await db.into(db.inventoryStock).insert(
            InventoryStockCompanion.insert(
              id: id,
              inventoryItemId: item.id,
              stockDate: normalized,
              openingStock: Value(defaultQty),
              closingStock: Value(defaultQty),
              createdAt: now,
              updatedAt: now,
            ),
          );

      // For today, also update inventory_items.quantity to keep in sync
      if (isToday) {
        await (db.update(db.inventoryItems)
              ..where((t) => t.id.equals(item.id)))
            .write(InventoryItemsCompanion(
          quantity: Value(defaultQty),
          updatedAt: Value(now),
        ));
      }

      applied++;
    }

    return applied;
  }

  /// Set the opening stock for an item on a date.
  /// Validates that newQty >= orderedQty for that date.
  /// Creates or updates the stock record.
  /// Recalculates closing_stock = newQty - orderedQty.
  /// **For today's date, also updates inventory_items.quantity** to keep in sync.
  /// Throws if newQty < orderedQty.
  Future<void> setOpeningStock(String itemId, DateTime date, double newQty) async {
    if (newQty < 0) {
      throw StateError('Stock cannot be negative');
    }

    // Get ordered quantity for this item on this date
    final orderedQty = await getOrderedQty(itemId, date);
    
    if (newQty < orderedQty) {
      throw StateError(
        'Cannot set stock to $newQty — already $orderedQty ordered for this date',
      );
    }

    final normalized = _normalizeDate(date);
    final now = DateTime.now();
    final closingStock = newQty - orderedQty;
    final isToday = _isToday(date);

    final existing = await getStockRecord(itemId, date);

    if (existing != null) {
      // Update existing record
      await (db.update(db.inventoryStock)
            ..where((t) => t.id.equals(existing.id)))
          .write(InventoryStockCompanion(
        openingStock: Value(newQty),
        closingStock: Value(closingStock),
        updatedAt: Value(now),
      ));
    } else {
      // Create new record
      final id = _uuid.v4();
      await db.into(db.inventoryStock).insert(
            InventoryStockCompanion.insert(
              id: id,
              inventoryItemId: itemId,
              stockDate: normalized,
              openingStock: Value(newQty),
              closingStock: Value(closingStock),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    // For today, also update inventory_items.quantity to closing stock
    if (isToday) {
      await (db.update(db.inventoryItems)
            ..where((t) => t.id.equals(itemId)))
          .write(InventoryItemsCompanion(
        quantity: Value(closingStock),
        updatedAt: Value(now),
      ));
    }
  }

  /// Set the closing stock (available stock) for an item on a date.
  /// This is what the user edits in the inventory page.
  /// Calculates opening_stock = newClosingQty + orderedQty.
  /// Validates that newClosingQty >= 0.
  /// **For today's date, also updates inventory_items.quantity** to keep in sync.
  Future<void> setClosingStock(String itemId, DateTime date, double newClosingQty) async {
    if (newClosingQty < 0) {
      throw StateError('Stock cannot be negative');
    }

    // Get ordered quantity for this item on this date
    final orderedQty = await getOrderedQty(itemId, date);
    
    // Calculate what opening stock should be
    final openingStock = newClosingQty + orderedQty;

    final normalized = _normalizeDate(date);
    final now = DateTime.now();
    final isToday = _isToday(date);

    final existing = await getStockRecord(itemId, date);

    if (existing != null) {
      // Update existing record
      await (db.update(db.inventoryStock)
            ..where((t) => t.id.equals(existing.id)))
          .write(InventoryStockCompanion(
        openingStock: Value(openingStock),
        closingStock: Value(newClosingQty),
        updatedAt: Value(now),
      ));
    } else {
      // Create new record
      final id = _uuid.v4();
      await db.into(db.inventoryStock).insert(
            InventoryStockCompanion.insert(
              id: id,
              inventoryItemId: itemId,
              stockDate: normalized,
              openingStock: Value(openingStock),
              closingStock: Value(newClosingQty),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    // For today, also update inventory_items.quantity to keep in sync
    // This ensures that order validation/deduction uses the same value
    if (isToday) {
      await (db.update(db.inventoryItems)
            ..where((t) => t.id.equals(itemId)))
          .write(InventoryItemsCompanion(
        quantity: Value(newClosingQty),
        updatedAt: Value(now),
      ));
    }
  }

  /// Recalculate the closing stock for an item on a date.
  /// Called after orders are created/updated/deleted.
  /// closing_stock = opening_stock - sum(order_items for that date).
  /// 
  /// NOTE: This method ONLY updates inventory_stock.closing_stock, NOT
  /// inventory_items.quantity. The order transaction already correctly 
  /// updates inventory_items.quantity through restore/deduct operations.
  /// Updating it again here would cause bugs because this runs AFTER the
  /// transaction completed, and calculating opening - ordered doesn't account
  /// for the transaction's internal restore+deduct sequence.
  Future<void> recalculateClosingStock(String itemId, DateTime date) async {
    final existing = await getStockRecord(itemId, date);
    if (existing == null) {
      // No stock record exists — nothing to update
      return;
    }

    final orderedQty = await getOrderedQty(itemId, date);
    final closingStock = existing.openingStock - orderedQty;
    final now = DateTime.now();

    await (db.update(db.inventoryStock)
          ..where((t) => t.id.equals(existing.id)))
        .write(InventoryStockCompanion(
      closingStock: Value(closingStock),
      updatedAt: Value(now),
    ));
    
    // NOTE: We intentionally do NOT update inventory_items.quantity here.
    // The order creation/update transaction already correctly updates it.
  }

  /// Recalculate closing stock for ALL items that have orders on a date.
  /// Called after orders are created/updated/deleted.
  /// 
  /// NOTE: This method ONLY updates inventory_stock.closing_stock, NOT
  /// inventory_items.quantity. See recalculateClosingStock for explanation.
  Future<void> recalculateAllClosingStockForDate(DateTime date) async {
    // Get all stock records for this date
    final stockRecords = await getStockMapForDateRaw(date);
    if (stockRecords.isEmpty) return;

    // Get all ordered quantities for this date
    final orderedQtyMap = await getOrderedQtyMapForDate(date);
    final now = DateTime.now();

    for (final entry in stockRecords.entries) {
      final itemId = entry.key;
      final record = entry.value;
      final orderedQty = orderedQtyMap[itemId] ?? 0;
      final closingStock = record.openingStock - orderedQty;

      await (db.update(db.inventoryStock)
            ..where((t) => t.id.equals(record.id)))
          .write(InventoryStockCompanion(
        closingStock: Value(closingStock),
        updatedAt: Value(now),
      ));
      
      // NOTE: We intentionally do NOT update inventory_items.quantity here.
      // The order creation/update transaction already correctly updates it.
    }
  }

  /// Get the opening stock for all items on a date.
  /// Returns a map of inventoryItemId -> openingStock (0 if no record exists).
  Future<Map<String, double>> getOpeningStockMapForDate(DateTime date) async {
    // Get all non-deleted inventory items
    final items = await (db.select(db.inventoryItems)
          ..where((t) => t.deletedAt.isNull()))
        .get();

    // Get all stock records for this date
    final stockRecords = await getStockMapForDateRaw(date);

    // Build result: use opening_stock if record exists, else 0
    return {
      for (final item in items)
        item.id: stockRecords[item.id]?.openingStock ?? 0,
    };
  }

  /// Get the closing stock (available stock) for all items on a date.
  /// Returns a map of inventoryItemId -> closingStock.
  /// If no stock record exists for that date, returns null (caller can fallback to item.quantity).
  Future<Map<String, double?>> getClosingStockMapForDate(DateTime date) async {
    // Get all non-deleted inventory items
    final items = await (db.select(db.inventoryItems)
          ..where((t) => t.deletedAt.isNull()))
        .get();

    // Get all stock records for this date
    final stockRecords = await getStockMapForDateRaw(date);

    // Build result: use closing_stock if record exists, else null (no record)
    return {
      for (final item in items)
        item.id: stockRecords[item.id]?.closingStock,
    };
  }

  /// Stream opening stock for all items on a given date.
  /// Re-emits when inventory items or stock records change.
  Stream<Map<String, double>> watchOpeningStockForDate(DateTime date) {
    // Watch both inventory items and stock records for this date
    final normalized = _normalizeDate(date);
    
    final itemsStream = (db.select(db.inventoryItems)
          ..where((t) => t.deletedAt.isNull()))
        .watch();
    
    final stockStream = (db.select(db.inventoryStock)
          ..where((t) => t.stockDate.equals(normalized)))
        .watch();

    // Combine the streams
    return itemsStream.asyncMap((_) => getOpeningStockMapForDate(date));
  }

  /// Stream closing stock (available) for all items on a given date.
  /// Re-emits when inventory items or stock records change.
  /// Returns null for items that have no stock record (caller can fallback to item.quantity).
  Stream<Map<String, double?>> watchClosingStockForDate(DateTime date) {
    final normalized = _normalizeDate(date);
    
    // Watch stock records stream for this date
    final stockStream = (db.select(db.inventoryStock)
          ..where((t) => t.stockDate.equals(normalized)))
        .watch();
    
    // Map stock records to closing stock map
    return stockStream.asyncMap((_) => getClosingStockMapForDate(date));
  }
}

/// Placeholder for old InventorySnapshotsRepository references.
/// Will be removed after migration is complete.
typedef InventorySnapshotsRepository = InventoryStockRepository;

class ReplenishmentTemplatesRepository {
  ReplenishmentTemplatesRepository(this.db);

  final AppDatabase db;

  /// Watch all templates.
  Stream<List<ReplenishmentTemplate>> watchAll() {
    return (db.select(db.replenishmentTemplates)
          ..orderBy([(t) => OrderingTerm(expression: t.customerId)]))
        .watch();
  }

  /// Get all templates.
  Future<List<ReplenishmentTemplate>> getAll() {
    return (db.select(db.replenishmentTemplates)
          ..orderBy([(t) => OrderingTerm(expression: t.customerId)]))
        .get();
  }

  /// Get template for a specific customer.
  Future<ReplenishmentTemplate?> getByCustomer(String customerId) {
    return (db.select(db.replenishmentTemplates)
          ..where((t) => t.customerId.equals(customerId)))
        .getSingleOrNull();
  }

  /// Parse the items JSON from a template.
  List<TemplateItem> parseItems(ReplenishmentTemplate template) {
    try {
      final list = jsonDecode(template.items) as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(TemplateItem.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Get items for a customer (convenience method).
  Future<List<TemplateItem>> getItemsForCustomer(String customerId) async {
    final template = await getByCustomer(customerId);
    if (template == null) return [];
    return parseItems(template);
  }

  /// Save (upsert) a template for a customer.
  /// [items] is a map of inventoryItemId -> quantity.
  Future<ReplenishmentTemplate> save({
    required String customerId,
    required Map<String, double> items,
  }) async {
    final now = DateTime.now();
    final itemsList = items.entries
        .where((e) => e.value > 0)
        .map((e) => TemplateItem(inventoryItemId: e.key, quantity: e.value))
        .toList();
    final itemsJson = jsonEncode(itemsList.map((i) => i.toJson()).toList());

    final existing = await getByCustomer(customerId);
    
    if (existing != null) {
      // Update existing
      await (db.update(db.replenishmentTemplates)
            ..where((t) => t.id.equals(existing.id)))
          .write(ReplenishmentTemplatesCompanion(
        items: Value(itemsJson),
        updatedAt: Value(now),
      ));
      return (db.select(db.replenishmentTemplates)
            ..where((t) => t.id.equals(existing.id)))
          .getSingle();
    } else {
      // Insert new
      final id = _uuid.v4();
      await db.into(db.replenishmentTemplates).insert(
            ReplenishmentTemplatesCompanion.insert(
              id: id,
              customerId: customerId,
              items: Value(itemsJson),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return (db.select(db.replenishmentTemplates)
            ..where((t) => t.id.equals(id)))
          .getSingle();
    }
  }

  /// Permanently delete a template.
  Future<void> delete(String id) async {
    await (db.delete(db.replenishmentTemplates)..where((t) => t.id.equals(id)))
        .go();
  }

  /// Delete template for a customer.
  Future<void> deleteByCustomer(String customerId) async {
    await (db.delete(db.replenishmentTemplates)
          ..where((t) => t.customerId.equals(customerId)))
        .go();
  }
}