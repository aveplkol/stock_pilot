/// The role assigned to a user, controlling what they can access.
enum AppRole {
  admin,
  manager,
  staff;

  static AppRole fromString(String? value) {
    switch (value) {
      case 'admin':
        return AppRole.admin;
      case 'manager':
        return AppRole.manager;
      case 'staff':
      default:
        return AppRole.staff;
    }
  }

  String get asString => switch (this) {
        AppRole.admin => 'admin',
        AppRole.manager => 'manager',
        AppRole.staff => 'staff',
      };

  String get label => switch (this) {
        AppRole.admin => 'Admin',
        AppRole.manager => 'Manager',
        AppRole.staff => 'Staff',
      };
}

/// A feature/area of the app that can be gated by role.
enum AppFeature {
  dashboard,
  payments,
  orders,
  reports,
  inventory,
  customers,
  settings,
  userManagement,
}

/// Represents a user's profile loaded from the `user_profiles` table.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.role,
    this.name,
    this.companyCode,
  });

  final String id;
  final String email;
  final AppRole role;
  final String? name;

  /// The company/tenant this user belongs to (multi-tenancy).
  final String? companyCode;

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      email: (map['email'] as String?) ?? '',
      role: AppRole.fromString(map['role'] as String?),
      name: map['name'] as String?,
      companyCode: map['company_code'] as String?,
    );
  }

  /// A sensible fallback profile (lowest privilege) when none is found.
  factory UserProfile.fallback(String id, String email) => UserProfile(
        id: id,
        email: email,
        role: AppRole.staff,
      );

  bool get isAdmin => role == AppRole.admin;
  bool get isManager => role == AppRole.manager;
  bool get isStaff => role == AppRole.staff;

  /// Central permission matrix: which roles can access which features.
  bool can(AppFeature feature) {
    switch (feature) {
      case AppFeature.dashboard:
      case AppFeature.payments:
      case AppFeature.orders:
        // All roles can view the dashboard and record payments/orders.
        return true;
      case AppFeature.reports:
      case AppFeature.inventory:
      case AppFeature.customers:
        // Managers and admins only.
        return role == AppRole.admin || role == AppRole.manager;
      case AppFeature.settings:
      case AppFeature.userManagement:
        // Admins only.
        return role == AppRole.admin;
    }
  }
}