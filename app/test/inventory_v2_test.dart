import 'dart:convert';

import 'package:cloud9_inventory_app/audit_log.dart';
import 'package:cloud9_inventory_app/batch_store.dart';
import 'package:cloud9_inventory_app/category_map.dart';
import 'package:cloud9_inventory_app/odoo_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('category map resolves seeded pair', () {
    final pair = CategoryMap.resolve(
      pos: const PosCategory(id: 3, name: 'Drinks'),
      internalCats: const [
        PosCategory(id: 10, name: 'All'),
        PosCategory(id: 11, name: 'Drinks'),
      ],
    );
    expect(pair, isNotNull);
    expect(pair!.posId, 3);
    expect(pair.internalId, 11);
  });

  test('category map returns null when unmapped', () {
    final pair = CategoryMap.resolve(
      pos: const PosCategory(id: 3, name: 'Drinks'),
      internalCats: const [PosCategory(id: 10, name: 'All')],
    );
    expect(pair, isNull);
  });

  test('category filter matches substring case-insensitively', () {
    const cats = [
      PosCategory(id: 1, name: 'Drinks'),
      PosCategory(id: 2, name: 'Snacks'),
    ];
    expect(CategoryMap.filter(cats, 'dri').length, 1);
    expect(CategoryMap.filter(cats, '').length, 2);
  });

  test('batch key keeps barcode-less items separate', () {
    expect(
        BatchStore.keyOf(barcode: '', defaultCode: 'SKU1', name: 'A'),
        isNot(BatchStore.keyOf(
            barcode: '', defaultCode: 'SKU2', name: 'B')));
    expect(
        BatchStore.keyOf(barcode: '', defaultCode: '', name: 'A'),
        BatchStore.keyOf(barcode: '', defaultCode: '', name: 'a'));
  });

  test('quant error is translated to actionable text', () {
    final out = OdooException.friendly(
        'Quants cannot be created for consumables or services.');
    expect(out, contains('Storable'));
    expect(
        OdooException.friendly('Some other error'), 'Some other error');
  });

  test('setStorable enables stock tracking on the template', () async {
    String? lastBody;
    final mock = MockClient((req) async {
      lastBody = req.body;
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': true}), 200);
    });
    final client = OdooClient(baseUrl: 'https://x', httpClient: mock);
    const p = InventoryProduct(
      variantId: 1,
      tmplId: 42,
      name: 'n',
      barcode: 'b',
      defaultCode: '',
      listPrice: 1,
      standardPrice: 1,
      qtyAvailable: 0,
      posCategId: null,
      type: 'consu',
      isStorable: false,
    );
    expect(p.tracksStock, isFalse);
    await client.setStorable(p);
    expect(lastBody, contains('[42]'));
    expect(lastBody, contains('"is_storable":true'));
    expect(p.asStorable().tracksStock, isTrue);
  });

  test('stock tracking parses from is_storable', () {
    final tracked = InventoryProduct.fromMap({
      'id': 1,
      'product_tmpl_id': [2, 't'],
      'name': 'n',
      'type': 'consu',
      'is_storable': true,
    });
    expect(tracked.tracksStock, isTrue);
    final untracked = InventoryProduct.fromMap({
      'id': 1,
      'product_tmpl_id': [2, 't'],
      'name': 'n',
      'type': 'consu',
      'is_storable': false,
    });
    expect(untracked.tracksStock, isFalse);
  });

  test('product type defaults to storable when absent', () {
    final p = InventoryProduct.fromMap({
      'id': 1,
      'product_tmpl_id': [2, 't'],
      'name': 'n',
    });
    expect(p.type, 'consu');
    expect(p.tracksStock, isTrue);
  });

  test('archiveVariant deactivates the variant only', () async {
    String? lastBody;
    final mock = MockClient((req) async {
      lastBody = req.body;
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': true}), 200);
    });
    final client = OdooClient(baseUrl: 'https://x', httpClient: mock);
    const p = InventoryProduct(
      variantId: 7,
      tmplId: 42,
      name: 'n',
      barcode: 'b',
      defaultCode: '',
      listPrice: 1,
      standardPrice: 1,
      qtyAvailable: 0,
      posCategId: null,
    );
    await client.archiveVariant(p);
    expect(lastBody, contains('product.product'));
    expect(lastBody, contains('[7]'));
    expect(lastBody, contains('"active":false'));
  });

  test('audit log caps at 200 entries', () {
    final log = AuditLog.instance;
    log.clear();
    for (var i = 0; i < 250; i++) {
      log.add(AuditEntry(
        when: DateTime(2026, 1, 1),
        who: 't',
        mode: 'receive',
        productId: i,
        productName: 'p$i',
        field: 'qty',
        oldValue: '0',
        newValue: '1',
      ));
    }
    expect(log.entries.length, AuditLog.cap);
    expect(log.entries.first.productId, 249);
  });
}
