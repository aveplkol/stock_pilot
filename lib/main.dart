import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    // Use the implicit (token-in-URL) flow rather than PKCE for auth email
    // links. PKCE requires the code verifier created when the reset was
    // requested to still be present in local storage on the SAME client that
    // opens the link. That breaks when the link is opened on a different
    // device/browser (or after storage is cleared), surfacing as
    // `access_denied`. The implicit flow puts the recovery tokens directly in
    // the redirect URL, so `supabase_flutter` can establish the recovery
    // session wherever the link is opened.
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit,
    ),
  );

  runApp(
    const ProviderScope(
      child: StockPilotApp(),
    ),
  );
}