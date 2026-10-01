import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stock_pilot/app/app.dart';

void main() {
  testWidgets('Stock Pilot app starts', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: StockPilotApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Inventory Items'), findsOneWidget);
  });
}