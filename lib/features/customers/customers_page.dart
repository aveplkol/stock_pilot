import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../providers.dart';

/// Display label for a customer: "Flat - Name" (either part optional).
String customerLabel(Customer c) {
  final flat = (c.flatNumber ?? '').trim();
  final name = (c.name ?? '').trim();
  if (flat.isNotEmpty && name.isNotEmpty) return '$flat - $name';
  if (flat.isNotEmpty) return flat;
  if (name.isNotEmpty) return name;
  return 'Unnamed customer';
}

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  String? _societyFilter; // null = All societies (holds a society ID)
  bool _showInactive = false;
  final Set<String> _collapsedBlocks = {}; // collapsed block keys
  bool _initializedCollapse = false; // collapse all blocks on first load

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(customersRepositoryProvider);
    final societiesRepo = ref.watch(societiesRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<List<Customer>>(
          stream: repo.watchCustomers(),
          builder: (context, snapshot) {
            final customers = snapshot.data ?? const [];
            final activeCount = customers.where((c) => c.active).length;
            final totalCount = customers.length;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Customers'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _showInactive ? '$totalCount' : '$activeCount',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            tooltip: _showInactive ? 'Hide inactive' : 'Show inactive',
            icon: Icon(
              _showInactive ? Icons.visibility : Icons.visibility_off,
            ),
            onPressed: () => setState(() => _showInactive = !_showInactive),
          ),
        ],
      ),
      body: StreamBuilder<List<Society>>(
        stream: societiesRepo.watchSocieties(),
        builder: (context, societiesSnap) {
          final societies = societiesSnap.data ?? const <Society>[];
          return Column(
            children: [
              // Society filter chips (value = society id).
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _chip('All societies', null),
                    ...societies.map((s) => _chip(s.name, s.id)),
                  ],
                ),
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
                      customers = customers.where((c) => c.active).toList();
                    }
                    if (customers.isEmpty) {
                      return const Center(child: Text('No customers yet'));
                    }

                    // Group by Block, sort blocks alphabetically and
                    // customers within each block by flat number
                    // (alphabetically, case-insensitive).
                    final groups = <String, List<Customer>>{};
                    for (final c in customers) {
                      final block = (c.block ?? '').trim();
                      groups
                          .putIfAbsent(
                              block.isEmpty ? 'No block' : block, () => [])
                          .add(c);
                    }
                    final blockKeys = groups.keys.toList()
                      ..sort((a, b) =>
                          a.toLowerCase().compareTo(b.toLowerCase()));
                    // Collapse all blocks by default on the first data load.
                    if (!_initializedCollapse && blockKeys.isNotEmpty) {
                      _initializedCollapse = true;
                      _collapsedBlocks.addAll(blockKeys);
                    }
                    for (final k in blockKeys) {
                      groups[k]!.sort((a, b) => _compareFlat(
                            a.flatNumber ?? '',
                            b.flatNumber ?? '',
                          ));
                    }

                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final block in blockKeys)
                          _buildCollapsibleBlock(
                            block,
                            groups[block]!,
                            societies,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
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

  /// Compares two flat numbers alphabetically (case-insensitive).
  int _compareFlat(String a, String b) =>
      a.trim().toLowerCase().compareTo(b.trim().toLowerCase());

  /// Maps a society ID to its display name.
  String _societyName(String? societyId, List<Society> societies) {
    if (societyId == null || societyId.isEmpty) return '';
    for (final s in societies) {
      if (s.id == societyId) return s.name;
    }
    return societyId; // Fallback to the raw value if unresolved.
  }

  /// Builds a collapsible block section (tappable header toggles children).
  Widget _buildCollapsibleBlock(
    String block,
    List<Customer> customers,
    List<Society> societies,
  ) {
    final isCollapsed = _collapsedBlocks.contains(block);
    final displayBlock = block == 'No block' ? 'No block' : 'Block $block';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (isCollapsed) {
              _collapsedBlocks.remove(block);
            } else {
              _collapsedBlocks.add(block);
            }
          }),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
            child: Row(
              children: [
                Icon(
                  isCollapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 18,
                  color: Colors.grey.shade700,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.apartment_outlined,
                  size: 18,
                  color: Colors.grey.shade700,
                ),
                const SizedBox(width: 6),
                Text(
                  displayBlock,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade800,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${customers.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!isCollapsed)
          ...customers.map((c) => _customerTile(c, societies)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _customerTile(Customer customer, List<Society> societies) {
    final flat = (customer.flatNumber ?? '').trim();
    final name = (customer.name ?? '').trim();
    final phone = (customer.phone ?? '').trim();

    final details = <String>[
      if (flat.isNotEmpty) 'Flat $flat',
      if (phone.isNotEmpty) phone,
    ].join('  ·  ');

    final title = name.isNotEmpty
        ? name
        : (flat.isNotEmpty ? 'Flat $flat' : 'Unnamed');

    final societyName = _societyName(customer.society, societies);

    return Opacity(
      opacity: customer.active ? 1 : 0.5,
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: customer.active ? null : Colors.grey.shade300,
            child: const Icon(Icons.person_outline),
          ),
          title: Row(
            children: [
              Flexible(child: Text(title)),
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
          subtitle: details.isEmpty ? null : Text(details),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (societyName.isNotEmpty)
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
                        Icons.location_city_outlined,
                        size: 14,
                        color: Colors.green.shade800,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        societyName,
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
                  customer.active ? Icons.toggle_on : Icons.toggle_off,
                  color: customer.active ? Colors.green : Colors.grey,
                ),
                tooltip:
                    customer.active ? 'Mark inactive' : 'Mark active',
                onPressed: () async {
                  await ref
                      .read(customersRepositoryProvider)
                      .setActive(customer.id, !customer.active);
                  unawaited(ref.read(syncServiceProvider).autoPush());
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

class _CustomerDialogState extends ConsumerState<_CustomerDialog> {
  late final TextEditingController _block;
  late final TextEditingController _flatNumber;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  final _formKey = GlobalKey<FormState>();
  String? _society; // holds a society ID
  bool _active = true;
  bool _saving = false;

  bool get _isEdit => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _society = c?.society;
    _block = TextEditingController(text: c?.block ?? '');
    _flatNumber = TextEditingController(text: c?.flatNumber ?? '');
    _name = TextEditingController(text: c?.name ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _active = c?.active ?? true;
  }

  @override
  void dispose() {
    _block.dispose();
    _flatNumber.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(labelText: label, hintText: hint);
  }

  Future<void> _promptAddSociety() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _AddSocietyDialog(),
    );
    if (name == null || name.isEmpty) return;
    try {
      final society =
          await ref.read(societiesRepositoryProvider).addSociety(name);
      unawaited(ref.read(syncServiceProvider).autoPush());
      // Store the new society's ID (not name).
      if (mounted) setState(() => _society = society.id);
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_society == null || _society!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Society is required.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(customersRepositoryProvider).save(
            id: widget.customer?.id,
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            society: _society,
            block: _block.text.trim().isEmpty ? null : _block.text.trim(),
            flatNumber: _flatNumber.text.trim(),
            active: _active,
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
              // Society (mandatory) — dropdown with add-new. Value = id.
              StreamBuilder<List<Society>>(
                stream: societiesRepo.watchSocieties(),
                builder: (context, snapshot) {
                  final societies = snapshot.data ?? const <Society>[];
                  final ids = societies.map((s) => s.id).toSet();
                  // If the current value is not among the known ids, reset.
                  final current =
                      (_society != null && ids.contains(_society))
                          ? _society
                          : null;
                  return Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: current,
                          isExpanded: true,
                          decoration: _decoration('Society *'),
                          items: [
                            ...societies.map(
                              (s) => DropdownMenuItem<String?>(
                                value: s.id,
                                child: Text(s.name),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _society = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Add new society',
                        icon: const Icon(Icons.add),
                        onPressed: _promptAddSociety,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              // Block (mandatory).
              TextFormField(
                controller: _block,
                decoration: _decoration('Block *'),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              // Flat Number (mandatory).
              TextFormField(
                controller: _flatNumber,
                decoration: _decoration('Flat number *'),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              // Customer name (optional).
              TextFormField(
                controller: _name,
                decoration: _decoration('Customer name (optional)'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextFormField(
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

/// Small dialog that collects a new society name. Owns and disposes its own
/// [TextEditingController] safely (after the dialog's exit animation),
/// avoiding "used after being disposed" errors.
class _AddSocietyDialog extends StatefulWidget {
  const _AddSocietyDialog();

  @override
  State<_AddSocietyDialog> createState() => _AddSocietyDialogState();
}

class _AddSocietyDialogState extends State<_AddSocietyDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add society'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Society name'),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Required' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
