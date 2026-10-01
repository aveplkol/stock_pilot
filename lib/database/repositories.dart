import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';

const _uuid = Uuid();

abstract class InventoryRepositoryBase {
  Stream<List<InventoryItem>> watchItems();

  Future<InventoryItem> createItem({
    required String name,
    required String unit,
    double quantity,
    double minimumQuantity,
    double? purchasePrice,
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
  Future<InventoryItem> createItem({
    required String name,
    required String unit,
    double quantity = 0,
    double minimumQuantity = 0,
    double? purchasePrice,
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
          notes: Value(notes),
          updatedAt: Value(now),
        ),
      );
    }
  }
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