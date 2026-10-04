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
  final Set<String> _collapsed = {}; // collapsed category keys

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

                // Group items by category name.
                final grouped = <String, List<InventoryItem>>{};
                for (final it in items) {
                  final key = it.categoryId != null
                      ? (catName[it.categoryId] ?? 'Uncategorized')
                      : 'Uncategorized';
                  grouped.putIfAbsent(key, () => []).add(it);
                }
                final sortedKeys = grouped.keys.toList()..sort();

                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                            const SizedBox(height: 16),
                            _SearchAndAdd(
                              controller: _searchController,
                              onChanged: (v) => setState(() => _query = v),
                              onAdd: () => _openDialog(context),
                            ),
                            const SizedBox(height: 12),
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
                      for (final cat in sortedKeys)
                        _categorySliver(
                          context,
                          cat,
                          grouped[cat]!,
                          catName,
                        ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _categorySliver(
    BuildContext context,
    String cat,
    List<InventoryItem> items,
    Map<String, String> catName,
  ) {
    final collapsed = _collapsed.contains(cat);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: InkWell(
            onTap: () => setState(() {
              if (collapsed) {
                _collapsed.remove(cat);
              } else {
                _collapsed.add(cat);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                    color: Colors.grey.shade700,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      cat.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Text(
                    '${items.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!collapsed)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.crossAxisExtent;
                // Smaller tiles → more per row.
                final cols = w >= 1200
                    ? 5
                    : w >= 900
                        ? 4
                        : w >= 620
                            ? 3
                            : 2;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 196,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final item = items[i];
                      return _ProductCard(
                        item: item,
                        categoryName: catName[item.categoryId],
                        onEdit: () => _openDialog(context, item: item),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: 10),
              addButton,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 12),
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
    final qtyLabel =
        '${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} '
        'in stock';

    Future<void> adjust(double delta, String type) async {
      if (delta < 0 && item.quantity <= 0) return;
      await repo.addTransaction(item.id, delta, type, unit: item.unit);
      unawaited(ref.read(syncServiceProvider).autoPush());
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 56,
                width: double.infinity,
                color: const Color(0xFFEAF1E7),
                alignment: Alignment.center,
                child: Text(
                  _emojiFor(item.name, categoryName),
                  style: const TextStyle(fontSize: 30),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: inStock
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2E7D32),
                          shape: BoxShape.circle,
                        ),                      )
                    : InkWell(
                        onTap: () => _confirmDelete(context, ref),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(4),
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
                            size: 16,
                            color: Colors.red.shade400,
                          ),
                        ),
                      ),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (categoryName ?? 'Uncategorized'),
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '\u20b9${item.price?.toStringAsFixed(2) ?? '0.00'}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        qtyLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: (!inStock || low)
                              ? Colors.orange.shade800
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      _miniBtn(
                        icon: Icons.remove,
                        onPressed: item.quantity > 0
                            ? () => adjust(-1, 'USED')
                            : null,
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      _miniBtn(
                        icon: Icons.add,
                        onPressed: () => adjust(1, 'PURCHASE'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: onEdit,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.north_east,
                          size: 13,
                          color: Colors.green.shade700,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniBtn({required IconData icon, VoidCallback? onPressed}) {
    final enabled = onPressed != null;
    return Material(
      color: const Color(0xFFEAF1E7),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            icon,
            size: 18,
            color: enabled ? const Color(0xFF123D32) : Colors.grey.shade400,
          ),
        ),
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
              syncError ?? (_isEdit ? 'Product updated.' : 'Product added.'),
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

  Future<void> _promptAddCategory() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _AddCategoryDialog(),
    );

    if (name == null || name.isEmpty) return;

    try {
      final category =
          await ref.read(inventoryRepositoryProvider).addCategory(name);
      // Select the newly created category and push it to the cloud.
      if (mounted) setState(() => _categoryId = category.id);
      unawaited(ref.read(syncServiceProvider).autoPush());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Category "${category.name}" added.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red.shade700,
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
                            labelText: 'Purchase price (\u20b9)',
                          ),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (s.isEmpty) return null;
                            final value = double.tryParse(s);
                            if (value == null || value < 0) return 'Invalid';
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
                            labelText: 'Sell price (\u20b9)',
                          ),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (s.isEmpty) return null;
                            final value = double.tryParse(s);
                            if (value == null || value < 0) return 'Invalid';
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
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: selected,
                          isExpanded: true,
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
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Add new category',
                        icon: const Icon(Icons.add),
                        onPressed: _promptAddCategory,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Available for ordering'),
                    value: _available,
                    onChanged: (v) => setState(() => _available = v ?? true),
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
                  : const Text('Save product'),
            ),
          ],
        );
      },
    );
  }
}

/// Small dialog that collects a new category name. It owns its own
/// [TextEditingController] and disposes it safely in [dispose] (after the
/// dialog's exit animation), avoiding "used after being disposed" errors.
class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog();

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add category'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Category name'),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Required' : null,
          onFieldSubmitted: (_) {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _controller.text.trim());
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _controller.text.trim());
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
