import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';
import '../auth/user_profile.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _syncing = false;
  String? _lastSyncMessage;

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _lastSyncMessage = null;
    });
    try {
      final result = await ref.read(syncServiceProvider).syncAll();
      if (mounted) {
        setState(() => _lastSyncMessage = result.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.toString())),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        setState(() => _lastSyncMessage = 'Sync failed: $msg');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $msg')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authRepositoryProvider);
    final user = auth.currentUser;
    final profile = ref.watch(currentUserProfileProvider).value;
    final isAdmin = profile?.role == AppRole.admin;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.person_outline),
              ),
              title: Text(user?.email ?? 'Not signed in'),
              subtitle: Text(
                user != null
                    ? 'Signed in · Role: ${profile?.role.label ?? '—'}'
                    : 'No active session',
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (isAdmin)
            Card(
              child: ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('User Management'),
                subtitle: const Text(
                  'Add users and assign roles (admin only).',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/users'),
              ),
            ),
          if (isAdmin) const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: _syncing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_sync_outlined),
              title: const Text('Cloud Sync'),
              subtitle: Text(
                _lastSyncMessage ??
                    'Push local data to Supabase and pull remote changes.',
              ),
              trailing: FilledButton(
                onPressed: (user == null || _syncing) ? null : _syncNow,
                child: const Text('Sync now'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Sign out',
                style: TextStyle(color: Colors.red),
              ),
              onTap: user == null
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Sign out'),
                          content: const Text(
                            'Are you sure you want to sign out?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('Sign out'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        await auth.signOut();
                        // Router's auth listener redirects to /login.
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }
}