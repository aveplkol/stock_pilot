import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_profile.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
    );
  }

  // ------------------------------------------------------------------
  // Profile / role
  // ------------------------------------------------------------------

  /// Fetches the current user's profile (including role) from Supabase.
  /// Returns a staff-level fallback if the row is missing or the fetch
  /// fails, so the app always has a safe, low-privilege default.
  Future<UserProfile?> fetchCurrentUserProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final data = await _client
          .from('user_profiles')
          .select('id,email,role,name')
          .eq('id', user.id)
          .maybeSingle();
      if (data == null) {
        return UserProfile.fallback(user.id, user.email ?? '');
      }
      return UserProfile.fromMap(data);
    } catch (_) {
      return UserProfile.fallback(user.id, user.email ?? '');
    }
  }

  /// Lists all user profiles. Only succeeds for admins (enforced by RLS).
  Future<List<UserProfile>> listUserProfiles() async {
    final data = await _client
        .from('user_profiles')
        .select('id,email,role,name')
        .order('email') as List<dynamic>;
    return data
        .cast<Map<String, dynamic>>()
        .map(UserProfile.fromMap)
        .toList();
  }

  /// Updates a user's role. Only succeeds for admins (enforced by RLS).
  Future<void> updateUserRole(String userId, AppRole role) async {
    await _client
        .from('user_profiles')
        .update({
          'role': role.asString,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
  }

  /// Creates a new user account with the given role.
  ///
  /// The role (and optional name) are embedded in the user metadata so the
  /// server-side `handle_new_user` trigger stamps the correct role onto the
  /// new `user_profiles` row. The new user receives a confirmation email
  /// (per your Supabase Auth settings) and signs in with the temporary
  /// password you share with them — they can change it later via the
  /// reset-password flow.
  ///
  /// Implementation note: the Supabase Admin API (which can create users
  /// without affecting the caller's session) requires the service-role key
  /// and must run on a trusted server/edge function — never in the client.
  /// This client-only method therefore uses the public sign-up flow, which
  /// signs the new user in. To keep the admin signed in, the caller should
  /// capture the admin's session first and restore it afterwards (see
  /// [currentSession] / [restoreSession]).
  Future<void> createUser({
    required String email,
    required String password,
    required AppRole role,
    String? name,
  }) async {
    await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'role': role.asString,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      },
    );
  }

  /// The current auth session (used to restore the admin's session after
  /// creating a user via the public sign-up flow).
  Session? get currentSession => _client.auth.currentSession;

  /// Restores a previously captured session (e.g. the admin's) using its
  /// refresh token.
  Future<void> restoreSession(Session session) async {
    final refreshToken = session.refreshToken;
    if (refreshToken == null) return;
    await _client.auth.setSession(refreshToken);
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }

  Future<void> resetPassword(String email) {
    return _client.auth.resetPasswordForEmail(
      email.trim(),
    );
  }
}