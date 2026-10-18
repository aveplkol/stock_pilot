import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/repositories.dart';
import '../../providers.dart';

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) =>
    '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

/// Page showing today's pending orders, grouped by customer.
/// Allows quick fulfillment and navigation to order details.
class TodaysOrdersPage extends ConsumerStatefulWidget {
  const TodaysOrdersPage({super.key});

  @override
  ConsumerState<TodaysOrdersPage> createState() => _TodaysOrdersPageState();
}

class _TodaysOrdersPageState extends ConsumerState<TodaysOrdersPage> {
  late DateTime _orderDate;

  @override
  void initState() {
    super.initState();
    _orderDate = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final ordersRepo = ref.watch(ordersRepositoryProvider);
    final customersRepo = ref.watch(customersRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Orders"),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _pickDate,
            tooltip: 'Select date',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _formatDate(_orderDate),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Customer>>(
        stream: customersRepo.watchCustomers(),
        builder: (context, customersSnapshot) {
          final allCustomers = customersSnapshot.data ?? [];
          final activeCustomers =
              allCustomers.where((c) => c.active).toList();

          if (activeCustomers.isEmpty) {
            return const Center(
              child: Text('No active customers'),
            );
          }

          return FutureBuilder<Set<String>>(
            future: ordersRepo.getCustomersWithOrdersOnDate(_orderDate),
            builder: (context, ordersSnapshot) {
              final customersWithOrders = ordersSnapshot.data ?? {};

              // Separate customers with and without orders
              final withOrders = activeCustomers
                  .where((c) => customersWithOrders.contains(c.id))
                  .toList();
              final withoutOrders = activeCustomers
                  .where((c) => !customersWithOrders.contains(c.id))
                  .toList();

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Summary card
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _SummaryItem(
                            label: 'Total Customers',
                            value: activeCustomers.length.toString(),
                            icon: Icons.people_outline,
                          ),
                          _SummaryItem(
                            label: 'With Orders',
                            value: withOrders.length.toString(),
                            icon: Icons.check_circle_outline,
                            color: Colors.green,
                          ),
                          _SummaryItem(
                            label: 'Pending',
                            value: withoutOrders.length.toString(),
                            icon: Icons.pending_outlined,
                            color: Colors.orange,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Customers without orders (need attention)
                  if (withoutOrders.isNotEmpty) ...[
                    Text(
                      'Pending Orders',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...withoutOrders.map((customer) => _CustomerOrderCard(
                          customer: customer,
                          hasOrder: false,
                          orderDate: _orderDate,
                          onCreateOrder: () => _createOrderForCustomer(customer),
                        )),
                    const SizedBox(height: 16),
                  ],

                  // Customers with orders
                  if (withOrders.isNotEmpty) ...[
                    Text(
                      'Completed Orders',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ...withOrders.map((customer) => _CustomerOrderCard(
                          customer: customer,
                          hasOrder: true,
                          orderDate: _orderDate,
                          onViewOrder: () => _viewOrderForCustomer(customer),
                        )),
                  ],
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generateFromTemplates,
        icon: const Icon(Icons.auto_fix_high),
        label: const Text('Auto-Generate'),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _orderDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() => _orderDate = picked);
    }
  }

  Future<void> _createOrderForCustomer(Customer customer) async {
    // Get template items for this customer
    final templatesRepo = ref.read(replenishmentTemplatesRepositoryProvider);
    final templateItems = await templatesRepo.getItemsForCustomer(customer.id);

    if (templateItems.isEmpty) {
      // No templates - just navigate to create order manually
      _navigateToCreateOrder(customer);
      return;
    }

    // Get inventory items for the templates
    final items =
        await ref.read(inventoryRepositoryProvider).watchItems().first;
    final itemsById = {for (final i in items) i.id: i};

    // Build order lines from templates
    final lines = <NewOrderLine>[];
    for (final templateItem in templateItems) {
      final item = itemsById[templateItem.inventoryItemId];
      if (item != null && item.quantity >= templateItem.quantity) {
        lines.add(NewOrderLine(
          inventoryItemId: templateItem.inventoryItemId,
          quantity: templateItem.quantity,
          unit: item.unit,
          unitPrice: item.price ?? 0,
        ));
      }
    }

    if (lines.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No items available in templates'),
          ),
        );
      }
      return;
    }

    // Create the order
    try {
      await ref.read(ordersRepositoryProvider).createOrder(
            customerId: customer.id,
            lines: lines,
            status: 'COMPLETED',
            orderDate: _orderDate,
          );

      unawaited(ref.read(syncServiceProvider).autoPush());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order created for ${_formatCustomerName(customer)}'),
          ),
        );
        setState(() {}); // Refresh the list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToCreateOrder(Customer customer) {
    // Navigate to orders page to create order manually
    // This would typically use go_router navigation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Navigate to create order for ${_formatCustomerName(customer)}'),
      ),
    );
  }

