import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../auth/user_profile.dart';

const _kBrandGreen = Color(0xFF123D32);

/// Admin-only page to list users, change their roles, and create new users.
class UserManagementPage extends ConsumerStatefulWidget {
  const UserManagementPage({super.key});

  @override
  ConsumerState<UserManagementPage> createState() =>
      _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> {
  bool _loading = true;
  String? _error;
  List<UserProfile> _users = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users =
          await ref.read(authRepositoryProvider).listUserProfiles();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _changeRole(UserProfile user) async {
    final selected = await showDialog<AppRole>(
      context: context,
      builder: (ctx) {
        AppRole temp = user.role;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text('Change role — ${user.email}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: AppRole.values
                  .map((r) => RadioListTile<AppRole>(
                        value: r,
                        groupValue: temp,
                        title: Text(r.label),
                        onChanged: (v) => setLocal(() => temp = v!),
                      ))
                  .toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, temp),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null || selected == user.role) return;
    try {
      await ref
          .read(authRepositoryProvider)
          .updateUserRole(user.id, selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${user.email} is now ${selected.label}. '
              'They must re-login for it to take effect.'),
          backgroundColor: _kBrandGreen,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $msg')));
    }
  }

  Future<void> _createUser() async {
    // Default the new user's company code to the signed-in admin's company.
    final adminProfile =
        await ref.read(currentUserProfileProvider.future);
    final adminCompanyCode = adminProfile?.companyCode;

    if (!mounted) return;
    final result = await showDialog<_NewUser>(
      context: context,
      builder: (ctx) =>
          _CreateUserDialog(companyCode: adminCompanyCode),
    );
    if (result == null) return;

    final auth = ref.read(authRepositoryProvider);
    // Capture the admin's session so we can restore it after sign-up
    // (the public sign-up flow signs the new user in).
    final adminSession = auth.currentSession;
    try {
      await auth.createUser(
        email: result.email,
        password: result.password,
        role: result.role,
        name: result.name,
        companyCode: result.companyCode,
      );
      // Restore the admin session.
      if (adminSession != null) {
        await auth.restoreSession(adminSession);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'User ${result.email} created as ${result.role.label}.'),
          backgroundColor: _kBrandGreen,
        ),
      );
      await _load();
    } catch (e) {
      // Best-effort restore even on failure.
      if (adminSession != null) {
        try {
          await auth.restoreSession(adminSession);
        } catch (_) {}
      }
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create user: $msg')),
      );
    }
  }

  Color _roleColor(AppRole role) => switch (role) {
        AppRole.admin => Colors.red.shade700,
        AppRole.manager => Colors.blue.shade700,
        AppRole.staff => Colors.grey.shade700,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: _kBrandGreen,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _kBrandGreen,
        foregroundColor: Colors.white,
        onPressed: _createUser,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add User'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(
                          'Unable to load users.\n$_error',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final u = _users[i];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _roleColor(u.role),
                            child: Text(
                              (u.name?.isNotEmpty == true
                                      ? u.name!
                                      : u.email)
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(u.name?.isNotEmpty == true
                              ? u.name!
                              : u.email),
                          subtitle: Text(u.email),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(
                                label: Text(
                                  u.role.label,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12),
                                ),
                                backgroundColor: _roleColor(u.role),
                                visualDensity: VisualDensity.compact,
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Change role',
                                onPressed: () => _changeRole(u),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _NewUser {
  const _NewUser({
    required this.email,
    required this.password,
    required this.role,
    this.name,
    this.companyCode,
  });
  final String email;
  final String password;
  final AppRole role;
  final String? name;
  final String? companyCode;
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog({this.companyCode});

  /// The signed-in admin's company code, used as the default for the new
  /// user so they belong to the same company/tenant.
  final String? companyCode;

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  late final TextEditingController _companyCtrl =
      TextEditingController(text: widget.companyCode ?? '');
  AppRole _role = AppRole.staff;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _companyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add User'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email *',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (!v.contains('@')) return 'Invalid email';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordCtrl,
              decoration: const InputDecoration(
                labelText: 'Temporary password *',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.length < 6) {
                  return 'Min 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AppRole>(
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: 'Role *',
                border: OutlineInputBorder(),
              ),
              items: AppRole.values
                  .map((r) =>
                      DropdownMenuItem(value: r, child: Text(r.label)))
                  .toList(),
              onChanged: (v) => setState(() => _role = v ?? AppRole.staff),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _companyCtrl,
              // Defaults to the admin's company and is read-only so the new
              // user is always created in the same company/tenant.
              readOnly: true,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Company code',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business_outlined),
                helperText: 'Same company as your account',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _NewUser(
                email: _emailCtrl.text.trim(),
                password: _passwordCtrl.text,
                role: _role,
                name: _nameCtrl.text.trim().isEmpty
                    ? null
                    : _nameCtrl.text.trim(),
                companyCode: _companyCtrl.text.trim().isEmpty
                    ? null
                    : _companyCtrl.text.trim(),
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
