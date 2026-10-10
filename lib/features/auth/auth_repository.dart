import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_profile.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;

  /// Domain used to synthesize an email address when a user signs up with
  /// only a username or a mobile number. Supabase Auth requires an email (or
  /// phone) to create an account, so we build a stable, unique synthetic
  /// address and still record the real username/phone in the profile so the
  /// user can sign in with whichever credential they provided.
  static const String _syntheticEmailDomain = 'stockpilot.local';

  /// Creates an account using **any one** of email, username, or mobile
  /// number (plus a password). At least one identifier must be supplied.
  ///
  /// * If [email] is provided it is used directly (confirmation + reset
  ///   emails work as normal).
  /// * Otherwise a synthetic email is generated from the username or mobile
  ///   number so the Supabase account can be created; the real username and
  ///   phone are still stored on the profile for identifier-based login.
  Future<AuthResponse> signUp({
    String? email,
    required String password,
    String? companyCode,
    String? username,
    String? phone,
    String? name,
  }) {
    final trimmedEmail = email?.trim();
    final trimmedUsername = username?.trim();
    final trimmedPhone = phone?.trim();

    final hasEmail = trimmedEmail != null && trimmedEmail.isNotEmpty;
    final hasUsername = trimmedUsername != null && trimmedUsername.isNotEmpty;
    final hasPhone = trimmedPhone != null && trimmedPhone.isNotEmpty;

    if (!hasEmail && !hasUsername && !hasPhone) {
      throw const AuthException(
        'Provide an email, username, or mobile number to create an account.',
      );
    }

    // Choose a real email if given; otherwise synthesize a stable one from
    // the username (preferred) or mobile number.
    final effectiveEmail = hasEmail
        ? trimmedEmail
        : hasUsername
            ? '$trimmedUsername@$_syntheticEmailDomain'
            : '$trimmedPhone@$_syntheticEmailDomain';

    final metadata = <String, dynamic>{
      if (companyCode != null && companyCode.trim().isNotEmpty)
        'company_code': companyCode.trim(),
      if (hasUsername) 'username': trimmedUsername,
      if (hasPhone) 'phone': trimmedPhone,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
    };
    return _client.auth.signUp(
      email: effectiveEmail,
      password: password,
      data: metadata.isEmpty ? null : metadata,
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
          .select('id,email,role,name,company_code')
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
    String? companyCode,
  }) async {
    await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'role': role.asString,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (companyCode != null && companyCode.trim().isNotEmpty)
          'company_code': companyCode.trim(),
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

  /// Signs in with a username + password. Usernames are stored on the
  /// `user_profiles` row; we resolve the username to its email via an RPC
  /// (`email_for_username`) and then sign in with that email. This lets
  /// users who were created without a real email address (e.g. a synthetic
  /// `username@company.local`) still sign in by username.
  Future<AuthResponse> signInWithUsername({
    required String username,
    required String password,
  }) async {
    final email = await _client.rpc(
      'email_for_username',
      params: {'p_username': username.trim()},
    ) as String?;
    if (email == null || email.isEmpty) {
      throw const AuthException('No account found for that username.');
    }
    return _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static final RegExp _emailRegex =
      RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  /// Signs in with a single [identifier] that may be an email address, a
  /// mobile number, or a username, plus a [password].
  ///
  /// If the identifier looks like an email it is used directly; otherwise it
  /// is resolved to an email server-side via the `email_for_identifier` RPC
  /// (which matches on username OR phone). This lets users log in with
  /// whichever credential they remember.
  Future<AuthResponse> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    final id = identifier.trim();
    if (_emailRegex.hasMatch(id)) {
      return _client.auth.signInWithPassword(email: id, password: password);
    }
    // Resolve a username or mobile number to its account email.
    final email = await _client.rpc(
      'email_for_identifier',
      params: {'p_identifier': id},
    ) as String?;
    if (email == null || email.isEmpty) {
      throw const AuthException(
        'No account found for that username, mobile number, or email.',
      );
    }
    return _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }

  /// Deep link the auth emails redirect back to on **native** platforms.
  /// Must be registered in the Supabase dashboard (Authentication → URL
  /// Configuration → Redirect URLs) and handled by the mobile platform
  /// (Android intent filter / iOS associated domain / custom URL scheme).
  static const String _nativeAuthRedirectUrl = 'stockpilot://auth-callback';

  /// The redirect URL for auth emails (password reset, confirmations).
  ///
  /// On the **web** the custom `stockpilot://` scheme cannot be opened by a
  /// browser, so we must redirect back to the running web app's own origin
  /// (e.g. `http://localhost:57076/reset-password` in dev, or your deployed
  /// origin in production). On **native** platforms we use the registered
  /// custom-scheme deep link.
  ///
  /// IMPORTANT (Supabase config): every value this can return must be added
  /// to Authentication → URL Configuration → Redirect URLs in the Supabase
  /// dashboard, otherwise the link falls back to the Site URL and you get an
  /// `otp_expired` / "invalid or expired" error on an unexpected origin.
  String get _authRedirectUrl {
    if (kIsWeb) {
      final origin = Uri.base.origin; // e.g. http://localhost:57076
      return '$origin/reset-password';
    }
    return _nativeAuthRedirectUrl;
  }

  Future<void> resetPassword(String email) {
    return _client.auth.resetPasswordForEmail(
      email.trim(),
      // Ensures the "Reset password" email link opens the app (not a bare
      // Site URL) and lands on the in-app reset screen. Platform-aware so
      // the web build redirects to its own origin and native builds use the
      // custom-scheme deep link.
      redirectTo: _authRedirectUrl,
    );
  }

  /// Updates the signed-in user's password. Used by the in-app reset screen
  /// after the user arrives via the password-reset deep link (which
  /// establishes a recovery session).
  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }
}
