import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../database/repositories.dart';
import '../../providers.dart';

/// The grouping used by the Overview order report.
enum ReportGrouping { all, society, customer }

/// The time period used to filter the Overview order report.
enum ReportPeriod { all, monthly, daily }

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

String _monthLabel(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _dayLabel(DateTime d) =>
    '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

/// Aggregates line items by "name (unit)" summing quantity and total.
List<OrderReportItem> _aggregateItems(List<OrderReportRow> orders) {
  final map = <String, OrderReportItem>{};
  for (final o in orders) {
    for (final it in o.items) {
      final key = '${it.itemName}__${it.unit}';
      final existing = map[key];
      if (existing == null) {
        map[key] = it;
      } else {
        map[key] = OrderReportItem(
          itemName: it.itemName,
          unit: it.unit,
          quantity: existing.quantity + it.quantity,
          total: existing.total + it.total,
        );
      }
    }
  }
  final list = map.values.toList()
    ..sort((a, b) => a.itemName.compareTo(b.itemName));
  return list;
}

String _fmtQty(double q) =>
    q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString();

class _DashboardPageState extends ConsumerState<DashboardPage> {
  ReportGrouping _grouping = ReportGrouping.all;
  ReportPeriod _period = ReportPeriod.all;
  String? _periodKey; // selected 'yyyy-MM' (monthly) or 'yyyy-MM-dd' (daily)

  @override
  Widget build(BuildContext context) {
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
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () => context.go('/settings'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Your inventory and order activity at a glance.'),
            const SizedBox(height: 28),

            // Inventory stat cards.
            StreamBuilder(
              stream: ref.watch(inventoryRepositoryProvider).watchItems(),
              builder: (context, snapshot) {
                final items = snapshot.data ?? const [];
                final low =
                    items.where((i) => i.quantity <= i.minimumQuantity).length;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 560;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _Stat(
                          title: 'Inventory Items',
                          value: '${items.length}',
                          icon: Icons.inventory_2_outlined,
                          width: isNarrow ? constraints.maxWidth : 260,
                        ),
                        _Stat(
                          title: 'Low Stock',
                          value: '$low',
                          icon: Icons.warning_amber_outlined,
                          width: isNarrow ? constraints.maxWidth : 260,
                        ),
                      ],
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 32),

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
            const SizedBox(height: 12),

            StreamBuilder<List<OrderReportRow>>(
              stream: ref.watch(ordersRepositoryProvider).watchOrderReport(),
              builder: (context, snapshot) {
                final all = snapshot.data ?? const <OrderReportRow>[];

                // Build the available month and day options (desc).
                final monthKeys = <String, DateTime>{};
                final dayKeys = <String, DateTime>{};
                for (final o in all) {
                  monthKeys[_monthKey(o.orderDate)] =
                      DateTime(o.orderDate.year, o.orderDate.month);
                  dayKeys[_dayKey(o.orderDate)] = DateTime(
                    o.orderDate.year,
                    o.orderDate.month,
                    o.orderDate.day,
                  );
                }
                final sortedMonths = monthKeys.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                final sortedDays = dayKeys.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

                // Apply period filter.
                List<OrderReportRow> orders;
                if (_period == ReportPeriod.monthly && _periodKey != null) {
                  orders = all
                      .where((o) => _monthKey(o.orderDate) == _periodKey)
                      .toList();
                } else if (_period == ReportPeriod.daily &&
                    _periodKey != null) {
                  orders = all
                      .where((o) => _dayKey(o.orderDate) == _periodKey)
                      .toList();
                } else {
                  orders = all;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Grouping selector.
                    SegmentedButton<ReportGrouping>(
                      segments: const [
                        ButtonSegment(
                          value: ReportGrouping.all,
                          label: Text('All'),
                          icon: Icon(Icons.summarize_outlined),
                        ),
                        ButtonSegment(
                          value: ReportGrouping.society,
                          label: Text('By society'),
                          icon: Icon(Icons.location_city_outlined),
                        ),
                        ButtonSegment(
                          value: ReportGrouping.customer,
                          label: Text('By customer'),
                          icon: Icon(Icons.person_outline),
                        ),
                      ],
                      selected: {_grouping},
                      onSelectionChanged: (s) =>
                          setState(() => _grouping = s.first),
                    ),
                    const SizedBox(height: 12),

                    // Period selector (All time / Monthly / Daily).
                    SegmentedButton<ReportPeriod>(
                      segments: const [
                        ButtonSegment(
                          value: ReportPeriod.all,
                          label: Text('All time'),
                        ),
                        ButtonSegment(
                          value: ReportPeriod.monthly,
                          label: Text('Monthly'),
                        ),
                        ButtonSegment(
                          value: ReportPeriod.daily,
                          label: Text('Daily'),
                        ),
                      ],
                      selected: {_period},
                      onSelectionChanged: (s) => setState(() {
                        _period = s.first;
                        // Default to the most recent period when switching.
                        if (_period == ReportPeriod.monthly) {
                          _periodKey = sortedMonths.isNotEmpty
                              ? sortedMonths.first.key
                              : null;
                        } else if (_period == ReportPeriod.daily) {
                          _periodKey = sortedDays.isNotEmpty
                              ? sortedDays.first.key
                              : null;
                        } else {
                          _periodKey = null;
                        }
                      }),
                    ),
                    const SizedBox(height: 12),

                    // Month/Day picker (only when a period is selected).
                    if (_period == ReportPeriod.monthly)
                      Row(
                        children: [
                          const Icon(Icons.calendar_month_outlined, size: 18),
                          const SizedBox(width: 8),
                          const Text('Month:'),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue: _periodKey,
                              isExpanded: true,
                              decoration:
                                  const InputDecoration(isDense: true),
                              items: sortedMonths
                                  .map(
                                    (e) => DropdownMenuItem<String?>(
                                      value: e.key,
                                      child: Text(_monthLabel(e.value)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _periodKey = v),
                            ),
                          ),
                        ],
                      ),
                    if (_period == ReportPeriod.daily)
                      Row(
                        children: [
                          const Icon(Icons.today_outlined, size: 18),
                          const SizedBox(width: 8),
                          const Text('Day:'),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue: _periodKey,
                              isExpanded: true,
                              decoration:
                                  const InputDecoration(isDense: true),
                              items: sortedDays
                                  .map(
                                    (e) => DropdownMenuItem<String?>(
                                      value: e.key,
                                      child: Text(_dayLabel(e.value)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _periodKey = v),
                            ),
                          ),
                        ],
                      ),
                    if (_period != ReportPeriod.all)
                      const SizedBox(height: 16)
                    else
                      const SizedBox(height: 4),

                    if (orders.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No orders for this selection.'),
                        ),
                      )
                    else
                      _buildReport(context, orders),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReport(BuildContext context, List<OrderReportRow> orders) {
    final grandTotal = orders.fold<double>(0, (s, o) => s + o.total);

    switch (_grouping) {
      case ReportGrouping.all:
        return _groupExpansion(
          context,
          icon: Icons.summarize_outlined,
          title: 'All societies',
          subtitle: '${orders.length} order(s)',
          amount: grandTotal,
          items: _aggregateItems(orders),
          initiallyExpanded: true,
          highlight: true,
        );

      case ReportGrouping.society:
        final groups = <String, List<OrderReportRow>>{};
        for (final o in orders) {
          groups.putIfAbsent(o.society, () => []).add(o);
        }
        final keys = groups.keys.toList()..sort();
        return Column(
          children: [
            _summaryCard(
              context,
              title: 'All societies',
              subtitle: '${orders.length} order(s)',
              amount: grandTotal,
            ),
            const SizedBox(height: 8),
            ...keys.map((society) {
              final rows = groups[society]!;
              final total = rows.fold<double>(0, (s, o) => s + o.total);
              return _groupExpansion(
                context,
                icon: Icons.location_city_outlined,
                title: society,
                subtitle: '${rows.length} order(s)',
                amount: total,
                items: _aggregateItems(rows),
              );
            }),
          ],
        );

      case ReportGrouping.customer:
        final groups = <String, List<OrderReportRow>>{};
        for (final o in orders) {
          final key = '${o.customerName}__${o.society}';
          groups.putIfAbsent(key, () => []).add(o);
        }
        final keys = groups.keys.toList()..sort();
        return Column(
          children: [
            _summaryCard(
              context,
              title: 'All customers',
              subtitle: '${orders.length} order(s)',
              amount: grandTotal,
            ),
            const SizedBox(height: 8),
            ...keys.map((key) {
              final rows = groups[key]!;
              final total = rows.fold<double>(0, (s, o) => s + o.total);
              final parts = key.split('__');
              return _groupExpansion(
                context,
                icon: Icons.person_outline,
                title: parts.first,
                subtitle:
                    '${parts.length > 1 ? parts[1] : ''} · ${rows.length} order(s)',
                amount: total,
                items: _aggregateItems(rows),
              );
            }),
          ],
        );
    }
  }

  /// A group header with an item-level breakdown shown when expanded.
  Widget _groupExpansion(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required double amount,
    required List<OrderReportItem> items,
    bool initiallyExpanded = false,
    bool highlight = false,
  }) {
    return Card(
      color: highlight ? const Color(0xFF123D32) : null,
      child: Theme(
        // Remove default dividers on the expansion tile.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          iconColor: highlight ? Colors.white : null,
          collapsedIconColor: highlight ? Colors.white70 : null,
          leading: CircleAvatar(
            backgroundColor: highlight ? Colors.white24 : null,
            child: Icon(icon, color: highlight ? Colors.white : null),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: highlight ? Colors.white : null,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: highlight ? Colors.white70 : Colors.grey.shade600,
            ),
          ),
          trailing: Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: highlight ? Colors.white : null,
            ),
          ),
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: items.isEmpty
              ? [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No items.',
                      style: TextStyle(
                        color: highlight
                            ? Colors.white70
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ]
              : items.map((it) {
                  final line =
                      '${it.itemName} - ${_fmtQty(it.quantity)}${it.unit} - '
                      '₹${it.total.toStringAsFixed(2)}';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 6,
                          color: highlight
                              ? Colors.white70
                              : Colors.grey.shade500,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            line,
                            style: TextStyle(
                              color: highlight ? Colors.white : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
        ),
      ),
    );
  }

  Widget _summaryCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required double amount,
  }) {
    return Card(
      color: const Color(0xFF123D32),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Text(
              '₹${amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.title,
    required this.value,
    required this.icon,
    required this.width,
  });

  final String title;
  final String value;
  final IconData icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 120,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
