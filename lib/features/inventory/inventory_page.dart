import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/product_icons.dart';
import '../../database/app_database.dart';
import '../../providers.dart';
import 'widgets/icon_picker.dart';

/// Returns the emoji to display for a product: the user-selected emoji if
/// present, otherwise one auto-derived from the product's name/category.
String _emojiForItem(InventoryItem item, String? categoryName) {
  if (item.iconName != null && item.iconName!.isNotEmpty) {
    return ProductIcons.resolve(item.iconName);
  }
  return ProductIcons.autoEmojiFor(item.name, categoryName);
}

/// Builds the visual used in a product's header: the user-selected emoji, or
/// the emoji auto-derived from the name/category.
Widget _productGlyph(InventoryItem item, String? categoryName) {
  return Text(
    _emojiForItem(item, categoryName),
    style: const TextStyle(fontSize: 30),
  );
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
  bool _showDeleted = false;

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
        child: _showDeleted
            ? _DeletedItemsView(
                onBack: () => setState(() => _showDeleted = false))
            : StreamBuilder<List<InventoryItem>>(
                stream: repo.watchItems(),
                builder: (context, snapshot) {
                  final allItems = snapshot.data ?? const <InventoryItem>[];
                  final items = _query.isEmpty
                      ? allItems
                      : allItems
                          .where((i) => i.name
                              .toLowerCase()
                              .contains(_query.toLowerCase()))
                          .toList();

                  return StreamBuilder<List<Category>>(
                    stream: repo.watchCategories(),
                    builder: (context, catSnap) {
                      final categories = catSnap.data ?? const [];
                      final catName = {
                        for (final c in categories) c.id: c.name
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

                      return CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Inventory',
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Show deleted items',
                                        icon:
                                            const Icon(Icons.visibility_off),
                                        onPressed: () => setState(
                                            () => _showDeleted = true),
                                      ),
                                      IconButton(
                                        tooltip: 'Manage categories',
                                        icon: const Icon(
                                            Icons.category_outlined),
                                        onPressed: () =>
                                            _openCategoryManager(context),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _SearchAndAdd(
                                    controller: _searchController,
                                    onChanged: (v) =>
                                        setState(() => _query = v),
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
                              child: Center(
                                  child: Text('No inventory items yet')),
                            )
                          else
                            for (final cat in sortedKeys)
                              _categorySliver(
                                context,
                                cat,
                                grouped[cat]!,
                                catName,
                              ),
                          const SliverToBoxAdapter(
                              child: SizedBox(height: 24)),
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

  void _openCategoryManager(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _CategoryManagerDialog(),
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
                child: _productGlyph(item, categoryName),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: InkWell(
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
              if (inStock)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2E7D32),
                      shape: BoxShape.circle,
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

/// A view that lists soft-deleted products with options to restore or
/// permanently delete each one. Shown when the user taps the "show deleted"
/// (crossed-eye) icon in the inventory header.
class _DeletedItemsView extends ConsumerWidget {
  const _DeletedItemsView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(inventoryRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to inventory',
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  'Deleted products',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const Icon(Icons.visibility),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<InventoryItem>>(
            stream: repo.watchDeletedItems(),
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <InventoryItem>[];
              if (items.isEmpty) {
                return const Center(child: Text('No deleted products'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final item = items[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFEAF1E7),
                        child: Text(
                          _emojiForItem(item, null),
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      title: Text(item.name),
                      subtitle: Text(
                        'Deleted ${item.deletedAt?.toLocal().toString().split('.').first ?? ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.restore,
                                color: Colors.green),
                            tooltip: 'Restore',
                            onPressed: () async {
                              await repo.restoreItem(item.id);
                              unawaited(
                                  ref.read(syncServiceProvider).autoPush());
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_forever,
                                color: Colors.red.shade700),
                            tooltip: 'Delete permanently',
                            onPressed: () =>
                                _confirmPurge(context, ref, item),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmPurge(
    BuildContext context,
    WidgetRef ref,
    InventoryItem item,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          'Permanently remove "${item.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(inventoryRepositoryProvider).purgeItem(item.id);
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
  String? _iconName;

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
    _iconName = it?.iconName;
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

  Future<void> _pickIcon() async {
    final result = await showProductIconPicker(context, selected: _iconName);
    if (result == null) return; // cancelled
    setState(() => _iconName = result.isEmpty ? null : result);
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
          iconName: _iconName,
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
          iconName: _iconName,
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
                  // Icon picker row.
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1E7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _iconName != null && _iconName!.isNotEmpty
                              ? ProductIcons.resolve(_iconName)
                              : ProductIcons.autoEmojiFor(
                                  _name.text, null),
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickIcon,
                          icon: const Icon(Icons.emoji_symbols_outlined),
                          label: Text(
                            _iconName == null
                                ? 'Choose an icon'
                                : 'Change icon',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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

/// Dialog listing active and deleted categories with soft-delete, restore
/// and permanent-delete controls.
class _CategoryManagerDialog extends ConsumerWidget {
  const _CategoryManagerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(inventoryRepositoryProvider);
    return AlertDialog(
      title: const Text('Manage categories'),
      content: SizedBox(
        width: 380,
        height: 420,
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<Category>>(
                stream: repo.watchCategories(),
                builder: (context, snap) {
                  final cats = snap.data ?? const <Category>[];
                  return StreamBuilder<List<Category>>(
                    stream: repo.watchDeletedCategories(),
                    builder: (context, delSnap) {
                      final deleted = delSnap.data ?? const <Category>[];
                      if (cats.isEmpty && deleted.isEmpty) {
                        return const Center(child: Text('No categories'));
                      }
                      return ListView(
                        children: [
                          if (cats.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            ...cats.map(
                              (c) => ListTile(
                                dense: true,
                                title: Text(c.name),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete_outline,
                                      color: Colors.red.shade400),
                                  tooltip: 'Delete category',
                                  onPressed: () =>
                                      _confirmDelete(context, ref, c),
                                ),
                              ),
                            ),
                          ],
                          if (deleted.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'DELETED',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            ...deleted.map(
                              (c) => ListTile(
                                dense: true,
                                title: Text(
                                  c.name,
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.restore,
                                          color: Colors.green),
                                      tooltip: 'Restore',
                                      onPressed: () async {
                                        await repo.restoreCategory(c.id);
                                        unawaited(ref
                                            .read(syncServiceProvider)
                                            .autoPush());
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_forever,
                                          color: Colors.red.shade700),
                                      tooltip: 'Delete permanently',
                                      onPressed: () =>
                                          _confirmPurge(context, ref, c),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category c,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('Remove "${c.name}" from categories?'),
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
    await ref.read(inventoryRepositoryProvider).deleteCategory(c.id);
    unawaited(ref.read(syncServiceProvider).autoPush());
  }

  Future<void> _confirmPurge(
    BuildContext context,
    WidgetRef ref,
    Category c,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          'Permanently remove "${c.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(inventoryRepositoryProvider).purgeCategory(c.id);
    unawaited(ref.read(syncServiceProvider).autoPush());
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
