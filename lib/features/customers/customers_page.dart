import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../providers.dart';

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  String? _societyFilter; // null = All societies
  bool _showInactive = false; // hide inactive customers by default

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(customersRepositoryProvider);
    final societiesRepo = ref.watch(societiesRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            tooltip: _showInactive ? 'Hide inactive' : 'Show inactive',
            icon: Icon(
              _showInactive ? Icons.visibility : Icons.visibility_off,
            ),
            onPressed: () =>
                setState(() => _showInactive = !_showInactive),
          ),
        ],
      ),
      body: Column(
        children: [
          // Society filter chips (driven by the societies table).
          StreamBuilder<List<Society>>(
            stream: societiesRepo.watchSocieties(),
            builder: (context, snapshot) {
              final societies = snapshot.data ?? const <Society>[];
              return SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _chip('All societies', null),
                    ...societies.map((s) => _chip(s.name, s.name)),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<List<Customer>>(
              stream: repo.watchCustomers(),
              builder: (context, snapshot) {
                var customers = snapshot.data ?? const [];
                if (_societyFilter != null) {
                  customers = customers
                      .where((c) => c.society == _societyFilter)
                      .toList();
                }
                if (!_showInactive) {
                  customers =
                      customers.where((c) => c.active).toList();
                }
                if (customers.isEmpty) {
                  return const Center(child: Text('No customers yet'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: customers.length,
                  itemBuilder: (_, i) {
                    final customer = customers[i];
                    return Opacity(
                      opacity: customer.active ? 1 : 0.5,
                      child: Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: customer.active
                              ? null
                              : Colors.grey.shade300,
                          child: const Icon(Icons.person_outline),
                        ),
                        title: Row(
                          children: [
                            Flexible(child: Text(customer.name)),
                            if (!customer.active) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Inactive',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          [
                            if ((customer.phone ?? '').isNotEmpty)
                              customer.phone!,
                            if ((customer.address ?? '').isNotEmpty)
                              customer.address!,
                          ].join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((customer.society ?? '').isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.location_on_outlined,
                                      size: 14,
                                      color: Colors.green.shade800,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      customer.society!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            IconButton(
                              icon: Icon(
                                customer.active
                                    ? Icons.toggle_on
                                    : Icons.toggle_off,
                                color: customer.active
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              tooltip: customer.active
                                  ? 'Mark inactive'
                                  : 'Mark active',
                              onPressed: () async {
                                await ref
                                    .read(customersRepositoryProvider)
                                    .setActive(
                                      customer.id,
                                      !customer.active,
                                    );
                                unawaited(
                                  ref
                                      .read(syncServiceProvider)
                                      .autoPush(),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit customer',
                              onPressed: () => _openDialog(customer: customer),
                            ),
                          ],
                        ),
                        onTap: () => _openDialog(customer: customer),
                      ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add customer'),
      ),
    );
  }

  Widget _chip(String label, String? value) {
    final selected = _societyFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _societyFilter = value),
      ),
    );
  }

  void _openDialog({Customer? customer}) {
    showDialog<void>(
      context: context,
      builder: (_) => _CustomerDialog(customer: customer),
    );
  }
}

class _CustomerDialog extends ConsumerStatefulWidget {
  const _CustomerDialog({this.customer});

  final Customer? customer;

  @override
  ConsumerState<_CustomerDialog> createState() => _CustomerDialogState();
}

// Sentinel value used by the society dropdown to represent the
// "Add new society…" action.
const String _kAddNewSociety = '__add_new_society__';

class _CustomerDialogState extends ConsumerState<_CustomerDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  final _formKey = GlobalKey<FormState>();
  String? _society;
  bool _active = true;
  bool _saving = false;

  bool get _isEdit => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _name = TextEditingController(text: c?.name ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _address = TextEditingController(text: c?.address ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
    _society = c?.society;
    _active = c?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Field decoration. Alignment/border/padding come from the global
  /// [InputDecorationTheme] so every form in the app stays consistent.
  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
    );
  }

  Future<void> _promptAddSociety() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add society'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Society name',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (name == null || name.isEmpty) return;

    final society =
        await ref.read(societiesRepositoryProvider).addSociety(name);
    unawaited(ref.read(syncServiceProvider).autoPush());
    if (mounted) {
      setState(() => _society = society.name);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      await ref.read(customersRepositoryProvider).save(
            id: widget.customer?.id,
            name: _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            address:
                _address.text.trim().isEmpty ? null : _address.text.trim(),
            society: _society,
            active: _active,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          );
      final syncError = await ref.read(syncServiceProvider).autoPush();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              syncError ??
                  (_isEdit ? 'Customer updated.' : 'Customer added.'),
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

  @override
  Widget build(BuildContext context) {
    final societiesRepo = ref.watch(societiesRepositoryProvider);

    return AlertDialog(
      title: Text(_isEdit ? 'Edit customer' : 'Add a customer'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: _decoration('Full name'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: _decoration('Phone number'),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return null;
                        if (!RegExp(r'^[+]?[\d\s-]{7,15}$').hasMatch(value)) {
                          return 'Invalid phone';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _address,
                      decoration: _decoration('Block Number'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: _decoration('Email'),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return null;
                  if (!RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(value)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              // Society dropdown driven by the societies table, with an
              // inline "Add new society…" action.
              StreamBuilder<List<Society>>(
                stream: societiesRepo.watchSocieties(),
                builder: (context, snapshot) {
                  final societies = snapshot.data ?? const <Society>[];
                  final names = societies.map((s) => s.name).toList();

                  // If the current value is not in the list (e.g. a society
                  // that was removed), keep it visible by appending it.
                  final currentValue = _society;
                  if (currentValue != null && !names.contains(currentValue)) {
                    names.add(currentValue);
                  }

                  return DropdownButtonFormField<String?>(
                    initialValue: _society,
                    isExpanded: true,
                    decoration: _decoration('Society'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None'),
                      ),
                      ...names.map(
                        (s) => DropdownMenuItem<String?>(
                          value: s,
                          child: Text(s),
                        ),
                      ),
                      const DropdownMenuItem<String?>(
                        value: _kAddNewSociety,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, size: 18),
                            SizedBox(width: 8),
                            Text('Add new society…'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == _kAddNewSociety) {
                        _promptAddSociety();
                      } else {
                        setState(() => _society = v);
                      }
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: _decoration('Notes'),
                maxLines: 2,
                minLines: 1,
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active customer'),
                subtitle: Text(
                  _active
                      ? 'Customer is active and available for orders.'
                      : 'Customer is inactive and hidden by default.',
                ),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
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
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save customer'),
        ),
      ],
    );
  }
}