  Future<void> _viewOrderForCustomer(Customer customer) async {
    final order = await ref
        .read(ordersRepositoryProvider)
        .findOrderForCustomerOnDate(customer.id, _orderDate);

    if (order != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order ${order.order.orderNumber} - ₹${order.order.total.toStringAsFixed(2)}'),
        ),
      );
    }
  }

  Future<void> _generateFromTemplates() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate Orders'),
        content: const Text(
          'This will create orders for all customers with templates who don\'t have an order today. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final templatesRepo = ref.read(replenishmentTemplatesRepositoryProvider);
    final ordersRepo = ref.read(ordersRepositoryProvider);
    final inventoryRepo = ref.read(inventoryRepositoryProvider);
    final customersRepo = ref.read(customersRepositoryProvider);

    // Get all active customers
    final customers = await customersRepo.watchCustomers().first;
    final activeCustomers = customers.where((c) => c.active).toList();

    // Get customers who already have orders
    final existingOrderCustomers =
        await ordersRepo.getCustomersWithOrdersOnDate(_orderDate);

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
        if (item != null && item.quantity >= templateItem.quantity) {
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
          orderDate: _orderDate,
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
      setState(() {}); // Refresh
    }
  }

  String _formatCustomerName(Customer customer) {
    final parts = <String>[];
    if (customer.flatNumber != null && customer.flatNumber!.isNotEmpty) {
      parts.add(customer.flatNumber!);
    }
    if (customer.name != null && customer.name!.isNotEmpty) {
      parts.add(customer.name!);
    }
    return parts.isEmpty ? 'Customer' : parts.join(' - ');
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _CustomerOrderCard extends StatelessWidget {
  const _CustomerOrderCard({
    required this.customer,
    required this.hasOrder,
    required this.orderDate,
    this.onCreateOrder,
    this.onViewOrder,
  });

  final Customer customer;
  final bool hasOrder;
  final DateTime orderDate;
  final VoidCallback? onCreateOrder;
  final VoidCallback? onViewOrder;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (customer.flatNumber != null && customer.flatNumber!.isNotEmpty) {
      parts.add(customer.flatNumber!);
    }
    if (customer.name != null && customer.name!.isNotEmpty) {
      parts.add(customer.name!);
    }
    final displayName = parts.isEmpty ? 'Customer' : parts.join(' - ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: hasOrder
              ? Colors.green.shade100
              : Colors.orange.shade100,
          child: Icon(
            hasOrder ? Icons.check : Icons.pending,
            color: hasOrder ? Colors.green : Colors.orange,
          ),
        ),
        title: Text(displayName),
        subtitle: Text(customer.society ?? 'No society'),
        trailing: hasOrder
            ? TextButton(
                onPressed: onViewOrder,
                child: const Text('View'),
              )
            : FilledButton(
                onPressed: onCreateOrder,
                child: const Text('Create'),
              ),
      ),
    );
  }
}