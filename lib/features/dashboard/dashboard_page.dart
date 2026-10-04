import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../database/app_database.dart';
import '../../database/repositories.dart';
import '../../providers.dart';
import '../auth/user_profile.dart';
import '../customers/customers_page.dart' show customerLabel;

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dayLabel(DateTime d) =>
    '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

/// Aggregated figures for a single product across many order lines.
class _AggRow {
  _AggRow(this.name, this.unit);
  final String name;
  final String unit;
  double quantity = 0;
  double purchaseTotal = 0; // sum(cost)
  double sellTotal = 0; // sum(revenue)

  double get avgPurchase => quantity == 0 ? 0 : purchaseTotal / quantity;
  double get avgSell => quantity == 0 ? 0 : sellTotal / quantity;
  double get profit => sellTotal - purchaseTotal;
}

/// Aggregates line items by "name (unit)" summing quantity, cost and revenue.
List<_AggRow> _aggregateItems(List<OrderReportRow> orders) {
  final map = <String, _AggRow>{};
  for (final o in orders) {
    for (final it in o.items) {
      final key = '${it.itemName}__${it.unit}';
      final row = map.putIfAbsent(key, () => _AggRow(it.itemName, it.unit));
      row.quantity += it.quantity;
      row.purchaseTotal += it.cost;
      row.sellTotal += it.total;
    }
  }
  final list = map.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  return list;
}

double _sumRevenue(List<OrderReportRow> orders) =>
    orders.fold<double>(0, (s, o) => s + o.total);

double _sumProfit(List<OrderReportRow> orders) {
  var profit = 0.0;
  for (final o in orders) {
    for (final it in o.items) {
      profit += it.profit;
    }
  }
  return profit;
}

String _fmtQty(double q) =>
    q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString();

class _DashboardPageState extends ConsumerState<DashboardPage> {
  // Filters. Dates default to tomorrow (next day's date).
  late DateTime _startDate;
  late DateTime _endDate;
  String? _society; // null => All societies
  String? _block; // null => All blocks
  String? _customerId; // null => All customers

  @override
  void initState() {
    super.initState();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _startDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    _endDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
  }

  bool _sameOrBefore(DateTime a, DateTime b) => !DateTime(a.year, a.month, a.day)
      .isAfter(DateTime(b.year, b.month, b.day));

