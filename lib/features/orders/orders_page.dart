import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/repositories.dart';
import '../../providers.dart';
import '../customers/customers_page.dart' show customerLabel;

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  late DateTime _orderDate;
  String? _society;
  String? _block;
  String? _customerId;
  final Map<String, int> _qty = {}; // inventoryItemId -> quantity
  final Set<String> _collapsed = {}; // collapsed category keys
  bool _initializedCollapse = false; // collapse all categories on first load
  String? _editingOrderId; // non-null when updating an existing order
  bool _saving = false;
  bool _loadingExisting = false;

  // Available (closing) stock per item for the selected order date.
  // Falls back to item.quantity when no record exists (handled at read time).
  Map<String, double?> _stockMap = const {};
  bool _loadingStock = false;

  // When editing, stores the original quantities from the existing order.
  // This allows us to calculate the true available stock = closing_stock + original_order_qty
  Map<String, double> _originalOrderQty = const {};

  @override
  void initState() {
    super.initState();
    _orderDate = _dateOnly(DateTime.now().add(const Duration(days: 1)));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStockForDate());
  }

  bool get _isOrderDateToday {
    final now = DateTime.now();
    return _orderDate.year == now.year &&
        _orderDate.month == now.month &&
        _orderDate.day == now.day;
  }

  /// Loads the closing (available) stock map for the selected order date.
  Future<void> _loadStockForDate() async {
    setState(() => _loadingStock = true);
    try {
      final stockRepo = ref.read(inventoryStockRepositoryProvider);
      final map = await stockRepo.getClosingStockMapForDate(_orderDate);
      if (!mounted) return;
      setState(() {
        _stockMap = map;
        _loadingStock = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingStock = false);
    }
  }

  /// Resolves the available stock for an item on the selected order date.
  /// When editing an existing order, adds back the original order quantity
  /// so the customer can increase their order.
  /// For today with no record, falls back to the live item.quantity.
  /// For other dates with no record, availability is 0.
  double _availableFor(InventoryItem item) {
    final closingStock = _stockMap[item.id];
    double baseAvailable;
    if (closingStock != null) {
      baseAvailable = closingStock;
    } else {
      baseAvailable = _isOrderDateToday ? item.quantity : 0.0;
    }
    
    // When editing, add back the original order quantity to show true available
    final originalQty = _originalOrderQty[item.id] ?? 0.0;
    return baseAvailable + originalQty;
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _orderDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _orderDate = _dateOnly(picked));
      await _loadStockForDate();
      if (_customerId != null) {
        await _loadExistingOrder();
      }
    }
  }

  Future<void> _loadExistingOrder() async {
    final customerId = _customerId;
    if (customerId == null) {
      setState(() {
        _qty.clear();
        _editingOrderId = null;
        _originalOrderQty = const {};
      });
      return;
    }
    setState(() => _loadingExisting = true);
    final existing = await ref
        .read(ordersRepositoryProvider)
        .findOrderForCustomerOnDate(customerId, _orderDate);
    if (!mounted) return;
    setState(() {
      _qty.clear();
      _originalOrderQty = {};
      if (existing != null) {
        _editingOrderId = existing.order.id;
        existing.quantities.forEach((itemId, q) {
          _qty[itemId] = q.round();
          _originalOrderQty[itemId] = q;  // Store original quantities
        });
      } else {
        _editingOrderId = null;
      }
      _loadingExisting = false;
    });
  }

  /// Copies the quantities from the customer's most recent prior order into
  /// the current form. Quantities are clamped to available stock, and items
  /// no longer orderable/in stock are skipped.
  Future<void> _copyPreviousDayOrder() async {
    final customerId = _customerId;
    if (customerId == null) return;

    final existing = await ref
        .read(ordersRepositoryProvider)
        .findMostRecentOrderBefore(customerId, _orderDate);
    if (!mounted) return;

    if (existing == null || existing.quantities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous order found to copy.')),
      );
      return;
    }

    // Load current inventory to clamp quantities to available stock and
    // skip items that are no longer orderable.
    final items = await ref.read(inventoryRepositoryProvider).watchItems().first;
    if (!mounted) return;
    final byId = {for (final i in items) i.id: i};

    var copied = 0;
    var adjusted = 0;
    var skipped = 0;
    final next = <String, int>{};
    existing.quantities.forEach((itemId, qty) {
      final item = byId[itemId];
      if (item == null || !item.availableForOrdering) {
        skipped++;
        return;
      }
      final want = qty.round();
      final maxQty = _availableFor(item).floor();
      final take = want > maxQty ? maxQty : want;
      if (take <= 0) {
        skipped++;
        return;
      }
      if (take < want) adjusted++;
      next[itemId] = take;
      copied++;
    });

    setState(() {
      _qty
        ..clear()
        ..addAll(next);
    });

    final parts = <String>['Copied $copied item(s)'];
    if (adjusted > 0) parts.add('$adjusted adjusted to stock');
    if (skipped > 0) parts.add('$skipped unavailable');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(parts.join(' · '))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventoryRepo = ref.watch(inventoryRepositoryProvider);
    final customersRepo = ref.watch(customersRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            tooltip: 'Auto Generate Orders',
            onPressed: _showAutoGenerateDialog,
          ),
        ],
      ),
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
            'Shop for a customer',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),

          // 1) Order date (defaults to tomorrow).
          const Text('Order date'),
          const SizedBox(height: 4),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.event_outlined),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmtDate(_orderDate)),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2) Society selection.
          const Text('Select a society'),
          const SizedBox(height: 4),
          StreamBuilder<List<Society>>(
            stream: ref.watch(societiesRepositoryProvider).watchSocieties(),
            builder: (context, snap) {
              final societies = snap.data ?? const <Society>[];
              final ids = societies.map((s) => s.id).toSet();
              final current =
                  (_society != null && ids.contains(_society))
                      ? _society
                      : null;
              return DropdownButtonFormField<String?>(
                initialValue: current,
                isExpanded: true,
                decoration:
                    const InputDecoration(hintText: 'Choose society'),
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
                    _editingOrderId = null;
                    _originalOrderQty = {};
                  });
                },
              );
            },
          ),
          const SizedBox(height: 16),

          // 3) Block selection (distinct blocks within the society).
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
                  if ((c.block ?? '').trim().isNotEmpty)
                    c.block!.trim(),
              }.toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
              final current = _block;
              if (current != null && !blocks.contains(current)) {
                blocks.add(current);
              }
              return DropdownButtonFormField<String?>(
                initialValue: _block,
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
                    (s) =>
                        DropdownMenuItem<String?>(value: s, child: Text(s)),
                  ),
                ],
                onChanged: _society == null
                    ? null
                    : (v) {
                        setState(() {
                          _block = v;
                          _customerId = null;
                          _qty.clear();
                          _editingOrderId = null;
                          _originalOrderQty = {};
                        });
                      },
              );
            },
          ),
          const SizedBox(height: 16),

          // 4) Customer selection (filtered by society + block).
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
                initialValue: selected,
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
                  await _loadExistingOrder();
                },
              );
            },
          ),

          if (_editingOrderId != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.edit_calendar_outlined,
                        color: Colors.amber.shade800, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Existing order found for ${_fmtDate(_orderDate)}. '
                        'Changes will update it.',
                        style: TextStyle(color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_customerId != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _copyPreviousDayOrder,
                icon: const Icon(Icons.content_copy_outlined, size: 18),
                label: const Text("Copy previous day's order"),
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Text(
            'Add products',
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
    final available = _availableFor(item);  // Now includes original order qty when editing
    final maxQty = available.floor();
    final outOfStock = available <= 0;
    
    // Show what's truly available (closing stock, not including this order's allocation)
    final closingStock = _stockMap[item.id];
    final displayAvailable = closingStock ?? (_isOrderDateToday ? item.quantity : 0.0);
    final originalQty = _originalOrderQty[item.id] ?? 0.0;
    
    // Build the availability text
    String availabilityText;
    if (_editingOrderId != null && originalQty > 0) {
      // When editing and this item was in the original order, show both values
      availabilityText = '${displayAvailable.toStringAsFixed(0)} available · ${originalQty.toStringAsFixed(0)} ordered';
    } else {
      availabilityText = '${displayAvailable.toStringAsFixed(0)} available';
    }
    
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
                  '\u20b9${item.price?.toStringAsFixed(2) ?? '0.00'} \u00b7 $availabilityText',
                  style: TextStyle(
                    fontSize: 12,
                    color: outOfStock ? Colors.orange.shade800 : Colors.grey.shade600,
                    fontWeight: outOfStock ? FontWeight.w600 : FontWeight.normal,
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
            onPressed: qty < maxQty
                ? () => setState(() => _qty[item.id] = qty + 1)
                : null,
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

            final isEditing = _editingOrderId != null;
            
            // Determine if we can save:
            // - For new orders: need at least one item with qty > 0
            // - For editing: can save even with 0 items (clears the order)
            final canSave = customer != null && (isEditing || lines.isNotEmpty);

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
                    isEditing ? 'UPDATE ORDER' : 'ORDER SUMMARY',
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
                    'For ${_fmtDate(_orderDate)}',
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (customer == null)
                    const Text(
                      'Choose a customer to start the order.',
                      style: TextStyle(color: Colors.white70),
                    )
                  else if (lines.isEmpty && !isEditing)
                    const Text(
                      'Add products to see the total.',
                      style: TextStyle(color: Colors.white70),
                    )
                  else if (lines.isEmpty && isEditing)
                    Text(
                      'All items removed. Save to clear the order.',
                      style: TextStyle(color: Colors.orange.shade200),
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
                                style:
                                    const TextStyle(color: Colors.white70),
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
                          'Total',
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
                  ],
                  if (canSave) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF123D32),
                        ),
                        onPressed:
                            _saving ? null : () => _placeOrder(lines, byId),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isEditing 
                                    ? (lines.isEmpty ? 'Clear order' : 'Update order')
                                    : 'Place order'),
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

  /// Shows a confirmation dialog before auto-generating orders from templates.
  Future<void> _showAutoGenerateDialog() async {
    var selectedDate = _orderDate;
    var stockConfirmed = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Auto Generate Orders'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will create orders for all customers with templates '
                'who don\'t have an order on the selected date.',
              ),
              const SizedBox(height: 20),
              const Text(
                'Order Date',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = _dateOnly(picked));
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmtDate(selectedDate)),
                      const Icon(Icons.calendar_today, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              CheckboxListTile(
                value: stockConfirmed,
                onChanged: (v) => setDialogState(() => stockConfirmed = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Default stock has been added for today',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: stockConfirmed
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Generate Orders'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      await _generateFromTemplates(selectedDate);
    }
  }

  /// Generates orders from replenishment templates for the given date.
  Future<void> _generateFromTemplates(DateTime orderDate) async {
    final templatesRepo = ref.read(replenishmentTemplatesRepositoryProvider);
    final ordersRepo = ref.read(ordersRepositoryProvider);
    final inventoryRepo = ref.read(inventoryRepositoryProvider);
    final customersRepo = ref.read(customersRepositoryProvider);

    // Get all active customers
    final customers = await customersRepo.watchCustomers().first;
    final activeCustomers = customers.where((c) => c.active).toList();

    // Get customers who already have orders
    final existingOrderCustomers =
        await ordersRepo.getCustomersWithOrdersOnDate(orderDate);

    // Get all templates and parse their items
    final allTemplates = await templatesRepo.getAll();
    final templateItemsByCustomer = <String, List<TemplateItem>>{};
    for (final template in allTemplates) {
      final items = templatesRepo.parseItems(template);
      if (items.isNotEmpty) {
        templateItemsByCustomer[template.customerId] = items;
      }
    }

    // Get inventory
    final items = await inventoryRepo.watchItems().first;
    final itemsById = {for (final i in items) i.id: i};

    // Resolve available (closing) stock for the target date so template
    // generation respects the date's inventory, not today's live quantity.
    final stockRepo = ref.read(inventoryStockRepositoryProvider);
    final stockMap = await stockRepo.getClosingStockMapForDate(orderDate);
    final isTargetToday = () {
      final now = DateTime.now();
      return orderDate.year == now.year &&
          orderDate.month == now.month &&
          orderDate.day == now.day;
    }();
    double availableFor(InventoryItem item) {
      final v = stockMap[item.id];
      if (v != null) return v;
      return isTargetToday ? item.quantity : 0.0;
    }

    var created = 0;
    var errors = 0;

    for (final customer in activeCustomers) {
      // Skip if already has order
      if (existingOrderCustomers.contains(customer.id)) continue;

      // Skip if no templates
      final templateItems = templateItemsByCustomer[customer.id];
      if (templateItems == null || templateItems.isEmpty) continue;

      // Build order lines
      final lines = <NewOrderLine>[];
      for (final templateItem in templateItems) {
        final item = itemsById[templateItem.inventoryItemId];
        if (item != null && availableFor(item) >= templateItem.quantity) {
          lines.add(NewOrderLine(
            inventoryItemId: templateItem.inventoryItemId,
            quantity: templateItem.quantity,
            unit: item.unit,
            unitPrice: item.price ?? 0,
          ));
        }
      }

      if (lines.isEmpty) continue;

      try {
        await ordersRepo.createOrder(
          customerId: customer.id,
          lines: lines,
          status: 'COMPLETED',
          orderDate: orderDate,
        );
        created++;
      } catch (e) {
        errors++;
      }
    }

    unawaited(ref.read(syncServiceProvider).autoPush());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created $created orders${errors > 0 ? ' ($errors errors)' : ''}',
          ),
        ),
      );
    }
  }

  Future<void> _placeOrder(
    List<MapEntry<String, int>> lines,
    Map<String, InventoryItem> byId,
  ) async {
    setState(() => _saving = true);
    try {
      final isEditing = _editingOrderId != null;
      
      if (isEditing && lines.isEmpty) {
        // User cleared all items - we need to restore stock and effectively "delete" the order
        // For now, update with minimal quantity (this should ideally be a delete operation)
        // TODO: Implement proper order deletion
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot clear all items. Please keep at least one item or delete the order.'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _saving = false);
        return;
      }
      
      final orderLines = lines.map((e) {
        final it = byId[e.key]!;
        return NewOrderLine(
          inventoryItemId: it.id,
          quantity: e.value.toDouble(),
          unit: it.unit,
          unitPrice: it.price ?? 0,
        );
      }).toList();

      if (isEditing) {
        await ref.read(ordersRepositoryProvider).updateOrder(
              orderId: _editingOrderId!,
              lines: orderLines,
            );
      } else {
        await ref.read(ordersRepositoryProvider).createOrder(
              customerId: _customerId,
              lines: orderLines,
              status: 'COMPLETED',
              orderDate: _orderDate,
            );
      }
      final syncError = await ref.read(syncServiceProvider).autoPush();
      
      // Reload stock after order change
      await _loadStockForDate();
      
      if (mounted) {
        setState(() {
          _qty.clear();
          _customerId = null;
          _editingOrderId = null;
          _originalOrderQty = {};
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              syncError ?? (isEditing ? 'Order updated.' : 'Order placed.'),
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
            content: Text(e.toString().replaceFirst('Exception: ', '').replaceFirst('StateError: ', '')),
          ),
        );
      }
    }
  }
}

/// A collapsible category block for the order builder.
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