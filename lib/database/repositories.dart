import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';

const _uuid = Uuid();

abstract class InventoryRepositoryBase {
  Stream<List<InventoryItem>> watchItems();

  Stream<List<Category>> watchCategories();

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

  /// Adds a new society by name. If a (non-deleted) society with the same
  /// name already exists it is returned instead of creating a duplicate.
  Future<Society> addSociety(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Society name cannot be empty');
    }

    final existing = await (db.select(db.societies)
          ..where((t) => t.deletedAt.isNull() & t.name.equals(trimmed)))
        .get();
    if (existing.isNotEmpty) {
      return existing.first;
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
            (t) => OrderingTerm(
          expression: t.name,
        ),
      ]))
        .watch();
  }

  Future<void> save({
    String? id,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? society,
    bool active = true,
    String? notes,
  }) async {
    final now = DateTime.now();

    if (id == null) {
      await db.into(db.customers).insert(
        CustomersCompanion.insert(
          id: _uuid.v4(),
          name: name,
          phone: Value(phone),
          email: Value(email),
          address: Value(address),
          society: Value(society),
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
    required this.total,
  });

  final String itemName;
  final double quantity;
  final String unit;
  final double total;
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
      // Load all order items and inventory names once per emission.
      final allItems = await db.select(db.orderItems).get();
      final inventory = await db.select(db.inventoryItems).get();
      final nameById = {for (final i in inventory) i.id: i.name};

      final itemsByOrder = <String, List<OrderReportItem>>{};
      for (final it in allItems) {
        itemsByOrder.putIfAbsent(it.orderId, () => []).add(
              OrderReportItem(
                itemName:
                    nameById[it.inventoryItemId] ?? 'Unknown item',
                quantity: it.quantity,
                unit: it.unit,
                total: it.total,
              ),
            );
      }

      return rows.map((row) {
        final order = row.readTable(db.orders);
        final customer = row.readTableOrNull(db.customers);
        return OrderReportRow(
          orderId: order.id,
          orderNumber: order.orderNumber,
          orderDate: order.orderDate,
          total: order.total,
          customerId: order.customerId,
          customerName: customer?.name ?? 'Walk-in / Unknown',
          society: (customer?.society == null || customer!.society!.isEmpty)
              ? 'No society'
              : customer.society!,
          items: itemsByOrder[order.id] ?? const [],
        );
      }).toList();
    });
  }

  Future<String> createOrder({
    String? customerId,
    required List<NewOrderLine> lines,
    String status = 'DRAFT',
    double discount = 0,
    String? notes,
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
          orderDate: now,
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
}