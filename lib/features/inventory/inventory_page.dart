import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/product_icons.dart';
import '../../database/app_database.dart';
import '../../providers.dart';
import 'widgets/icon_picker.dart';

/// Simple date formatter without intl dependency.
String _formatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final weekday = weekdays[date.weekday - 1];
  final day = date.day.toString().padLeft(2, '0');
  final month = months[date.month - 1];
  final year = date.year;
  return '$weekday, $day $month $year';
}

/// Returns the emoji to display for a product.
String _emojiForItem(InventoryItem item, String? categoryName) {
  if (item.iconName != null && item.iconName!.isNotEmpty) {
    return ProductIcons.resolve(item.iconName);
  }
  return ProductIcons.autoEmojiFor(item.name, categoryName);
}

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
  final _scrollController = ScrollController();
  String _query = '';
  final Set<String> _collapsed = {};
  bool _showDeleted = false;
  DateTime _selectedDate = DateTime.now();
  bool _applyingDefaultStock = false;
  int _stockRefreshKey = 0; // Incremented to force stock refresh

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

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
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _showApplyDefaultStockDialog() async {
    final result = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => _ApplyDefaultStockDialog(initialDate: _selectedDate),
    );
    if (result == null) return;

    setState(() => _applyingDefaultStock = true);
    try {
      final stockRepo = ref.read(inventoryStockRepositoryProvider);
      
      // Check if already applied
      final alreadyApplied = await stockRepo.hasDefaultStockBeenApplied(result);
      if (alreadyApplied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Default stock was already applied for ${_formatDate(result)}.'),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        }
        return;
      }

      final count = await stockRepo.applyDefaultStock(result);
      // Update selected date to the applied date and refresh
      setState(() {
        _selectedDate = result;
        _stockRefreshKey++;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Default stock applied to $count items for ${_formatDate(result)}.'),
            backgroundColor: Colors.green.shade700,
          ),
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
    } finally {
      if (mounted) {
        setState(() => _applyingDefaultStock = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(inventoryRepositoryProvider);
    final stockRepo = ref.watch(inventoryStockRepositoryProvider);

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

                      final grouped = <String, List<InventoryItem>>{};
                      for (final it in items) {
                        final key = it.categoryId != null
                            ? (catName[it.categoryId] ?? 'Uncategorized')
                            : 'Uncategorized';
                        grouped.putIfAbsent(key, () => []).add(it);
                      }
                      final sortedKeys = grouped.keys.toList()..sort();

                      // Use FutureBuilder to fetch stock for the selected date
                      // Re-fetches when date or _stockRefreshKey changes
                      return FutureBuilder<Map<String, double?>>(
                        key: ValueKey('stock_${_selectedDate.year}_${_selectedDate.month}_${_selectedDate.day}_$_stockRefreshKey'),
                        future: stockRepo.getClosingStockMapForDate(_selectedDate),
                        builder: (context, stockSnap) {
                          final stockMap = stockSnap.data ?? <String, double?>{};

                          return CustomScrollView(
                            controller: _scrollController,
                            slivers: [
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 16, 16, 0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                                      fontWeight:
                                                          FontWeight.w800),
                                            ),
                                          ),
                                          // Apply Default Stock button
                                          _applyingDefaultStock
                                              ? Container(
                                                  width: 40,
                                                  height: 40,
                                                  alignment: Alignment.center,
                                                  child: const SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  ),
                                                )
                                              : IconButton.filled(
                                                  tooltip: 'Apply Default Stock',
                                                  icon: const Icon(Icons.inventory_2_outlined),
                                                  onPressed: _showApplyDefaultStockDialog,
                                                  style: IconButton.styleFrom(
                                                    backgroundColor: Colors.green.shade700,
                                                  ),
                                                ),
                                          IconButton.filled(
                                            tooltip: 'Add product',
                                            icon: const Icon(Icons.add),
                                            onPressed: () =>
                                                _openDialog(context),
                                          ),
                                          IconButton(
                                            tooltip: 'Show deleted items',
                                            icon: const Icon(
                                                Icons.visibility_off),
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
                                      const SizedBox(height: 12),
                                      _DatePickerRow(
                                        selectedDate: _selectedDate,
                                        isToday: _isToday,
                                        onSelectDate: _selectDate,
                                      ),
                                      const SizedBox(height: 16),
                                      _SearchBar(
                                        controller: _searchController,
                                        onChanged: (v) =>
                                            setState(() => _query = v),
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
                                    context, cat, grouped[cat]!, catName, stockMap),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                            ],
                          );
                        },
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
    Map<String, double?> stockMap,
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
                final cols = w >= 1200 ? 5 : w >= 900 ? 4 : w >= 620 ? 3 : 2;
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
                      // For today, fall back to live item.quantity if no stock
                      // record exists. For other dates, show 0 (no record = no stock).
                      final stock = stockMap[item.id] ?? (_isToday ? item.quantity : 0.0);
                      return _ProductCard(
                        key: ValueKey('${item.id}_${_selectedDate.toIso8601String()}_$_stockRefreshKey'),
                        item: item,
                        categoryName: catName[item.categoryId],
                        displayStock: stock,
                        selectedDate: _selectedDate,
                        isToday: _isToday,
                        onEdit: () => _openDialog(context, item: item),
                        onStockChanged: () {
                          if (mounted) {
                            setState(() => _stockRefreshKey++);
                          }
                        },
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
      builder: (_) => _ProductDialog(
        item: item,
        selectedDate: _selectedDate,
        isToday: _isToday,
        onStockChanged: () {
          if (mounted) {
            setState(() => _stockRefreshKey++);
          }
        },
      ),
    );
  }

  void _openCategoryManager(BuildContext context) {
    showDialog<void>(context: context, builder: (_) => const _CategoryManagerDialog());
  }
}

