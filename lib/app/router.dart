import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers.dart';
import '../features/auth/login_page.dart';
import '../features/auth/reset_password_page.dart';
import '../features/auth/user_profile.dart';
import '../features/admin/user_management_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/inventory/inventory_page.dart';
import '../features/customers/customers_page.dart';
import '../features/orders/orders_page.dart';
import '../features/payments/payment_page.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/societies_page.dart';

class AuthRouterNotifier extends ChangeNotifier {
  AuthRouterNotifier() {
    _subscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      // When the user arrives via the password-reset deep link, Supabase
      // emits a `passwordRecovery` event with a short-lived recovery
      // session. We flag it so the router redirects to the in-app reset
      // screen instead of the dashboard.
      if (data.event == AuthChangeEvent.passwordRecovery) {
        isRecoveringPassword = true;
      }
      // Defer notification to avoid triggering router redirects during an
      // active widget build/dispose phase (which throws the
      // `_dependents.isEmpty` assertion). Scheduling on a microtask lets the
      // current frame settle before navigation occurs.
      scheduleMicrotask(() {
        if (!_disposed) {
          notifyListeners();
        }
      });
    });
  }

  /// True while a password-recovery session is active (set when the reset
  /// deep link opens the app). Cleared once the user finishes resetting.
  bool isRecoveringPassword = false;

  late final StreamSubscription<AuthState> _subscription;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}

/// Reads any auth error (e.g. an expired reset link) that Supabase appended
/// to the launch URL as query parameters, e.g.
/// `.../reset-password?error=access_denied&error_code=otp_expired&...`.
///
/// Returns a human-readable message when an error is present, otherwise null.
String? _authErrorFromLaunchUrl() {
  final params = Uri.base.queryParameters;
  final errorCode = params['error_code'] ?? params['error'];
  if (errorCode == null || errorCode.isEmpty) return null;

  final description = params['error_description'];
  if (description != null && description.isNotEmpty) {
    // Supabase uses '+' for spaces in the description.
    return description.replaceAll('+', ' ');
  }
  switch (errorCode) {
    case 'otp_expired':
      return 'This password reset link is invalid or has expired. '
          'Request a new one below.';
    case 'access_denied':
      return 'Access was denied for this link. Request a new reset link '
          'below.';
    default:
      return 'The link could not be used ($errorCode). Request a new one '
          'below.';
  }
}

