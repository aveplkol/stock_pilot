import 'package:drift/drift.dart';

class Societies extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}

class InventoryItems extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get categoryId => text().nullable()();
  RealColumn get quantity => real().withDefault(const Constant(0))();
  TextColumn get unit => text()();
  RealColumn get minimumQuantity => real().withDefault(const Constant(0))();
  RealColumn get purchasePrice => real().nullable()();
  RealColumn get price => real().nullable()();
  BoolColumn get availableForOrdering =>
      boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  // Material icon code point name chosen by the user to represent the
  // product in lists/cards. Nullable; the UI falls back to an emoji/box
  // when not set.
  TextColumn get iconName => text().nullable()();
  // Default daily incoming stock quantity from the supplier. Used by the
  // "Default Stock" button to quickly record daily purchases.
  RealColumn get defaultQuantity => real().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}

class StockTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get inventoryItemId => text()();
  TextColumn get transactionType => text()();
  RealColumn get quantity => real()();
  TextColumn get unit => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get transactionDate => dateTime()();
  TextColumn get deviceId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}

class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  // Customer name is now optional (a flat number + block identifies them).
  TextColumn get name => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  // `block` holds the Block Name (e.g. "ALDINA", "D-Block") — mandatory
  // in the UI. (Renamed from the legacy `address` column.)
  TextColumn get block => text().nullable()();
  // `society` stores the society ID (foreign key to societies.id).
  TextColumn get society => text().nullable()();
  // Flat / house number within the block (mandatory in the UI).
  TextColumn get flatNumber => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}

class Orders extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get orderNumber => text()();
  TextColumn get status => text()();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get orderDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}

class OrderItems extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text()();
  TextColumn get inventoryItemId => text()();
  RealColumn get quantity => real()();
  TextColumn get unit => text()();
  RealColumn get unitPrice => real()();
  RealColumn get total => real()();
  DateTimeColumn get createdAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}

class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get customerId => text()();
  RealColumn get amount => real()();
  TextColumn get paymentMode => text()(); // UPI, Cash, Cheque, Bank Transfer
  TextColumn get reference => text().nullable()(); // e.g. UPI ref, cheque number
  TextColumn get notes => text().nullable()();
  DateTimeColumn get paymentDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}

/// Stores the default order template for a customer.
/// Used by the "Order Templates" feature to auto-generate daily orders.
/// One row per customer. The `items` column stores a JSON array of
/// {inventoryItemId, quantity} pairs.
class ReplenishmentTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get customerId => text()();
  /// JSON array of items: [{"id": "inventoryItemId", "qty": 2}, ...]
  TextColumn get items => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}

/// Daily inventory stock records capturing opening and closing stock for each item
/// per date. Used for date-based inventory management and order fulfillment.
/// One row per inventory item per date.
/// 
/// - `openingStock`: The stock available at the start of the day (set via 
///   "Default Stock" button or manual edit on the card).
/// - `closingStock`: Always computed as `openingStock - total_ordered_for_this_date`.
class InventoryStock extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get companyCode => text().nullable()();
  TextColumn get inventoryItemId => text()();
  /// The date for this stock record (stored as DateTime at midnight UTC).
  DateTimeColumn get stockDate => dateTime()();
  /// Stock at the start of the day (set when Default Stock is applied or
  /// when stock is manually adjusted for that date).
  RealColumn get openingStock => real().withDefault(const Constant(0))();
  /// Stock at the end of the day after orders are deducted.
  /// Always = openingStock - sum(order_items.quantity for orders on this date).
  RealColumn get closingStock => real().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
