// Picker flow: browse in pick mode toggles selection, badges existing
// lines, and pops label payloads (Add vs Add & Print). The picker never
// touches the store or prefs — only the Odoo client is mocked.
import 'dart:convert';

import 'package:cloud9_inventory_app/label_collections.dart';
import 'package:cloud9_inventory_app/odoo_client.dart';
import 'package:cloud9_inventory_app/screens/browse.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _row(int id, String name) => {
  'id': id,
  'product_tmpl_id': [id * 10, name],
  'name': name,
  'barcode': 'BC$id',
  'default_code': '',
  'list_price': 2.0,
  'standard_price': 1.0,
  'qty_available': 5.0,
  'pos_categ_ids': [5],
  'type': 'consu',
  'is_storable': true,
};

MockClient _mock() => MockClient((req) async {
  final body = jsonDecode(req.body) as Map<String, dynamic>;
  final params = body['params'] as Map<String, dynamic>;
  if (params['model'] == 'pos.category') {
    return http.Response(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'result': [
          {'id': 5, 'name': 'Drinks'},
        ],
      }),
      200,
    );
  }
  return http.Response(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'result': [_row(1, 'Coke 12pk'), _row(2, 'Pepsi')],
    }),
    200,
  );
});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tap toggles, Add pops payloads with printNow=false', (
    tester,
  ) async {
    PickResult? captured;
    final client = OdooClient(baseUrl: 'https://x', httpClient: _mock());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => FilledButton(
            onPressed: () async {
              captured = await Navigator.of(ctx).push<PickResult>(
                MaterialPageRoute(
                  builder: (_) => BrowseScreen(
                    client: client,
                    user: 'u',
                    editable: false,
                    title: 'Add to Batch 1',
                    pickMode: true,
                  ),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Coke 12pk'), findsOneWidget);

    await tester.tap(find.text('Coke 12pk'));
    await tester.pumpAndSettle();
    expect(find.text('Add (1)'), findsOneWidget);

    await tester.tap(find.text('Add (1)'));
    await tester.pumpAndSettle();
    expect(captured, isNotNull);
    expect(captured!.printNow, isFalse);
    expect(captured!.items.length, 1);
    expect(captured!.items.single.name, 'Coke');
    expect(captured!.items.single.size, '12pk');
    expect(captured!.items.single.category, 'Drinks');
  });

  testWidgets('Add & Print pops printNow=true; badges mark existing', (
    tester,
  ) async {
    PickResult? captured;
    final client = OdooClient(baseUrl: 'https://x', httpClient: _mock());
    final existing = {
      LabelCollections.keyOf(barcode: 'BC1', defaultCode: '', name: 'Coke'),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => FilledButton(
            onPressed: () async {
              captured = await Navigator.of(ctx).push<PickResult>(
                MaterialPageRoute(
                  builder: (_) => BrowseScreen(
                    client: client,
                    user: 'u',
                    editable: false,
                    title: 'Add to Batch 1',
                    pickMode: true,
                    existingKeys: existing,
                  ),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.textContaining('In collection'), findsOneWidget);

    await tester.tap(find.text('Pepsi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add & Print (1)'));
    await tester.pumpAndSettle();
    expect(captured, isNotNull);
    expect(captured!.printNow, isTrue);
    expect(captured!.items.single.name, 'Pepsi');
  });

  testWidgets('info button opens detail sheet without printing', (
    tester,
  ) async {
    final client = OdooClient(baseUrl: 'https://x', httpClient: _mock());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => FilledButton(
            onPressed: () {
              Navigator.of(ctx).push(
                MaterialPageRoute(
                  builder: (_) => BrowseScreen(
                    client: client,
                    user: 'u',
                    editable: false,
                    title: 'Add to Batch 1',
                    pickMode: true,
                  ),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    // Pick-mode sheet offers Select, never Print.
    expect(find.text('Select this item'), findsOneWidget);
    expect(find.text('Print label'), findsNothing);
  });
}
