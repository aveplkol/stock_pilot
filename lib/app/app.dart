import 'package:flutter/material.dart';
import 'router.dart';
import 'theme.dart';

class StockPilotApp extends StatelessWidget {
  const StockPilotApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Stock Pilot',
    debugShowCheckedModeBanner: false,
    theme: StockPilotTheme.light,
    routerConfig: stockPilotRouter,
  );
}
