import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers.dart';

class CustomersPage extends ConsumerWidget {
  const CustomersPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(customersRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      body: StreamBuilder(
        stream: repo.watchCustomers(),
        builder: (context, snapshot) {
          final customers = snapshot.data ?? const [];
          if (customers.isEmpty) return const Center(child: Text('No customers yet'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: customers.length,
            itemBuilder: (_, i) => Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(customers[i].name),
              subtitle: Text(customers[i].phone ?? customers[i].email ?? ''),
            )),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Customer'),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final key = GlobalKey<FormState>();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Customer'),
        content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: 12),
          TextFormField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            if (!key.currentState!.validate()) return;
            await ref.read(customersRepositoryProvider).save(
              name: name.text.trim(), phone: phone.text.trim(), email: email.text.trim());
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          }, child: const Text('Save')),
        ],
      ),
    );
    name.dispose(); phone.dispose(); email.dispose();
  }
}
