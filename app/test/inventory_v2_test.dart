import 'dart:convert';

import 'package:cloud9_inventory_app/audit_log.dart';
import 'package:cloud9_inventory_app/batch_store.dart';
import 'package:cloud9_inventory_app/category_map.dart';
import 'package:cloud9_inventory_app/odoo_client.dart';
import 'package:cloud9_inventory_app/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('access-denied error names the Odoo rights fix', () {
    final out = OdooException.friendly(
        "You are not allowed to modify 'Product Template' (product.template) records.");
    expect(out, contains('not allowed to change products'));
    expect(out, contains('Settings'));
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

  test('rankForName puts keyword match first without filtering', () {
    const cats = [
      PosCategory(id: 1, name: 'Snacks'),
      PosCategory(id: 2, name: 'Beverages - Taxable'),
      PosCategory(id: 3, name: 'Tobacco'),
    ];
    final ranked = CategoryMap.rankForName(cats, 'snapple apple');
    expect(ranked.length, 3);
    expect(ranked.first.name, 'Beverages - Taxable');
    expect(CategoryMap.matchScore(ranked.first, 'snapple apple'),
        greaterThan(0));
  });

  test('rankForName keeps Odoo order when there is no signal', () {
    const cats = [
      PosCategory(id: 1, name: 'Snacks'),
      PosCategory(id: 2, name: 'Beverages - Taxable'),
    ];
    final ranked = CategoryMap.rankForName(cats, 'mystery thing xyz');
    expect([ranked[0].id, ranked[1].id], [1, 2]);
    expect(CategoryMap.matchScore(cats[0], 'mystery thing xyz'), 0);
  });

  test('recent categories dedupe and cap at 5, most-recent first', () async {
    SharedPreferences.setMockInitialValues({});
    for (var i = 1; i <= 6; i++) {
      await SessionStore.saveRecentPosCat(i);
    }
    expect(await SessionStore.loadRecentPosCats(), [6, 5, 4, 3, 2]);
    await SessionStore.saveRecentPosCat(4);
    expect(await SessionStore.loadRecentPosCats(), [4, 6, 5, 3, 2]);
  });

  test('category lists are cached for the session (one HTTP call)', () async {    var calls = 0;
    final mock = MockClient((req) async {
      calls++;
      return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'result': [
              {'id': 7, 'name': 'Beverages - Taxable'}
            ]
          }),
          200);
    });
    final client = OdooClient(baseUrl: 'https://x', httpClient: mock);
    final first = await client.getPosCategories();
    final second = await client.getPosCategories();
    expect(calls, 1);
    expect(first.length, 1);
    expect(second.first.id, 7);
  });

  test('archiveProduct deactivates the template', () async {    String? lastBody;
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
    );
    await client.archiveProduct(p);
    expect(lastBody, contains('[42]'));
    expect(lastBody, contains('"active":false'));
  });

  test('callKw re-logs in once on 401 and retries the call', () async {
    var calls = 0;
    var authed = 0;
    String? refreshed;
    Future<({String db, String login, String password})> creds() async =>
        (db: 'odoo', login: 'u', password: 'p');
    final mock = MockClient((req) async {
      if (req.url.path.contains('authenticate')) {
        authed++;
        return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'result': {'uid': 7, 'session_id': 'fresh123'}
            }),
            200);
      }
      calls++;
      if (calls == 1) return http.Response('', 401);
      return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'result': [
              {'id': 1}
            ]
          }),
          200);
    });
    final client = OdooClient(baseUrl: 'https://x', httpClient: mock)
      ..credentialsProvider = creds
      ..onSessionRefreshed = (c) async => refreshed = c;
    final res = await client.callKw('product.product', 'search_read', []);
    expect((res as List).length, 1);
    expect(authed, 1);
    expect(calls, 2);
    expect(refreshed, 'session_id=fresh123');
    expect(client.sessionCookie, 'session_id=fresh123');
  });

  test('callKw surfaces SESSION_EXPIRED when refresh login fails', () async {
    Future<({String db, String login, String password})> creds() async =>
        (db: 'odoo', login: 'u', password: 'wrong');
    final mock = MockClient((req) async {
      if (req.url.path.contains('authenticate')) {
        return http.Response(
            jsonEncode(
                {'jsonrpc': '2.0', 'id': 1, 'result': null}),
            200);
      }
      return http.Response('', 401);
    });
    final client = OdooClient(baseUrl: 'https://x', httpClient: mock)
      ..credentialsProvider = creds;
    await expectLater(
      client.callKw('product.product', 'search_read', []),
      throwsA(isA<OdooException>().having(
          (e) => e.message, 'message', 'SESSION_EXPIRED')),
    );
  });

  test('searchProducts matches name, code, SKU and categories', () async {
    String? lastBody;
    final mock = MockClient((req) async {
      lastBody = req.body;
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': []}), 200);
    });
    final client = OdooClient(baseUrl: 'https://x', httpClient: mock);
    final res = await client.searchProducts(query: 'cola');
    expect(res.rows, isEmpty);
    expect(res.more, isFalse);
    final body = lastBody!;
    for (final field in [
      'name',
      'barcode',
      'default_code',
      'categ_id',
      'pos_categ_ids'
    ]) {
      expect(body, contains('"$field"'));
    }
    expect(body, contains('"ilike"'));
  });

  test('callKw surfaces SESSION_EXPIRED with no stored credentials',
      () async {
    final mock = MockClient((req) async => http.Response('', 401));
    final client = OdooClient(baseUrl: 'https://x', httpClient: mock);
    await expectLater(
      client.callKw('product.product', 'search_read', []),
      throwsA(isA<OdooException>().having(
          (e) => e.message, 'message', 'SESSION_EXPIRED')),
    );
  });

  test('callKw re-logs in on prod 200 code-100 session-expired', () async {
    // Prod Odoo (admin.cloud9market.net) returns HTTP 200 + code 100
    // "Odoo Session Expired", not 401. Must still auto-refresh + retry.
    var calls = 0;
    var authed = 0;
    String? refreshed;
    Future<({String db, String login, String password})> creds() async =>
        (db: 'odoo', login: 'u', password: 'p');
    String expiredBody() => jsonEncode({
          'jsonrpc': '2.0',
          'id': null,
          'error': {
            'code': 100,
            'message': 'Odoo Session Expired',
            'data': {
              'name': 'odoo.http.SessionExpiredException',
              'message': 'Session expired',
            },
          },
        });
    final mock = MockClient((req) async {
      if (req.url.path.contains('authenticate')) {
        authed++;
        return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'result': {'uid': 7, 'session_id': 'fresh123'}
            }),
            200);
      }
      calls++;
      if (calls == 1) return http.Response(expiredBody(), 200);
      return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'result': [
              {'id': 1}
            ]
          }),
          200);
    });
    final client = OdooClient(baseUrl: 'https://x', httpClient: mock)
      ..credentialsProvider = creds
      ..onSessionRefreshed = (c) async => refreshed = c;
    final res = await client.callKw('product.product', 'search_read', []);
    expect((res as List).length, 1);
    expect(authed, 1);
    expect(calls, 2);
    expect(refreshed, 'session_id=fresh123');
  });
}
