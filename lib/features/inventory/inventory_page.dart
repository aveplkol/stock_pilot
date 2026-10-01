import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});
  @override ConsumerState<InventoryPage> createState() => _InventoryPageState();
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
      body: StreamBuilder(
        stream: repo.watchItems(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('No inventory items yet'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final item = items[i];
              final low = item.quantity <= item.minimumQuantity;
              return Card(child: ListTile(
                leading: Icon(low ? Icons.warning_amber : Icons.inventory_2_outlined),
                title: Text(item.name),
                subtitle: Text('${item.quantity} ${item.unit}${low ? ' • Low stock' : ''}'),
                trailing: Wrap(children: [
                  IconButton(
                    tooltip: 'Use 1',
                    onPressed: item.quantity > 0
                        ? () => repo.addTransaction(item.id, -1, 'USED', unit: item.unit)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    tooltip: 'Purchase 1',
                    onPressed: () => repo.addTransaction(item.id, 1, 'PURCHASE', unit: item.unit),
                    icon: const Icon(Icons.add),
                  ),
                ]),
              ));
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addItem(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
    );
  }

  Future<void> _addItem(BuildContext context) async {
    final name = TextEditingController();
    final quantity = TextEditingController(text: '0');
    final minimum = TextEditingController(text: '0');
    var unit = 'pcs';
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Add Item'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Item name'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: unit,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: const ['pcs','kg','g','litre','ml','pack','box','bottle']
                    .map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                onChanged: (v) => setState(() => unit = v ?? 'pcs'),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: quantity, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Current quantity')),
              const SizedBox(height: 12),
              TextFormField(controller: minimum, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minimum stock')),
            ])),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await ref.read(inventoryRepositoryProvider).createItem(
                name: name.text.trim(), unit: unit,
                quantity: double.tryParse(quantity.text) ?? 0,
                minimumQuantity: double.tryParse(minimum.text) ?? 0,
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
    name.dispose(); quantity.dispose(); minimum.dispose();
  }
}
