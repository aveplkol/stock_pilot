import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../providers.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(inventoryRepositoryProvider).ensureDefaultCategories();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(inventoryRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: StreamBuilder<List<InventoryItem>>(
        stream: repo.watchItems(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('No inventory items yet'));
          }
          return StreamBuilder<List<Category>>(
            stream: repo.watchCategories(),
            builder: (context, catSnap) {
              final categories = catSnap.data ?? const [];
              final catName = {for (final c in categories) c.id: c.name};

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final item = items[i];
                  final low = item.quantity <= item.minimumQuantity;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                low
                                    ? Icons.warning_amber
                                    : Icons.inventory_2_outlined,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if (item.categoryId != null &&
                                            catName[item.categoryId] != null)
                                          catName[item.categoryId]!,
                                        if (item.price != null)
                                          '₹${item.price!.toStringAsFixed(2)}',
                                        '${item.quantity} ${item.unit}'
                                            '${low ? ' • Low' : ''}',
                                        if (!item.availableForOrdering)
                                          'Not orderable',
                                      ].join('  •  '),
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () =>
                                    _openDialog(context, item: item),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: 'Use 1',
                                onPressed: item.quantity > 0
                                    ? () async {
                                        await repo.addTransaction(
                                          item.id,
                                          -1,
                                          'USED',
                                          unit: item.unit,
                                        );
                                        unawaited(
                                          ref
                                              .read(syncServiceProvider)
                                              .autoPush(),
                                        );
                                      }
                                    : null,
                                icon: const Icon(Icons.remove),
                              ),
                              Text('${item.quantity}'),
                              IconButton(
                                tooltip: 'Purchase 1',
                                onPressed: () async {
                                  await repo.addTransaction(
                                    item.id,
                                    1,
                                    'PURCHASE',
                                    unit: item.unit,
                                  );
                                  unawaited(
                                    ref.read(syncServiceProvider).autoPush(),
                                  );
                                },
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add product'),
      ),
    );
  }

  void _openDialog(BuildContext context, {InventoryItem? item}) {
    showDialog<void>(
      context: context,
      builder: (_) => _ProductDialog(item: item),
    );
  }
}

class _ProductDialog extends ConsumerStatefulWidget {
  const _ProductDialog({this.item});

  final InventoryItem? item;

  @override
  ConsumerState<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends ConsumerState<_ProductDialog> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _quantity;
  late final TextEditingController _minimum;
  final _formKey = GlobalKey<FormState>();

  String _unit = 'pcs';
  String? _categoryId;
  bool _available = true;
  bool _saving = false;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _name = TextEditingController(text: it?.name ?? '');
    _price = TextEditingController(
      text: it?.price != null ? it!.price!.toStringAsFixed(2) : '',
    );
    _quantity = TextEditingController(
      text: it != null ? it.quantity.toStringAsFixed(0) : '0',
    );
    _minimum = TextEditingController(
      text: it != null ? it.minimumQuantity.toStringAsFixed(0) : '0',
    );
    _unit = it?.unit ?? 'pcs';
    _categoryId = it?.categoryId;
    _available = it?.availableForOrdering ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _quantity.dispose();
    _minimum.dispose();
    super.dispose();
  }

  Future<void> _save(List<Category> categories) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final repo = ref.read(inventoryRepositoryProvider);
    final price = double.tryParse(_price.text.trim());
    final minimum = double.tryParse(_minimum.text.trim()) ?? 0;

    try {
      if (_isEdit) {
        await repo.updateItem(
          id: widget.item!.id,
          name: _name.text.trim(),
          unit: _unit,
          minimumQuantity: minimum,
          price: price,
          availableForOrdering: _available,
          categoryId: _categoryId,
          purchasePrice: widget.item!.purchasePrice,
          notes: widget.item!.notes,
        );
        // Apply any manual quantity change as an ADJUSTMENT transaction.
        final target = double.tryParse(_quantity.text.trim());
        if (target != null && target != widget.item!.quantity) {
          await repo.setQuantity(widget.item!.id, target);
        }
      } else {
        await repo.createItem(
          name: _name.text.trim(),
          unit: _unit,
          quantity: double.tryParse(_quantity.text.trim()) ?? 0,
          minimumQuantity: minimum,
          price: price,
          availableForOrdering: _available,
          categoryId: _categoryId,
        );
      }
      final syncError = await ref.read(syncServiceProvider).autoPush();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              syncError ??
                  (_isEdit ? 'Product updated.' : 'Product added.'),
            ),
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Category>>(
      stream: ref.watch(inventoryRepositoryProvider).watchCategories(),
      builder: (context, snap) {
        final categories = snap.data ?? const [];
        // Ensure selected category is valid.
        final validIds = categories.map((c) => c.id).toSet();
        final selected =
            (_categoryId != null && validIds.contains(_categoryId))
                ? _categoryId
                : null;

        return AlertDialog(
          title: Text(_isEdit ? 'Edit product' : 'Add a product'),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _name,
                    decoration:
                        const InputDecoration(labelText: 'Product name'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Price (₹)'),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return null;
                      final value = double.tryParse(s);
                      if (value == null || value < 0) {
                        return 'Enter a valid price';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _quantity,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Stock quantity',
                          ),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (s.isEmpty) return null;
                            final value = double.tryParse(s);
                            if (value == null || value < 0) {
                              return 'Enter a valid quantity';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _unit,
                          decoration:
                              const InputDecoration(labelText: 'Unit'),
                          items: const [
                            'pcs',
                            'kg',
                            'g',
                            'litre',
                            'ml',
                            'pack',
                            'box',
                            'bottle',
                          ]
                              .map((u) => DropdownMenuItem(
                                    value: u,
                                    child: Text(u),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _unit = v ?? 'pcs'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: selected,
                    decoration:
                        const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Uncategorized'),
                      ),
                      ...categories.map(
                        (c) => DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(c.name),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Available for ordering'),
                    value: _available,
                    onChanged: (v) =>
                        setState(() => _available = v ?? true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _saving ? null : () => _save(categories),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? 'Save product' : 'Save product'),
            ),
          ],
        );
      },
    );
  }
}
