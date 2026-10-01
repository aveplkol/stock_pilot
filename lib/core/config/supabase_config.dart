/// Supabase configuration.
///
/// Values are provided at build/run time via `--dart-define` so that
/// credentials are not hard-coded in source control. Example:
///
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx
/// ```
///
/// For convenience during local development, the previous project values
/// are kept as fallback defaults. Override them in CI/production builds
/// with `--dart-define` (or a `--dart-define-from-file`).
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://chjhuebnffqnhvxlprju.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_rp698MRnjGphJDbW9sC5vg_lqemdFYZ',
  );
}