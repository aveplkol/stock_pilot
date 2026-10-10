import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/app_database.dart';
import '../../database/repositories.dart';
import '../../providers.dart';

/// Manages the master list of societies: add, soft-delete (deactivate),
/// restore, and permanently delete. A visibility toggle in the header shows
/// inactive (soft-deleted) societies, mirroring the Customers page UX.
class SocietiesPage extends ConsumerStatefulWidget {
  const SocietiesPage({super.key});

  @override
  ConsumerState<SocietiesPage> createState() => _SocietiesPageState();
}

class _SocietiesPageState extends ConsumerState<SocietiesPage> {
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(societiesRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Societies'),
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
      body: _showInactive
          ? _InactiveSocietiesList(repo: repo)
          : _ActiveSocietiesList(repo: repo),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _promptAdd,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Add society'),
      ),
    );
  }

  Future<void> _promptAdd() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _AddSocietyDialog(),
    );
    if (name == null || name.isEmpty) return;
    try {
      await ref.read(societiesRepositoryProvider).addSociety(name);
      unawaited(ref.read(syncServiceProvider).autoPush());
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
}

class _ActiveSocietiesList extends ConsumerWidget {
  const _ActiveSocietiesList({required this.repo});

  final SocietiesRepository repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<Society>>(
      stream: repo.watchSocieties(),
      builder: (context, snapshot) {
        final societies = snapshot.data ?? const <Society>[];
        if (societies.isEmpty) {
          return const Center(child: Text('No societies yet'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: societies.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final s = societies[i];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.location_city_outlined),
                ),
                title: Text(s.name),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                  tooltip: 'Deactivate society',
                  onPressed: () => _confirmDelete(context, ref, s),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Society s,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete society?'),
        content: Text('Mark "${s.name}" as inactive?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(societiesRepositoryProvider).deleteSociety(s.id);
    unawaited(ref.read(syncServiceProvider).autoPush());
  }
}

class _InactiveSocietiesList extends ConsumerWidget {
  const _InactiveSocietiesList({required this.repo});

  final SocietiesRepository repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<Society>>(
      stream: repo.watchDeletedSocieties(),
      builder: (context, snapshot) {
        final societies = snapshot.data ?? const <Society>[];
        if (societies.isEmpty) {
          return const Center(child: Text('No inactive societies'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: societies.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final s = societies[i];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey.shade300,
                  child: const Icon(Icons.location_city_outlined),
                ),
                title: Text(
                  s.name,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                subtitle: Text(
                  'Inactive since '
                  '${s.deletedAt?.toLocal().toString().split('.').first ?? ''}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.restore, color: Colors.green),
                      tooltip: 'Restore',
                      onPressed: () async {
                        await repo.restoreSociety(s.id);
                        unawaited(ref.read(syncServiceProvider).autoPush());
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_forever,
                          color: Colors.red.shade700),
                      tooltip: 'Delete permanently',
                      onPressed: () => _confirmPurge(context, ref, s),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmPurge(
    BuildContext context,
    WidgetRef ref,
    Society s,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text(
          'Permanently remove "${s.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(societiesRepositoryProvider).purgeSociety(s.id);
    unawaited(ref.read(syncServiceProvider).autoPush());
  }
}

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