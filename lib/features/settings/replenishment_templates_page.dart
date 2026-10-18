import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/repositories.dart';
import '../../providers.dart';
import '../customers/customers_page.dart' show customerLabel;

/// Order Templates page — allows setting default product quantities per customer.
/// These templates are used by "Today's Orders" to auto-generate orders.
class ReplenishmentTemplatesPage extends ConsumerStatefulWidget {
  const ReplenishmentTemplatesPage({super.key});

  @override
  ConsumerState<ReplenishmentTemplatesPage> createState() =>
      _ReplenishmentTemplatesPageState();
}

class _ReplenishmentTemplatesPageState
    extends ConsumerState<ReplenishmentTemplatesPage> {
  String? _society;
  String? _block;
  String? _customerId;
  final Map<String, int> _qty = {}; // inventoryItemId -> quantity
  final Set<String> _collapsed = {}; // collapsed category keys
  bool _initializedCollapse = false;
  bool _saving = false;
  bool _loadingExisting = false;
  bool _hasExistingTemplate = false;

  Future<void> _loadExistingTemplate() async {
    final customerId = _customerId;
    if (customerId == null) {
      setState(() {
        _qty.clear();
        _hasExistingTemplate = false;
      });
      return;
    }
    setState(() => _loadingExisting = true);
    final repo = ref.read(replenishmentTemplatesRepositoryProvider);
    final template = await repo.getByCustomer(customerId);
    if (!mounted) return;
    setState(() {
      _qty.clear();
      _hasExistingTemplate = template != null;
      if (template != null) {
        final items = repo.parseItems(template);
        for (final item in items) {
          _qty[item.inventoryItemId] = item.quantity.round();
        }
      }
      _loadingExisting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final inventoryRepo = ref.watch(inventoryRepositoryProvider);
    final customersRepo = ref.watch(customersRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Order Templates')),
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
                SizedBox(width: 360, child: summary),
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
            'Set default order for a customer',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'These quantities will be used to auto-generate daily orders.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),

          // 1) Society selection.
          const Text('Select a society'),
          const SizedBox(height: 4),
          StreamBuilder<List<Society>>(
            stream: ref.watch(societiesRepositoryProvider).watchSocieties(),
            builder: (context, snap) {
              final societies = snap.data ?? const <Society>[];
              final ids = societies.map((s) => s.id).toSet();
              final current =
                  (_society != null && ids.contains(_society)) ? _society : null;
              return DropdownButtonFormField<String?>(
                value: current,
                isExpanded: true,
                decoration: const InputDecoration(hintText: 'Choose society'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Choose society'),
                  ),
                  ...societies.map(
                    (s) => DropdownMenuItem<String?>(
                      value: s.id,
                      child: Text(s.name),
                    ),
                  ),
                ],
                onChanged: (v) {
                  setState(() {
                    _society = v;
                    _block = null;
                    _customerId = null;
                    _qty.clear();
                    _hasExistingTemplate = false;
                  });
                },
              );
            },
          ),
          const SizedBox(height: 16),

          // 2) Block selection (distinct blocks within the society).
          const Text('Select a block'),
          const SizedBox(height: 4),
          StreamBuilder<List<Customer>>(
            stream: customersRepo.watchCustomers(),
            builder: (context, snap) {
              final all =
                  (snap.data ?? const []).where((c) => c.active).toList();
              final inSociety = _society == null
                  ? all
                  : all.where((c) => c.society == _society).toList();
              final blocks = <String>{
                for (final c in inSociety)
                  if ((c.block ?? '').trim().isNotEmpty) c.block!.trim(),
              }.toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
              final current = _block;
              if (current != null && !blocks.contains(current)) {
                blocks.add(current);
              }
              return DropdownButtonFormField<String?>(
                value: _block,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: _society == null
                      ? 'Choose a society first'
                      : 'Choose block',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Choose block'),
                  ),
                  ...blocks.map(
                    (s) => DropdownMenuItem<String?>(value: s, child: Text(s)),
                  ),
                ],
                onChanged: _society == null
                    ? null
                    : (v) {
                        setState(() {
                          _block = v;
                          _customerId = null;
                          _qty.clear();
                          _hasExistingTemplate = false;
                        });
                      },
              );
            },
          ),
          const SizedBox(height: 16),

          // 3) Customer selection (filtered by society + block).
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
              if (_block != null) {
                customers = customers
                    .where((c) => (c.block ?? '').trim() == _block)
                    .toList();
              }
              customers.sort((a, b) => (a.flatNumber ?? '')
                  .trim()
                  .toLowerCase()
                  .compareTo((b.flatNumber ?? '').trim().toLowerCase()));
              final validIds = customers.map((c) => c.id).toSet();
              final selected =
                  (_customerId != null && validIds.contains(_customerId))
                      ? _customerId
                      : null;
              return DropdownButtonFormField<String?>(
                value: selected,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: _society == null
                      ? 'Choose a society first'
                      : 'Choose customer',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Choose customer'),
                  ),
                  ...customers.map(
                    (c) => DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(customerLabel(c)),
                    ),
                  ),
                ],
                onChanged: (v) async {
                  setState(() => _customerId = v);
                  await _loadExistingTemplate();
                },
              );
            },
          ),

          if (_hasExistingTemplate)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.bookmark_outline,
                        color: Colors.blue.shade800, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Template exists for this customer. Changes will update it.',
                        style: TextStyle(color: Colors.blue.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),
          const Text(
            'Set default quantities',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const Divider(),

          if (_loadingExisting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _buildProductCategories(inventoryRepo),
        ],
      ),
    );
  }

  Widget _buildProductCategories(InventoryRepositoryBase inventoryRepo) {
    return StreamBuilder<List<InventoryItem>>(
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
            final catName = {for (final c in categories) c.id: c.name};

            final grouped = <String, List<InventoryItem>>{};
            for (final it in items) {
              final key = it.categoryId != null
                  ? (catName[it.categoryId] ?? 'Uncategorized')
                  : 'Uncategorized';
              grouped.putIfAbsent(key, () => []).add(it);
            }
            final sortedKeys = grouped.keys.toList()..sort();
            // Collapse all categories by default on the first data load.
            if (!_initializedCollapse && sortedKeys.isNotEmpty) {
              _initializedCollapse = true;
              _collapsed.addAll(sortedKeys);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final cat in sortedKeys)
                  _CategorySection(
                    title: cat,
                    expanded: !_collapsed.contains(cat),
                    itemCount: grouped[cat]!.length,
                    onToggle: () => setState(() {
                      if (_collapsed.contains(cat)) {
                        _collapsed.remove(cat);
                      } else {
                        _collapsed.add(cat);
                      }
                    }),
                    children: grouped[cat]!.map(_productRow).toList(),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _productRow(InventoryItem item) {
    final qty = _qty[item.id] ?? 0;
    // For templates, we allow any quantity (not limited by stock)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
                  '\u20b9${item.price?.toStringAsFixed(2) ?? '0.00'} per ${item.unit}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed:
                qty > 0 ? () => setState(() => _qty[item.id] = qty - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          Text('$qty', style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _qty[item.id] = qty + 1),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

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

            final isEditing = _hasExistingTemplate;

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
                  Text(
                    isEditing ? 'UPDATE TEMPLATE' : 'TEMPLATE SUMMARY',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    customer == null
                        ? 'No customer selected'
                        : customerLabel(customer),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Daily order template',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (customer == null || lines.isEmpty)
                    const Text(
                      'Choose a customer and set quantities to create a template.',
                      style: TextStyle(color: Colors.white70),
                    )
                  else ...[
                    ...lines.map((e) {
                      final it = byId[e.key]!;
                      final lineTotal = (it.price ?? 0) * e.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${it.name} \u00d7 ${e.value}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                            Text(
                              '\u20b9${lineTotal.toStringAsFixed(2)}',
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
                          'Est. Daily Total',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '\u20b9${total.toStringAsFixed(2)}',
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
                        onPressed: _saving ? null : () => _saveTemplate(lines, byId),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(isEditing ? 'Update template' : 'Save template'),
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

  Future<void> _saveTemplate(
    List<MapEntry<String, int>> lines,
    Map<String, InventoryItem> byId,
  ) async {
    final customerId = _customerId;
    if (customerId == null) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(replenishmentTemplatesRepositoryProvider);

      // Build the items map from the lines
      final items = <String, double>{
        for (final entry in lines) entry.key: entry.value.toDouble(),
      };

      // Save the template (creates or updates)
      await repo.save(customerId: customerId, items: items);

      final syncError = await ref.read(syncServiceProvider).autoPush();
      if (mounted) {
        setState(() {
          _hasExistingTemplate = lines.isNotEmpty;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(syncError ?? 'Template saved successfully.'),
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

/// A collapsible category block for the template builder.
class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.title,
    required this.expanded,
    required this.itemCount,
    required this.onToggle,
    required this.children,
  });

  final String title;
  final bool expanded;
  final int itemCount;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  color: Colors.grey.shade700,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Text(
                  '$itemCount',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...children,
        const Divider(height: 1),
      ],
    );
  }
}
