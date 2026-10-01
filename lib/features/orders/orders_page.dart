import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/repositories.dart';
import '../../providers.dart';

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  String? _society;
  String? _customerId;
  final Map<String, int> _qty = {}; // inventoryItemId -> quantity
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final inventoryRepo = ref.watch(inventoryRepositoryProvider);
    final customersRepo = ref.watch(customersRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 820;
          final form = _buildForm(inventoryRepo, customersRepo);
          final summary = _buildSummary(inventoryRepo, customersRepo);

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: form),
                SizedBox(width: 340, child: summary),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: form),
              summary,
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------
  // FORM: society -> customer -> products grouped by category
  // -------------------------------------------------------------------
  Widget _buildForm(
    InventoryRepositoryBase inventoryRepo,
    CustomersRepository customersRepo,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shop for a customer',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),

          // Select a society (driven by the societies table)
          const Text('Select a society'),
          const SizedBox(height: 4),
          StreamBuilder<List<Society>>(
            stream: ref.watch(societiesRepositoryProvider).watchSocieties(),
            builder: (context, snap) {
              final societies = snap.data ?? const <Society>[];
              final names = societies.map((s) => s.name).toList();
              final current = _society;
              if (current != null && !names.contains(current)) {
                names.add(current);
              }
              return DropdownButtonFormField<String?>(
                initialValue: _society,
                isExpanded: true,
                decoration: const InputDecoration(
                  hintText: 'Choose Society',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Choose Society'),
                  ),
                  ...names.map(
                    (s) =>
                        DropdownMenuItem<String?>(value: s, child: Text(s)),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _society = v;
                  _customerId = null; // refresh customer selection
                }),
              );
            },
          ),
          const SizedBox(height: 16),

          // Select customer (filtered by society)
          const Text('Select customer'),
          const SizedBox(height: 4),
          StreamBuilder<List<Customer>>(
            stream: customersRepo.watchCustomers(),
            builder: (context, snap) {
              var customers =
                  (snap.data ?? const []).where((c) => c.active).toList();
              if (_society != null) {
                customers =
                    customers.where((c) => c.society == _society).toList();
              }
              final validIds = customers.map((c) => c.id).toSet();
              final selected =
                  (_customerId != null && validIds.contains(_customerId))
                      ? _customerId
                      : null;
              return DropdownButtonFormField<String?>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  hintText: 'Choose customer',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Choose customer'),
                  ),
                  ...customers.map(
                    (c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.name),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _customerId = v),
              );
            },
          ),
          const SizedBox(height: 20),

          const Text(
            'Add products',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const Divider(),

          // Products grouped by category
          StreamBuilder<List<InventoryItem>>(
            stream: inventoryRepo.watchItems(),
            builder: (context, itemSnap) {
              final items = (itemSnap.data ?? const [])
                  .where((i) => i.availableForOrdering)
                  .toList();
              if (items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No products available for ordering.'),
                );
              }
              return StreamBuilder<List<Category>>(
                stream: inventoryRepo.watchCategories(),
                builder: (context, catSnap) {
                  final categories = catSnap.data ?? const [];
                  final catName = {
                    for (final c in categories) c.id: c.name,
                  };

                  // Group items by category name.
                  final grouped = <String, List<InventoryItem>>{};
                  for (final it in items) {
                    final key = it.categoryId != null
                        ? (catName[it.categoryId] ?? 'Uncategorized')
                        : 'Uncategorized';
                    grouped.putIfAbsent(key, () => []).add(it);
                  }
                  final sortedKeys = grouped.keys.toList()..sort();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final cat in sortedKeys) ...[
                        Padding(
                          padding:
                              const EdgeInsets.only(top: 12, bottom: 4),
                          child: Text(
                            cat.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        ...grouped[cat]!.map(_productRow),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _productRow(InventoryItem item) {
    final qty = _qty[item.id] ?? 0;
    final maxQty = item.quantity.floor();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '₹${item.price?.toStringAsFixed(2) ?? '0.00'} · '
                  '${item.quantity.toStringAsFixed(0)} available',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed:
                qty > 0 ? () => setState(() => _qty[item.id] = qty - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          Text('$qty'),
          IconButton(
            onPressed: qty < maxQty
                ? () => setState(() => _qty[item.id] = qty + 1)
                : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // SUMMARY PANEL
  // -------------------------------------------------------------------
  Widget _buildSummary(
    InventoryRepositoryBase inventoryRepo,
    CustomersRepository customersRepo,
  ) {
    return StreamBuilder<List<InventoryItem>>(
      stream: inventoryRepo.watchItems(),
      builder: (context, itemSnap) {
        final items = itemSnap.data ?? const [];
        final byId = {for (final i in items) i.id: i};

        final lines = _qty.entries
            .where((e) => e.value > 0 && byId.containsKey(e.key))
            .toList();
        final total = lines.fold<double>(
          0,
          (sum, e) => sum + (byId[e.key]!.price ?? 0) * e.value,
        );

        return StreamBuilder<List<Customer>>(
          stream: customersRepo.watchCustomers(),
          builder: (context, custSnap) {
            final customer = (custSnap.data ?? const [])
                .where((c) => c.id == _customerId)
                .cast<Customer?>()
                .firstWhere((_) => true, orElse: () => null);

            return Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF123D32),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ORDER SUMMARY',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    customer?.name ?? 'No customer selected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (customer == null || lines.isEmpty)
                    const Text(
                      'Choose a customer and add products to see the total.',
                      style: TextStyle(color: Colors.white70),
                    )
                  else ...[
                    ...lines.map((e) {
                      final it = byId[e.key]!;
                      final lineTotal = (it.price ?? 0) * e.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${it.name} × ${e.value}',
                                style:
                                    const TextStyle(color: Colors.white70),
                              ),
                            ),
                            Text(
                              '₹${lineTotal.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(color: Colors.white24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '₹${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF123D32),
                        ),
                        onPressed: _saving
                            ? null
                            : () => _placeOrder(lines, byId),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Place order'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _placeOrder(
    List<MapEntry<String, int>> lines,
    Map<String, InventoryItem> byId,
  ) async {
    setState(() => _saving = true);
    try {
      final orderLines = lines.map((e) {
        final it = byId[e.key]!;
        return NewOrderLine(
          inventoryItemId: it.id,
          quantity: e.value.toDouble(),
          unit: it.unit,
          unitPrice: it.price ?? 0,
        );
      }).toList();

      await ref.read(ordersRepositoryProvider).createOrder(
            customerId: _customerId,
            lines: orderLines,
            status: 'COMPLETED',
          );
      final syncError = await ref.read(syncServiceProvider).autoPush();
      if (mounted) {
        setState(() {
          _qty.clear();
          _customerId = null;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(syncError ?? 'Order placed.'),
            backgroundColor: syncError != null ? Colors.red.shade700 : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }
}