  bool _inRange(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return _sameOrBefore(_startDate, day) && _sameOrBefore(day, _endDate);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _startDate = DateTime(picked.year, picked.month, picked.day);
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _endDate = DateTime(picked.year, picked.month, picked.day);
        if (_endDate.isBefore(_startDate)) _startDate = _endDate;
      });
    }
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authRepositoryProvider).signOut();
      // Router's auth listener redirects to /login.
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final isAdmin = profile?.role == AppRole.admin;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Overview',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (isAdmin)
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                    onPressed: () => context.go('/settings'),
                  ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Sign out',
                  onPressed: () => _confirmSignOut(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Your order activity at a glance.'),
            const SizedBox(height: 24),

            // Order report section.
            Text(
              'Order report',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text('Totals and item breakdown of orders placed.'),
            const SizedBox(height: 16),

            // Filters + report (both depend on the customers list).
            StreamBuilder<List<Customer>>(
              stream: ref.watch(customersRepositoryProvider).watchCustomers(),
              builder: (context, custSnap) {
                final allCustomers =
                    (custSnap.data ?? const <Customer>[]).toList();
                final matchingIds = _matchingCustomerIds(allCustomers);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFilters(context, allCustomers),
                    const SizedBox(height: 16),
                    StreamBuilder<List<OrderReportRow>>(
                      stream: ref
                          .watch(ordersRepositoryProvider)
                          .watchOrderReport(),
                      builder: (context, snapshot) {
                        final all =
                            snapshot.data ?? const <OrderReportRow>[];
                        final orders = all.where((o) {
                          if (!_inRange(o.orderDate)) return false;
                          if (matchingIds != null) {
                            final id = o.customerId;
                            if (id == null || !matchingIds.contains(id)) {
                              return false;
                            }
                          }
                          return true;
                        }).toList();

                        if (orders.isEmpty) {
                          return const Card(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child:
                                  Text('No orders for this selection.'),
                            ),
                          );
                        }
                        return _buildReport(context, orders);
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Returns the set of customer ids matching the current society/block/
  /// customer selection, or `null` when "All" is selected across the board
  /// (meaning: do not filter by customer).
  Set<String>? _matchingCustomerIds(List<Customer> allCustomers) {
    if (_society == null && _block == null && _customerId == null) {
      return null;
    }
    if (_customerId != null) {
      return {_customerId!};
    }
    var custs = allCustomers;
    if (_society != null) {
      custs = custs.where((c) => c.society == _society).toList();
    }
    if (_block != null) {
      custs = custs.where((c) => (c.address ?? '').trim() == _block).toList();
    }
    return custs.map((c) => c.id).toSet();
  }

  Widget _buildFilters(BuildContext context, List<Customer> allCustomers) {
    // Societies available.
    final societies = {
      for (final c in allCustomers)
        if ((c.society ?? '').trim().isNotEmpty) c.society!.trim()
    }.toList()
      ..sort();

    // Blocks available within the selected society (address = block).
    final inSoc = _society == null
        ? allCustomers
        : allCustomers.where((c) => c.society == _society).toList();
    final blocks = {
      for (final c in inSoc)
        if ((c.address ?? '').trim().isNotEmpty) c.address!.trim()
    }.toList()
      ..sort();

    // Customers available within the selected society + block.
    var custs = inSoc;
    if (_block != null) {
      custs = custs.where((c) => (c.address ?? '').trim() == _block).toList();
    }
    custs = custs.toList()
      ..sort((a, b) {
        final na = int.tryParse((a.flatNumber ?? '').trim());
        final nb = int.tryParse((b.flatNumber ?? '').trim());
        if (na != null && nb != null) return na.compareTo(nb);
        return (a.flatNumber ?? '').compareTo(b.flatNumber ?? '');
      });

    // Keep the selected customer valid for the current society/block.
    final validCustomerIds = custs.map((c) => c.id).toSet();
    final selectedCustomerId =
        (_customerId != null && validCustomerIds.contains(_customerId))
            ? _customerId
            : null;

    InputDecoration dec(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;

        final startField = _DateField(
          label: 'Start date',
          value: _dayLabel(_startDate),
          onTap: _pickStartDate,
        );
        final endField = _DateField(
          label: 'End date',
          value: _dayLabel(_endDate),
          onTap: _pickEndDate,
        );

        final societyField = DropdownButtonFormField<String?>(
          initialValue: _society,
          isExpanded: true,
          decoration: dec('Society'),
          items: [
            const DropdownMenuItem(value: null, child: Text('All societies')),
            ...societies
                .map((s) => DropdownMenuItem(value: s, child: Text(s))),
          ],
          onChanged: (v) => setState(() {
            _society = v;
            _block = null;
            _customerId = null;
          }),
        );

        final blockField = DropdownButtonFormField<String?>(
          initialValue: _block,
          isExpanded: true,
          decoration: dec('Block'),
          items: [
            const DropdownMenuItem(value: null, child: Text('All blocks')),
            ...blocks.map((b) => DropdownMenuItem(value: b, child: Text(b))),
          ],
          onChanged: (v) => setState(() {
            _block = v;
            _customerId = null;
          }),
        );

        final customerField = DropdownButtonFormField<String?>(
          initialValue: selectedCustomerId,
          isExpanded: true,
          decoration: dec('Customer'),
          items: [
            const DropdownMenuItem(value: null, child: Text('All customers')),
            ...custs.map((c) =>
                DropdownMenuItem(value: c.id, child: Text(customerLabel(c)))),
          ],
          onChanged: (v) => setState(() => _customerId = v),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: startField),
                  const SizedBox(width: 12),
                  Expanded(child: endField),
                ],
              ),
              const SizedBox(height: 12),
              societyField,
              const SizedBox(height: 12),
              blockField,
              const SizedBox(height: 12),
              customerField,
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(child: startField),
                const SizedBox(width: 12),
                Expanded(child: endField),
                const SizedBox(width: 12),
                Expanded(child: societyField),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: blockField),
                const SizedBox(width: 12),
                Expanded(child: customerField),
                const SizedBox(width: 12),
                const Spacer(),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildReport(BuildContext context, List<OrderReportRow> orders) {
    final grandTotal = _sumRevenue(orders);
    final grandProfit = _sumProfit(orders);

    // A single consolidated report for the current selection.
    return _groupExpansion(
      context,
      icon: Icons.summarize_outlined,
      title: _selectionTitle(),
      subtitle: '${orders.length} order(s)',
      amount: grandTotal,
      profit: grandProfit,
      items: _aggregateItems(orders),
      initiallyExpanded: true,
      highlight: true,
    );
  }

  String _selectionTitle() {
    final parts = <String>[];
    parts.add(_society ?? 'All societies');
    if (_block != null) parts.add(_block!);
    return parts.join(' · ');
  }

  /// A group header with a tabular item breakdown shown when expanded.
  Widget _groupExpansion(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required double amount,
    required double profit,
    required List<_AggRow> items,
    bool initiallyExpanded = false,
    bool highlight = false,
  }) {
    final fg = highlight ? Colors.white : null;
    final fg70 = highlight ? Colors.white70 : Colors.grey.shade600;

    return Card(
      color: highlight ? const Color(0xFF123D32) : null,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          iconColor: highlight ? Colors.white : null,
          collapsedIconColor: highlight ? Colors.white70 : null,
          leading: CircleAvatar(
            backgroundColor: highlight ? Colors.white24 : null,
            child: Icon(icon, color: fg),
          ),
          title: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, color: fg),
          ),
          subtitle: Text(subtitle, style: TextStyle(color: fg70)),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${amount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: fg,
                ),
              ),
              Text(
                'Profit ₹${profit.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 11,
                  color: highlight
                      ? Colors.greenAccent.shade100
                      : Colors.green.shade700,
                ),
              ),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            if (items.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('No items.', style: TextStyle(color: fg70)),
              )
            else
              _itemsTable(context, items, highlight: highlight),
          ],
        ),
      ),
    );
  }

  /// Renders the per-product table: Product, Qty, Purchase, Sell, Total.
  Widget _itemsTable(
    BuildContext context,
    List<_AggRow> items, {
    required bool highlight,
  }) {
    final fg = highlight ? Colors.white : Colors.black87;
    final fgHead = highlight ? Colors.white70 : Colors.grey.shade700;
    final border = highlight ? Colors.white24 : Colors.grey.shade300;

    Widget cell(
      String text, {
      bool header = false,
      TextAlign align = TextAlign.left,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Text(
          text,
          textAlign: align,
          softWrap: true,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: header ? FontWeight.w700 : FontWeight.w400,
            color: header ? fgHead : fg,
          ),
        ),
      );
    }

    const columnWidths = <int, TableColumnWidth>{
      0: FlexColumnWidth(2.2), // Product
      1: FlexColumnWidth(1.1), // Qty
      2: FlexColumnWidth(1.3), // Purchase
      3: FlexColumnWidth(1.3), // Sell
      4: FlexColumnWidth(1.4), // Total
    };

    return Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(color: border),
        bottom: BorderSide(color: border),
      ),
      children: [
        TableRow(
          children: [
            cell('Product', header: true),
            cell('Qty', header: true, align: TextAlign.right),
            cell('Purchase', header: true, align: TextAlign.right),
            cell('Sell', header: true, align: TextAlign.right),
            cell('Total', header: true, align: TextAlign.right),
          ],
        ),
        ...items.map(
          (r) => TableRow(
            children: [
              cell(r.name),
              cell('${_fmtQty(r.quantity)} ${r.unit}',
                  align: TextAlign.right),
              cell('₹${r.avgPurchase.toStringAsFixed(2)}',
                  align: TextAlign.right),
              cell('₹${r.avgSell.toStringAsFixed(2)}',
                  align: TextAlign.right),
              cell('₹${r.sellTotal.toStringAsFixed(2)}',
                  align: TextAlign.right),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(value),
      ),
    );
  }
}
