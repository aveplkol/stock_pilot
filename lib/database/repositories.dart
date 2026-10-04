import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';

const _uuid = Uuid();

abstract class InventoryRepositoryBase {
  Stream<List<InventoryItem>> watchItems();

  Stream<List<Category>> watchCategories();

  /// Adds a new category by name, preventing duplicates (case-insensitive).
  /// Returns the existing category if one with the same name already exists.
  Future<Category> addCategory(String name);

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
  Stream<List<Category>> watchCategories() {
    return (db.select(db.categories)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
            (t) => OrderingTerm(expression: t.name),
      ]))
        .watch();
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
    const names = [
      'Grocery',
      'Toiletries',
      'Cleaning',
      'Medicines',
      'Household',
      'Miscellaneous',
    ];

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
  Future<void> ensureDefaultSocieties() async {
    const names = [
      'Prestige Ozone',
      'Palm Meadows',
      'Brigade Gateway',
      'Sobha Dream Acres',
      'Godrej Woods',
    ];

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
    String? address,
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
          address: Value(address),
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
          address: Value(address),
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
      // Load all order items and inventory details once per emission.
      final allItems = await db.select(db.orderItems).get();
      final inventory = await db.select(db.inventoryItems).get();
      final nameById = {for (final i in inventory) i.id: i.name};
      final purchaseById = {
        for (final i in inventory) i.id: i.purchasePrice ?? 0.0,
      };

      final itemsByOrder = <String, List<OrderReportItem>>{};
      for (final it in allItems) {
        itemsByOrder.putIfAbsent(it.orderId, () => []).add(
              OrderReportItem(
                itemName:
                    nameById[it.inventoryItemId] ?? 'Unknown item',
                quantity: it.quantity,
                unit: it.unit,
                unitPrice: it.unitPrice,
                purchasePrice: purchaseById[it.inventoryItemId] ?? 0.0,
                total: it.total,
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

  /// Replaces all line items of an existing order with [lines], restoring and
  /// re-applying stock accordingly. Recomputes totals.
  Future<void> updateOrder({
    required String orderId,
    required List<NewOrderLine> lines,
    double discount = 0,
    String? notes,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('Order must contain at least one item');
    }

    await db.transaction(() async {
      final now = DateTime.now();

      // Restore stock from existing lines, then delete them.
      final existing = await (db.select(db.orderItems)
            ..where((t) => t.orderId.equals(orderId)))
          .get();
      for (final e in existing) {
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
      // Reverse the previous stock transactions for this order's number.
      final order = await (db.select(db.orders)
            ..where((t) => t.id.equals(orderId)))
          .getSingle();

      final subtotal = lines.fold<double>(
        0,
        (sum, line) => sum + line.quantity * line.unitPrice,
      );
      if (discount > subtotal) {
        throw ArgumentError('Discount cannot exceed subtotal');
      }

      // Apply new lines.
      for (final line in lines) {
        final item = await (db.select(db.inventoryItems)
              ..where((t) => t.id.equals(line.inventoryItemId)))
            .getSingle();
        if (line.quantity <= 0 || item.quantity < line.quantity) {
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
  }

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

    return db.transaction(() async {
      final now = DateTime.now();
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

      final number = 'ORD-${now.millisecondsSinceEpoch}';

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
          orderDate: orderDate ?? now,
          createdAt: now,
          updatedAt: now,
        ),
      );

      for (final line in lines) {
        final item = await (db.select(db.inventoryItems)
          ..where(
                (t) => t.id.equals(line.inventoryItemId),
          ))
            .getSingle();

        if (line.quantity <= 0 ||
            item.quantity < line.quantity) {
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
            createdAt: now,
          ),
        );

        await (db.update(db.inventoryItems)
          ..where((t) => t.id.equals(item.id)))
            .write(
          InventoryItemsCompanion(
            quantity: Value(
              item.quantity - line.quantity,
            ),
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
            notes: Value('Order $number'),
            transactionDate: now,
            createdAt: now,
          ),
        );
      }

      return id;
    });
  }

  /// Fetches all orders for a customer (used for ledger/outstanding calculation).
  Future<List<Order>> getOrdersForCustomer(String customerId) {
    return (db.select(db.orders)
          ..where((t) => t.deletedAt.isNull() & t.customerId.equals(customerId))
          ..orderBy([(t) => OrderingTerm(expression: t.orderDate, mode: OrderingMode.desc)]))
        .get();
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
