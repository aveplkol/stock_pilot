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
  // Legacy "address" column (kept for back-compat; no longer surfaced).
  TextColumn get address => text().nullable()();
  // `society` holds the Block Name (mandatory in the UI).
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
