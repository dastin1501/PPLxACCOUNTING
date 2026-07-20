// Basic smoke test for the POS Stock Manager app.
//
// This verifies that the app boots and renders its main navigation shell
// (defaulting to the "Sell" screen) without crashing.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pos_app/main.dart';

void main() {
  setUpAll(() {
    // Use the FFI-based sqlite implementation so the database can be
    // opened in the plain Dart/Flutter test VM (no platform channels).
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App boots and shows the Sell screen by default', (WidgetTester tester) async {
    await tester.pumpWidget(const PosApp());
    await tester.pump();

    expect(find.text('Sell'), findsWidgets);
    expect(find.text('Inventory'), findsOneWidget);
  });
}