GoRouter createStockPilotRouter() {
  final authNotifier = AuthRouterNotifier();

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: authNotifier,

    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;

      final isLoggedIn = session != null;
      final isLoginPage = state.uri.path == '/login';
      final isResetPage = state.uri.path == '/reset-password';

      // If the launch URL carries an auth error (e.g. an expired reset
      // link), surface it on the login screen instead of silently showing a
      // blank sign-in form. This commonly happens when the reset email link
      // has expired or was already used.
      final launchError = _authErrorFromLaunchUrl();
      if (launchError != null && !authNotifier.isRecoveringPassword) {
        if (isLoginPage) return null;
        return Uri(
          path: '/login',
          queryParameters: {'authError': launchError},
        ).toString();
      }

      // While a password-recovery session is active, force the user to the
      // reset screen until they set a new password.
      if (authNotifier.isRecoveringPassword) {
        return isResetPage ? null : '/reset-password';
      }

      if (!isLoggedIn && !isLoginPage) {
        return '/login';
      }

      if (isLoggedIn && isLoginPage) {
        return '/dashboard';
      }

      return null;
    },

    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginPage(
          initialError: state.uri.queryParameters['authError'],
        ),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordPage(),
      ),

      ShellRoute(
        builder: (context, state, child) {
          return StockPilotShell(child: child);
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/inventory',
            builder: (context, state) => const RoleGuard(
              feature: AppFeature.inventory,
              child: InventoryPage(),
            ),
          ),
          GoRoute(
            path: '/customers',
            builder: (context, state) => const RoleGuard(
              feature: AppFeature.customers,
              child: CustomersPage(),
            ),
          ),
          GoRoute(
            path: '/orders',
            builder: (context, state) => const OrdersPage(),
          ),
          GoRoute(
            path: '/payments',
            builder: (context, state) => const PaymentPage(),
          ),
          GoRoute(
            path: '/users',
            builder: (context, state) => const RoleGuard(
              feature: AppFeature.userManagement,
              child: UserManagementPage(),
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const RoleGuard(
              feature: AppFeature.settings,
              child: SettingsPage(),
            ),
          ),
          GoRoute(
            path: '/societies',
            builder: (context, state) => const RoleGuard(
              feature: AppFeature.customers,
              child: SocietiesPage(),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Wraps a page and only renders it if the current user's role permits the
/// given [feature]. Otherwise it shows an "access denied" placeholder.
/// This complements the server-side RLS policies as a UX layer.
class RoleGuard extends ConsumerWidget {
  const RoleGuard({
    required this.feature,
    required this.child,
    super.key,
  });

  final AppFeature feature;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    return profileAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const _AccessDenied(),
      data: (profile) {
        if (profile != null && profile.can(feature)) {
          return child;
        }
        return const _AccessDenied();
      },
    );
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 56, color: Colors.grey.shade500),
              const SizedBox(height: 16),
              Text(
                'Access denied',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'You do not have permission to view this page.\n'
                'Contact an administrator if you believe this is a mistake.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => GoRouter.of(context).go('/dashboard'),
                child: const Text('Back to Overview'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StockPilotShell extends ConsumerWidget {
  const StockPilotShell({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the startup/auth-driven cloud pull alive while the app shell is
    // mounted, so remote data (inventory catalog, customers, etc.) is
    // pulled into the local DB on launch and after sign-in.
    ref.watch(startupSyncProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Scaffold(
            body: Row(
              children: [
                const DesktopNavigation(),
                Expanded(child: child),
              ],
            ),
          );
        }

        return Scaffold(
          body: child,
          bottomNavigationBar: const MobileNavigation(),
        );
      },
    );
  }
}

class DesktopNavigation extends ConsumerWidget {
  const DesktopNavigation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final profile = ref.watch(currentUserProfileProvider).value;
    bool can(AppFeature f) => profile?.can(f) ?? false;

    return Container(
      width: 250,
      color: const Color(0xFF123D32),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 28),
              child: Text(
                'Stock Pilot',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            const _Label('WORKSPACE'),

            _item(
              context,
              path,
              '/dashboard',
              Icons.dashboard_outlined,
              'Overview',
            ),

            if (can(AppFeature.inventory))
              _item(
                context,
                path,
                '/inventory',
                Icons.inventory_2_outlined,
                'Inventory',
              ),

            if (can(AppFeature.customers))
              _item(
                context,
                path,
                '/customers',
                Icons.people_outline,
                'Customers',
              ),

            _item(
              context,
              path,
              '/orders',
              Icons.shopping_bag_outlined,
              'Orders',
            ),

            _item(
              context,
              path,
              '/payments',
              Icons.payments_outlined,
              'Payments',
            ),

            const Spacer(),

            if (can(AppFeature.userManagement) ||
                can(AppFeature.settings)) ...[
              const _Label('ADMIN'),
              if (can(AppFeature.userManagement))
                _item(
                  context,
                  path,
                  '/users',
                  Icons.manage_accounts_outlined,
                  'User Management',
                ),
              if (can(AppFeature.customers))
                _item(
                  context,
                  path,
                  '/societies',
                  Icons.location_city_outlined,
                  'Societies',
                ),
              if (can(AppFeature.settings))
                _item(
                  context,
                  path,
                  '/settings',
                  Icons.settings_outlined,
                  'Settings',
                ),
            ],

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _item(
      BuildContext context,
      String current,
      String path,
      IconData icon,
      String label,
      ) {
    final selected = current == path;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 2,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: Icon(
            icon,
            color: selected ? Colors.white : Colors.white70,
          ),
          title: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
            ),
          ),
          selected: selected,
          selectedTileColor: Colors.white.withValues(alpha: .12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          onTap: () => context.go(path),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        24,
        12,
        24,
        8,
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class MobileNavigation extends ConsumerWidget {
  const MobileNavigation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final profile = ref.watch(currentUserProfileProvider).value;
    bool can(AppFeature f) => profile?.can(f) ?? false;

    // Build the destination set dynamically based on role. Overview,
    // Orders and Payments are available to everyone; Inventory and
    // Customers only to managers/admins.
    final destinations = <({String path, IconData icon, String label})>[
      (
        path: '/dashboard',
        icon: Icons.dashboard_outlined,
        label: 'Overview'
      ),
      if (can(AppFeature.inventory))
        (
          path: '/inventory',
          icon: Icons.inventory_2_outlined,
          label: 'Inventory'
        ),
      if (can(AppFeature.customers))
        (
          path: '/customers',
          icon: Icons.people_outline,
          label: 'Customers'
        ),
      (
        path: '/orders',
        icon: Icons.shopping_bag_outlined,
        label: 'Orders'
      ),
      (
        path: '/payments',
        icon: Icons.payments_outlined,
        label: 'Payments'
      ),
    ];

    var selected = destinations.indexWhere((d) => d.path == path);
    if (selected < 0) selected = 0;

    return NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: (index) =>
          context.go(destinations[index].path),
      destinations: destinations
          .map((d) => NavigationDestination(
                icon: Icon(d.icon),
                label: d.label,
              ))
          .toList(),
    );
  }
}