class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({
    required this.selectedDate,
    required this.isToday,
    required this.onSelectDate,
  });

  final DateTime selectedDate;
  final bool isToday;
  final VoidCallback onSelectDate;

  @override
  Widget build(BuildContext context) {
    final dateStr = isToday ? 'Today' : _formatDate(selectedDate);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: InkWell(
        onTap: onSelectDate,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 20, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(dateStr,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700)),
              ),
              Icon(Icons.arrow_drop_down, color: Colors.green.shade700),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: const InputDecoration(
        hintText: 'Search products',
        prefixIcon: Icon(Icons.search),
      ),
    );
  }
}

class _ProductCard extends ConsumerStatefulWidget {
  const _ProductCard({
    super.key,
    required this.item,
    required this.categoryName,
    required this.displayStock,
    required this.selectedDate,
    required this.isToday,
    required this.onEdit,
    this.onStockChanged,
  });

  final InventoryItem item;
  final String? categoryName;
  final double displayStock;
  final DateTime selectedDate;
  final bool isToday;
  final VoidCallback? onEdit;
  final VoidCallback? onStockChanged;

  @override
  ConsumerState<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<_ProductCard> {
  late TextEditingController _qtyController;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: _formatQty(widget.displayStock));
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _ProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.displayStock != widget.displayStock && !_focusNode.hasFocus) {
      _qtyController.text = _formatQty(widget.displayStock);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  String _formatQty(double qty) => qty % 1 == 0 ? qty.toInt().toString() : qty.toString();

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _submitQuantity();
    }
  }

  Future<void> _submitQuantity() async {
    final text = _qtyController.text.trim();
    final newQty = double.tryParse(text);
    if (newQty == null || newQty < 0) {
      _qtyController.text = _formatQty(widget.displayStock);
      return;
    }
    if (newQty == widget.displayStock) return;

    try {
      final stockRepo = ref.read(inventoryStockRepositoryProvider);
      // setClosingStock handles both inventory_stock AND inventory_items.quantity for today
      await stockRepo.setClosingStock(widget.item.id, widget.selectedDate, newQty);
      
      unawaited(ref.read(syncServiceProvider).autoPush());
      
      // Notify parent to refresh stock data
      widget.onStockChanged?.call();
    } catch (e) {
      if (mounted) {
        _qtyController.text = _formatQty(widget.displayStock);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '').replaceFirst('StateError: ', '')),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _adjust(double delta, String type) async {
    final currentQty = widget.displayStock;
    final newQty = currentQty + delta;
    if (newQty < 0) return;

    try {
      final stockRepo = ref.read(inventoryStockRepositoryProvider);
      // setClosingStock handles both inventory_stock AND inventory_items.quantity for today
      await stockRepo.setClosingStock(widget.item.id, widget.selectedDate, newQty);
      
      unawaited(ref.read(syncServiceProvider).autoPush());
      
      // Notify parent to refresh stock data
      widget.onStockChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '').replaceFirst('StateError: ', '')),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove "${widget.item.name}" from inventory?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(inventoryRepositoryProvider).deleteItem(widget.item.id);
    unawaited(ref.read(syncServiceProvider).autoPush());
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final categoryName = widget.categoryName;
    final displayStock = widget.displayStock;
    final onEdit = widget.onEdit;

    final inStock = displayStock > 0;
    final qtyLabel = '${_formatQty(displayStock)} in stock';

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
              // Edit and delete buttons
              Positioned(
                top: 6,
                right: 6,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onEdit != null)
                      InkWell(
                        onTap: onEdit,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4)],
                          ),
                          child: Icon(Icons.edit_outlined, size: 16, color: Colors.green.shade700),
                        ),
                      ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _confirmDelete(context),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4)],
                        ),
                        child: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                      ),
                    ),
                  ],
                ),
              ),
              if (inStock)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: Color(0xFF2E7D32), shape: BoxShape.circle),
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
                  Text(categoryName ?? 'Uncategorized',
                      style: TextStyle(color: Colors.green.shade700, fontSize: 10, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text('\u20b9${item.price?.toStringAsFixed(2) ?? '0.00'}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                      Text(qtyLabel,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: !inStock ? Colors.orange.shade800 : Colors.grey.shade600)),
                    ],
                  ),
                  const Spacer(),
                  // Stock editing controls
                  Row(
                    children: [
                      _miniBtn(icon: Icons.remove, onPressed: displayStock > 0 ? () => _adjust(-1, 'USED') : null),
                      Expanded(
                        child: Center(
                          child: SizedBox(
                            width: 50,
                            height: 30,
                            child: TextField(
                              controller: _qtyController,
                              focusNode: _focusNode,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                isDense: true,
                              ),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                              onSubmitted: (_) => _submitQuantity(),
                            ),
                          ),
                        ),
                      ),
                      _miniBtn(icon: Icons.add, onPressed: () => _adjust(1, 'PURCHASE')),
                    ],
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
          child: Icon(icon, size: 18, color: enabled ? const Color(0xFF123D32) : Colors.grey.shade400),
        ),
      ),
    );
  }
}

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
              IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back to inventory', onPressed: onBack),
              Expanded(
                child: Text('Deleted products',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
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
              if (items.isEmpty) return const Center(child: Text('No deleted products'));
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
                        child: Text(_emojiForItem(item, null), style: const TextStyle(fontSize: 20)),
                      ),
                      title: Text(item.name),
                      subtitle: Text('Deleted ${item.deletedAt?.toLocal().toString().split('.').first ?? ''}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.restore, color: Colors.green),
                            tooltip: 'Restore',
                            onPressed: () async {
                              await repo.restoreItem(item.id);
                              unawaited(ref.read(syncServiceProvider).autoPush());
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_forever, color: Colors.red.shade700),
                            tooltip: 'Delete permanently',
                            onPressed: () => _confirmPurge(context, ref, item),
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

  Future<void> _confirmPurge(BuildContext context, WidgetRef ref, InventoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text('Permanently remove "${item.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
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
  const _ProductDialog({
    this.item,
    required this.selectedDate,
    required this.isToday,
    this.onStockChanged,
  });
  final InventoryItem? item;
  final DateTime selectedDate;
  final bool isToday;
  final VoidCallback? onStockChanged;

  @override
  ConsumerState<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends ConsumerState<_ProductDialog> {
  late final TextEditingController _name;
  late final TextEditingController _purchasePrice;
  late final TextEditingController _price;
  late final TextEditingController _quantity;
  late final TextEditingController _minimum;
  late final TextEditingController _defaultQuantity;
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
        text: it?.purchasePrice != null ? it!.purchasePrice!.toStringAsFixed(2) : '');
    _price = TextEditingController(text: it?.price != null ? it!.price!.toStringAsFixed(2) : '');
    _quantity = TextEditingController(text: it != null ? it.quantity.toStringAsFixed(0) : '0');
    _minimum = TextEditingController(text: it != null ? it.minimumQuantity.toStringAsFixed(0) : '0');
    _defaultQuantity = TextEditingController(
        text: it?.defaultQuantity != null ? it!.defaultQuantity!.toStringAsFixed(0) : '');
    _unit = it?.unit ?? 'pcs';
    _categoryId = it?.categoryId;
    _available = it?.availableForOrdering ?? true;
    _iconName = it?.iconName;
    
    // If editing, fetch the stock for the selected date
    if (_isEdit) {
      _loadStockForSelectedDate();
    }
  }

  Future<void> _loadStockForSelectedDate() async {
    final stockRepo = ref.read(inventoryStockRepositoryProvider);
    final stockMap = await stockRepo.getClosingStockMapForDate(widget.selectedDate);
    final stock = stockMap[widget.item!.id];
    if (stock != null && mounted) {
      setState(() {
        _quantity.text = stock % 1 == 0 ? stock.toInt().toString() : stock.toString();
      });
    } else if (widget.isToday && mounted) {
      // For today with no stock record, show live quantity
      setState(() {
        _quantity.text = widget.item!.quantity % 1 == 0 
            ? widget.item!.quantity.toInt().toString() 
            : widget.item!.quantity.toString();
      });
    } else if (mounted) {
      // No stock record for non-today date, default to 0
      setState(() {
        _quantity.text = '0';
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _purchasePrice.dispose();
    _price.dispose();
    _quantity.dispose();
    _minimum.dispose();
    _defaultQuantity.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final result = await showProductIconPicker(context, selected: _iconName);
    if (result == null) return;
    setState(() => _iconName = result.isEmpty ? null : result);
  }

  Future<void> _save(List<Category> categories) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final repo = ref.read(inventoryRepositoryProvider);
    final stockRepo = ref.read(inventoryStockRepositoryProvider);
    final purchasePrice = double.tryParse(_purchasePrice.text.trim());
    final price = double.tryParse(_price.text.trim());
    final minimum = double.tryParse(_minimum.text.trim()) ?? 0;
    final defaultQty = double.tryParse(_defaultQuantity.text.trim());

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
          defaultQuantity: defaultQty,
        );
        final target = double.tryParse(_quantity.text.trim());
        if (target != null) {
          // setClosingStock handles both inventory_stock AND inventory_items.quantity for today
          await stockRepo.setClosingStock(widget.item!.id, widget.selectedDate, target);
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
          defaultQuantity: defaultQty,
        );
      }
      final syncError = await ref.read(syncServiceProvider).autoPush();
      
      // Notify parent to refresh stock data
      widget.onStockChanged?.call();
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(syncError ?? (_isEdit ? 'Product updated.' : 'Product added.')),
            backgroundColor: syncError != null ? Colors.red.shade700 : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
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
      final category = await ref.read(inventoryRepositoryProvider).addCategory(name);
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
    // Show date context in the stock quantity label when not today
    final stockLabel = widget.isToday
        ? 'Stock quantity'
        : 'Stock quantity (${_formatDate(widget.selectedDate)})';

    return StreamBuilder<List<Category>>(
      stream: ref.watch(inventoryRepositoryProvider).watchCategories(),
      builder: (context, snap) {
        final categories = snap.data ?? const [];
        final validIds = categories.map((c) => c.id).toSet();
        final selected = (_categoryId != null && validIds.contains(_categoryId)) ? _categoryId : null;

        return AlertDialog(
          title: Text(_isEdit ? 'Edit product' : 'Add a product'),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                              : ProductIcons.autoEmojiFor(_name.text, null),
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickIcon,
                          icon: const Icon(Icons.emoji_symbols_outlined),
                          label: Text(_iconName == null ? 'Choose an icon' : 'Change icon'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Product name'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _purchasePrice,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Purchase price (\u20b9)'),
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
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Sell price (\u20b9)'),
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
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: stockLabel),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (s.isEmpty) return null;
                            final value = double.tryParse(s);
                            if (value == null || value < 0) return 'Enter a valid quantity';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _unit,
                          decoration: const InputDecoration(labelText: 'Unit'),
                          items: const ['pcs', 'kg', 'g', 'litre', 'ml', 'pack', 'box', 'bottle']
                              .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                              .toList(),
                          onChanged: (v) => setState(() => _unit = v ?? 'pcs'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _defaultQuantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Default stock quantity',
                      helperText: 'Used when applying default stock for a date',
                    ),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return null;
                      final value = double.tryParse(s);
                      if (value == null || value < 0) return 'Invalid';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: selected,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Category'),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('Uncategorized')),
                            ...categories.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name))),
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
            TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: _saving ? null : () => _save(categories),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save product'),
            ),
          ],
        );
      },
    );
  }
}

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
                          child: Text('ACTIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      ...cats.map((c) => ListTile(
                            dense: true,
                            title: Text(c.name),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                              tooltip: 'Delete category',
                              onPressed: () => _confirmDelete(context, ref, c),
                            ),
                          )),
                    ],
                    if (deleted.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('DELETED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      ...deleted.map((c) => ListTile(
                            dense: true,
                            title: Text(c.name,
                                style: TextStyle(color: Colors.grey.shade500, decoration: TextDecoration.lineThrough)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.restore, color: Colors.green),
                                  tooltip: 'Restore',
                                  onPressed: () async {
                                    await repo.restoreCategory(c.id);
                                    unawaited(ref.read(syncServiceProvider).autoPush());
                                  },
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_forever, color: Colors.red.shade700),
                                  tooltip: 'Delete permanently',
                                  onPressed: () => _confirmPurge(context, ref, c),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Category c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('Remove "${c.name}" from categories?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
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

  Future<void> _confirmPurge(BuildContext context, WidgetRef ref, Category c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text('Permanently remove "${c.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
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
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
          onFieldSubmitted: (_) {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _controller.text.trim());
            }
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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

/// Dialog to select a date before applying default stock.
class _ApplyDefaultStockDialog extends StatefulWidget {
  const _ApplyDefaultStockDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_ApplyDefaultStockDialog> createState() => _ApplyDefaultStockDialogState();
}

class _ApplyDefaultStockDialogState extends State<_ApplyDefaultStockDialog> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _isToday ? 'Today' : _formatDate(_selectedDate);

    return AlertDialog(
      title: const Text('Apply Default Stock'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This will set the opening stock for all products that have a default quantity configured.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
          ),
          const SizedBox(height: 20),
          const Text(
            'Select date:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 20, color: Colors.green.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: Colors.green.shade700),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _selectedDate),
          icon: const Icon(Icons.inventory_2_outlined, size: 18),
          label: const Text('Apply'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade700,
          ),
        ),
      ],
    );
  }
}