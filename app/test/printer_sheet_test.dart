import 'package:cloud9_inventory_app/i18n/lang.dart';
import 'package:cloud9_inventory_app/screens/printer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    Lang.instance.setForTest(AppLang.en);
  });

  testWidgets('printer sheet shows title, hint and a way back',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => FilledButton(
            onPressed: () => showPrinterSheet(c),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    // Header + contention hint render regardless of platform state
    // (BT stack is unreachable in widget tests by design).
    expect(find.text('Label printer'), findsOneWidget);
    expect(find.textContaining('Labelife'), findsOneWidget);
    expect(find.text('No printer'), findsOneWidget);
  });

  test('shortMac masks to the last two octets', () {
    expect(shortMac('AA:BB:CC:C0:75'), '···C0:75');
    expect(shortMac(''), '');
    expect(shortMac('nocolons'), 'nocolons');
  });
}
