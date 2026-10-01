import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stock_pilot/database/app_database.dart';
import 'package:stock_pilot/database/repositories.dart';
import 'package:stock_pilot/features/dashboard/dashboard_page.dart';
import 'package:stock_pilot/providers.dart';

class FakeInventoryRepository implements InventoryRepositoryBase {
  @override
  Stream<List<InventoryItem>> watchItems() {
    return Stream.value(<InventoryItem>[]);
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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> addTransaction(
      String itemId,
      double delta,
      String type, {
        required String unit,
        String? notes,
      }) {
    throw UnimplementedError();
  }

  @override
  Stream<List<StockTransaction>> watchHistory(
      String itemId,
      ) {
    throw UnimplementedError();
  }

  @override
  Future<void> ensureDefaultCategories() {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('Dashboard renders', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(
            FakeInventoryRepository(),
          ),
        ],
        child: const MaterialApp(
          home: DashboardPage(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Overview'), findsOneWidget);

    expect(
      find.text(
        'Your inventory and order activity at a glance.',
      ),
      findsOneWidget,
    );

    expect(
      find.text('Inventory Items'),
      findsOneWidget,
    );

    expect(
      find.text('Low Stock'),
      findsOneWidget,
    );

    expect(
      find.text('0'),
      findsNWidgets(2),
    );
  });
}