import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../providers.dart';

/// Picks a representative emoji for a product from its name/category.
String _emojiFor(String name, String? category) {
  final n = name.toLowerCase();
  final c = (category ?? '').toLowerCase();
  bool has(String s) => n.contains(s) || c.contains(s);

  if (has('milk')) return '🥛';
  if (has('bread') || has('loaf') || has('bakery')) return '🍞';
  if (has('egg')) return '🥚';
  if (has('rice')) return '🍚';
  if (has('oil')) return '🫗';
  if (has('water')) return '💧';
  if (has('fruit') || has('apple')) return '🍎';
  if (has('vegetable') || has('veg')) return '🥦';
  if (has('tea')) return '🍵';
  if (has('coffee')) return '☕';
  if (has('sugar') || has('salt') || has('pantry')) return '🧂';
  if (has('clean')) return '🧼';
  if (has('medicine') || has('medicines')) return '💊';
  if (has('household')) return '🧺';
  return '📦';
}

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(inventoryRepositoryProvider).ensureDefaultCategories();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(inventoryRepositoryProvider);

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<InventoryItem>>(
          stream: repo.watchItems(),
          builder: (context, snapshot) {
            final allItems = snapshot.data ?? const <InventoryItem>[];
            final items = _query.isEmpty
                ? allItems
                : allItems
                    .where((i) =>
                        i.name.toLowerCase().contains(_query.toLowerCase()))
                    .toList();

            return StreamBuilder<List<Category>>(
              stream: repo.watchCategories(),
              builder: (context, catSnap) {
                final categories = catSnap.data ?? const [];
                final catName = {for (final c in categories) c.id: c.name};

                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inventory',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 20),
                            _SearchAndAdd(
                              controller: _searchController,
                              onChanged: (v) => setState(() => _query = v),
                              onAdd: () => _openDialog(context),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    if (items.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: Text('No inventory items yet')),
                      )
                    else
                      SliverPadding(
                        padding:
                            const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.crossAxisExtent;
                            final cols = w >= 1100
                                ? 4
                                : w >= 820
                                    ? 3
                                    : w >= 560
                                        ? 2
                                        : 1;
                            return SliverGrid(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                mainAxisExtent: 330,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) {
                                  final item = items[i];
                                  return _ProductCard(
                                    item: item,
                                    categoryName:
                                        catName[item.categoryId],
                                    onEdit: () =>
                                        _openDialog(context, item: item),
                                  );
                                },
                                childCount: items.length,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
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

class _SearchAndAdd extends StatelessWidget {
  const _SearchAndAdd({
    required this.controller,
    required this.onChanged,
    required this.onAdd,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final searchField = TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: const InputDecoration(
        hintText: 'Search products',
        prefixIcon: Icon(Icons.search),
      ),
    );

    final addButton = FilledButton.icon(
      onPressed: onAdd,
      icon: const Icon(Icons.add),
      label: const Text('Add product'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: 12),
              addButton,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 16),
            addButton,
          ],
        );
      },
    );
  }
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({
    required this.item,
    required this.categoryName,
    required this.onEdit,
  });

  final InventoryItem item;
  final String? categoryName;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(inventoryRepositoryProvider);
    final inStock = item.quantity > 0;
    final low = item.quantity <= item.minimumQuantity;
    final qtyLabel = '${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} in stock';

    Future<void> adjust(double delta, String type) async {
      if (delta < 0 && item.quantity <= 0) return;
      await repo.addTransaction(item.id, delta, type, unit: item.unit);
      unawaited(ref.read(syncServiceProvider).autoPush());
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tinted image header with status/delete.
          Stack(
            children: [
              Container(
                height: 120,
                width: double.infinity,
                color: const Color(0xFFEAF1E7),
                alignment: Alignment.center,
                child: Text(
                  _emojiFor(item.name, categoryName),
                  style: const TextStyle(fontSize: 56),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: inStock
                    ? Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2E7D32),
                          shape: BoxShape.circle,
                        ),
                      )
                    : InkWell(
                        onTap: () => _confirmDelete(context, ref),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.red.shade400,
                          ),
                        ),
                      ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (categoryName ?? 'Uncategorized'),
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '₹${item.price?.toStringAsFixed(2) ?? '0.00'}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      qtyLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: (!inStock || low)
                            ? Colors.orange.shade800
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _QtyStepper(
                  value: item.quantity,
                  onDecrement:
                      item.quantity > 0 ? () => adjust(-1, 'USED') : null,
                  onIncrement: () => adjust(1, 'PURCHASE'),
                  onSet: (v) async {
                    await repo.setQuantity(item.id, v);
                    unawaited(ref.read(syncServiceProvider).autoPush());
                  },
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: onEdit,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Edit details & photo',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.north_east,
                        size: 16,
                        color: Colors.green.shade700,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove "${item.name}" from inventory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(inventoryRepositoryProvider).deleteItem(item.id);
    unawaited(ref.read(syncServiceProvider).autoPush());
  }
}

/// A "− value +" stepper where the value is also directly editable.
class _QtyStepper extends StatefulWidget {
  const _QtyStepper({
    required this.value,
    required this.onIncrement,
    required this.onDecrement,
    required this.onSet,
  });

  final double value;
  final VoidCallback onIncrement;
  final VoidCallback? onDecrement;
  final ValueChanged<double> onSet;

  @override
  State<_QtyStepper> createState() => _QtyStepperState();
}

class _QtyStepperState extends State<_QtyStepper> {
  late final TextEditingController _controller;
  final _focus = FocusNode();

  String get _text => widget.value % 1 == 0
      ? widget.value.toInt().toString()
      : widget.value.toString();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _text);
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _QtyStepper old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _controller.text != _text) {
      _controller.text = _text;
    }
  }

  void _commit() {
    final v = double.tryParse(_controller.text.trim());
    if (v == null || v < 0) {
      _controller.text = _text;
      return;
    }
    if (v != widget.value) widget.onSet(v);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _roundBtn(
          icon: Icons.remove,
          onPressed: widget.onDecrement,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
              onSubmitted: (_) => _commit(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _roundBtn(
          icon: Icons.add,
          onPressed: widget.onIncrement,
        ),
      ],
    );
  }

  Widget _roundBtn({required IconData icon, VoidCallback? onPressed}) {
    final enabled = onPressed != null;
    return Material(
      color: const Color(0xFFEAF1E7),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            color: enabled ? const Color(0xFF123D32) : Colors.grey.shade400,
          ),
        ),
      ),
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
  late final TextEditingController _purchasePrice;
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
    _purchasePrice = TextEditingController(
      text: it?.purchasePrice != null
          ? it!.purchasePrice!.toStringAsFixed(2)
          : '',
    );
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
    _purchasePrice.dispose();
    _price.dispose();
    _quantity.dispose();
    _minimum.dispose();
    super.dispose();
  }

  Future<void> _save(List<Category> categories) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final repo = ref.read(inventoryRepositoryProvider);
    final purchasePrice = double.tryParse(_purchasePrice.text.trim());
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
          purchasePrice: purchasePrice,
          notes: widget.item!.notes,
        );
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
          purchasePrice: purchasePrice,
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
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _purchasePrice,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Purchase price (₹)',
                          ),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (s.isEmpty) return null;
                            final value = double.tryParse(s);
                            if (value == null || value < 0) {
                              return 'Invalid';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _price,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Sell price (₹)',
                          ),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (s.isEmpty) return null;
                            final value = double.tryParse(s);
                            if (value == null || value < 0) {
                              return 'Invalid';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
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
