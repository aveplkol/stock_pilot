import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://chjhuebnffqnhvxlprju.supabase.co',
    publishableKey: 'sb_publishable_rp698MRnjC5vg_lqemdFYZ',
  );

  runApp(
    const ProviderScope(
      child: StockPilotApp(),
    ),
  );
}