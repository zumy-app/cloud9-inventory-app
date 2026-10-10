import 'dart:convert';

import 'package:cloud9_inventory_app/label_collections.dart';
import 'package:cloud9_inventory_app/odoo_client.dart';
import 'package:cloud9_inventory_app/screens/browse.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _row(int id, String name) => {
  'id': id,
  'product_tmpl_id': [id * 10, name],
  'name': name,
  'barcode': 'BC$id',
  'default_code': '',
  'list_price': 1.5,
  'standard_price': 1.0,
  'qty_available': 3.0,
  'pos_categ_ids': [5],
  'type': 'consu',
  'is_storable': true,
};

void main() {
  test('mapProductToPicked resolves size + category, keeps variant', () {
    const p = InventoryProduct(
      variantId: 42,
      tmplId: 7,
      name: 'Coke 12pk',
      barcode: 'BC42',
      defaultCode: '',
      listPrice: 9.99,
      standardPrice: 5,
      qtyAvailable: 10,
      posCategId: 5,
    );
    final picked = mapProductToPicked(p, 'Drinks');
    expect(picked.name, 'Coke');
    expect(picked.size, '12pk');
    expect(picked.price, 9.99);
    expect(picked.category, 'Drinks');
    expect(picked.variantId, 42);
  });

  test('badge key matches stored line key for the same product', () {
    const p = InventoryProduct(
      variantId: 1,
      tmplId: 1,
      name: 'Pecan Spinwheels, 2.1 oz',
      barcode: 'BC1',
      defaultCode: '',
      listPrice: 2.49,
      standardPrice: 1,
      qtyAvailable: 0,
      posCategId: null,
    );
    final picked = mapProductToPicked(p, '');
    final badgeKey = LabelCollections.keyOf(
      barcode: picked.barcode,
      defaultCode: picked.defaultCode,
      name: picked.name,
    );
    // Same rule the store uses at insert time.
    expect(
      badgeKey,
      LabelCollections.keyOf(
        barcode: 'BC1',
        defaultCode: '',
        name: 'Pecan Spinwheels',
      ),
    );
  });

  test('fetchAllMatching pages until short page', () async {
    final mock = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final kwargs = (body['params'] as Map)['kwargs'] as Map<String, dynamic>;
      final offset = (kwargs['offset'] ?? 0) as int;
      final rows = offset == 0
          ? [_row(1, 'A'), _row(2, 'B')]
          : [_row(3, 'C 12pk')];
      return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': rows}),
        200,
      );
    });
    final client = OdooClient(baseUrl: 'https://x', httpClient: mock);
    final all = await fetchAllMatching(
      client,
      query: '',
      posCategId: null,
      page: 2,
    );
    expect(all.map((p) => p.variantId), [1, 2, 3]);
    expect(all.last.name, 'C 12pk');
  });

  test('fetchAllMatching stops at cap', () async {
    var calls = 0;
    final mock = MockClient((req) async {
      calls++;
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'result': [_row(calls * 10 + 1, 'A'), _row(calls * 10 + 2, 'B')],
        }),
        200,
      );
    });
    final client = OdooClient(baseUrl: 'https://x', httpClient: mock);
    final all = await fetchAllMatching(
      client,
      query: '',
      posCategId: null,
      page: 2,
      cap: 5,
    );
    expect(all.length, 6); // 3 full pages of 2, then length >= cap
    expect(calls, 3);
  });
}
