import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers.dart';

class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(ordersRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: StreamBuilder(
        stream: repo.watchOrders(),
        builder: (context, snapshot) {
          final orders = snapshot.data ?? const [];
          if (orders.isEmpty) return const Center(child: Text('No orders yet'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (_, i) => Card(child: ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(orders[i].orderNumber),
              subtitle: Text(orders[i].status),
              trailing: Text(orders[i].total.toStringAsFixed(2)),
            )),
          );
        },
      ),
      floatingActionButton: const FloatingActionButton.extended(
        onPressed: null, icon: Icon(Icons.add), label: Text('New Order')),
    );
  }
}
