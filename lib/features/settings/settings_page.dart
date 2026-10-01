import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Card(
          child: ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('Cloud Sync'),
            subtitle: Text('Supabase sync will be connected here.'),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(Icons.security_outlined),
            title: Text('Account'),
            subtitle: Text('Authentication will be added here.'),
          ),
        ),
      ],
    ),
  );
}
