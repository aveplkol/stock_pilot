import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/inventory/inventory_page.dart';
import '../features/customers/customers_page.dart';
import '../features/orders/orders_page.dart';
import '../features/settings/settings_page.dart';

final stockPilotRouter = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    ShellRoute(
      builder: (context, state, child) => StockPilotShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardPage(),
        ),
        GoRoute(
          path: '/inventory',
          builder: (context, state) => const InventoryPage(),
        ),
        GoRoute(
          path: '/customers',
          builder: (context, state) => const CustomersPage(),
        ),
        GoRoute(
          path: '/orders',
          builder: (context, state) => const OrdersPage(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),
  ],
);

class StockPilotShell extends StatelessWidget {
  const StockPilotShell({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Scaffold(body: Row(children: [
          const DesktopNavigation(),
          Expanded(child: child),
        ]));
      }
      return Scaffold(body: child, bottomNavigationBar: const MobileNavigation());
    },
  );
}

class DesktopNavigation extends StatelessWidget {
  const DesktopNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    return Container(
      width: 250,
      color: const Color(0xFF123D32),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Text('Stock Pilot', style: TextStyle(
              color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
          ),
          const _Label('WORKSPACE'),
          _item(context, path, '/dashboard', Icons.dashboard_outlined, 'Overview'),
          _item(context, path, '/inventory', Icons.inventory_2_outlined, 'Inventory'),
          _item(context, path, '/customers', Icons.people_outline, 'Customers'),
          _item(context, path, '/orders', Icons.shopping_bag_outlined, 'Orders'),
          const Spacer(),
          const _Label('SETTINGS'),
          _item(context, path, '/settings', Icons.settings_outlined, 'Settings'),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _item(BuildContext context, String current, String path, IconData icon, String label) {
    final selected = current == path;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: Icon(icon, color: selected ? Colors.white : Colors.white70),
        title: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white70)),
        selected: selected,
        selectedTileColor: Colors.white.withValues(alpha: .12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onTap: () => context.go(path),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
    child: Text(text, style: const TextStyle(
      color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

class MobileNavigation extends StatelessWidget {
  const MobileNavigation({super.key});
  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final selected = switch (path) {
      '/inventory' => 1,
      '/customers' => 2,
      '/orders' => 3,
      _ => 0,
    };
    return NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: (i) =>
          context.go(['/dashboard','/inventory','/customers','/orders'][i]),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Overview'),
        NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Inventory'),
        NavigationDestination(icon: Icon(Icons.people_outline), label: 'Customers'),
        NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), label: 'Orders'),
      ],
    );
  }
}
