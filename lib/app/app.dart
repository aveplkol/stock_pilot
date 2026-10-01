import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'theme.dart';

class StockPilotApp extends StatefulWidget {
  const StockPilotApp({
    super.key,
    this.router,
  });

  final GoRouter? router;

  @override
  State<StockPilotApp> createState() => _StockPilotAppState();
}

class _StockPilotAppState extends State<StockPilotApp> {
  late final GoRouter _router;
  late final bool _ownsRouter;

  @override
  void initState() {
    super.initState();

    if (widget.router != null) {
      _router = widget.router!;
      _ownsRouter = false;
    } else {
      _router = createStockPilotRouter();
      _ownsRouter = true;
    }
  }

  @override
  void dispose() {
    if (_ownsRouter) {
      _router.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Stock Pilot',
      debugShowCheckedModeBanner: false,
      theme: StockPilotTheme.light,
      routerConfig: _router,
    );
  }
}