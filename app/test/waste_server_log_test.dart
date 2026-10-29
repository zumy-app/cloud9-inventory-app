// Hardened tests for the shared DB waste log (stock.scrap origin codec +
// per-user attribution + filtered fetch + totals).
//
// These pin the critique findings: delimiter handling, truncation, legacy
// compat, Odoo shape tolerance, createScrap precedence, and totals math.
import 'dart:convert';

import 'package:cloud9_inventory_app/odoo_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _p = InventoryProduct(
  variantId: 10,
  tmplId: 20,
  name: 'Milk',
  barcode: 'BC1',
  defaultCode: 'M1',
  listPrice: 4,
  standardPrice: 2.5,
  qtyAvailable: 5,
  posCategId: null,
);

MockClient _scrapMock({
  required List<Map<String, dynamic>> rows,
  void Function(Map<String, dynamic> createVals)? onCreate,
  String? Function(List<dynamic> domain)? onSearch,
}) {
  return MockClient((req) async {
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    final params = body['params'] as Map<String, dynamic>;
    final model = params['model'] as String;
    final method = params['method'] as String;
    final kwargs = (params['kwargs'] as Map?)?.cast<String, dynamic>() ?? {};
    if (model == 'stock.location') {
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': [
            {'id': 8}
          ]}),
          200);
    }
    if (model == 'stock.scrap' && method == 'search_read') {
      final domain = (kwargs['domain'] as List?) ?? [];
      final verdict = onSearch?.call(domain);
      if (verdict == 'throw') {
        return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'error': {'code': 400, 'message': 'bad domain'}
            }),
            200);
      }
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': rows}), 200);
    }
    if (model == 'stock.scrap' && method == 'create') {
      final args = params['args'] as List;
      onCreate?.call((args.first as Map).cast<String, dynamic>());
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': 99}), 200);
    }
    if (model == 'stock.scrap' && method == 'read') {
      return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'result': [
              {'id': 99, 'value': 5.0, 'scrap_qty': 2.0}
            ]
          }),
          200);
    }
    return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': true}), 200);
  });
}

void main() {
  group('buildWasteOrigin', () {
    test('minimal keys only', () {
      expect(
        buildWasteOrigin(reasonKey: 'expired', dispositionKey: 'trashed'),
        'WASTE|reason=expired|disp=trashed',
      );
    });

    test('omits empties, formats retail, trims', () {
      final o = buildWasteOrigin(
        reasonKey: ' expired ',
        dispositionKey: 'trashed',
        retailEach: 4.5,
      );
      expect(o, contains('reason=expired'));
      expect(o, contains('retail=4.50'));
      expect(o, isNot(contains('by=')));
      expect(o, isNot(contains('note=')));
    });

    test('retail <= 0 omitted', () {
      final o = buildWasteOrigin(
          reasonKey: 'expired', dispositionKey: 'trashed', retailEach: 0);
      expect(o, isNot(contains('retail=')));
      final neg = buildWasteOrigin(
          reasonKey: 'expired', dispositionKey: 'trashed', retailEach: -1);
      expect(neg, isNot(contains('retail=')));
    });

    test('sanitizes pipe + newline so parsing survives', () {
      final o = buildWasteOrigin(
        reasonKey: 'expired',
        dispositionKey: 'trashed',
        note: 'a|b\nc',
        supplierInvoice: 'INV|1',
      );
      expect(o, isNot(contains('a|b')));
      final meta = parseWasteOrigin(o);
      expect(meta.note, 'a/b c');
      expect(meta.supplierInvoice, 'INV/1');
    });

    test('per-field truncation keeps origin bounded', () {
      final longNote = List.filled(500, 'n').join();
      final o = buildWasteOrigin(
        reasonKey: 'expired',
        dispositionKey: 'trashed',
        loggedBy: List.filled(200, 'u').join(),
        note: longNote,
      );
      // 60 (by) + 180 (note) + fixed framing => well under ~500.
      expect(o.length, lessThan(400));
      final meta = parseWasteOrigin(o);
      expect(meta.note.length, 180);
      expect(meta.loggedBy.length, 60);
    });

    test('keeps = inside values (splits on first = only)', () {
      final o = buildWasteOrigin(
        reasonKey: 'expired',
        dispositionKey: 'trashed',
        note: 'a=b=c',
      );
      final meta = parseWasteOrigin(o);
      expect(meta.note, 'a=b=c');
    });
  });

  group('parseWasteOrigin', () {
    test('empty origin yields empty keys, never throws', () {
      final m = parseWasteOrigin('');
      expect(m.reasonKey, '');
      expect(m.dispositionKey, '');
      expect(m.loggedBy, '');
      expect(m.retailEach, 0.0);
    });

    test('non-WASTE origin is manual (no keys)', () {
      final m = parseWasteOrigin('PO12345');
      expect(m.reasonKey, '');
      expect(m.reasonLabel, '');
      expect(m.loggedBy, '');
    });

    test('unknown keys ignored, known keys survive', () {
      final m = parseWasteOrigin(
          'WASTE|reason=expired|future=x|disp=trashed|by=clerk');
      expect(m.reasonKey, 'expired');
      expect(m.dispositionKey, 'trashed');
      expect(m.loggedBy, 'clerk');
    });

    test('segments without = are skipped', () {
      final m = parseWasteOrigin('WASTE|reason=expired|garbage|disp=trashed');
      expect(m.reasonKey, 'expired');
      expect(m.dispositionKey, 'trashed');
    });

    test('invalid retail falls back to 0', () {
      final m = parseWasteOrigin('WASTE|reason=expired|retail=abc');
      expect(m.retailEach, 0.0);
    });

    test('unknown reason key keeps raw label (no crash)', () {
      final m = parseWasteOrigin('WASTE|reason=moldy|disp=trashed');
      expect(m.reasonKey, 'moldy');
      expect(m.reasonLabel, 'moldy');
    });

    test('legacy with slash parses both sides', () {
      final m =
          parseWasteOrigin('WASTE:Expired on shelf/Trashed / destroyed');
      expect(m.reasonKey, 'expired');
      expect(m.dispositionKey, 'trashed');
      expect(m.reasonLabel, contains('Expired'));
    });

    test('legacy without slash keeps reason, empty disp', () {
      final m = parseWasteOrigin('WASTE:Recall');
      expect(m.reasonKey, 'recall');
      expect(m.dispositionKey, '');
    });

    test('legacy unknown labels yield empty keys (manual-ish)', () {
      final m = parseWasteOrigin('WASTE:Something weird/Else');
      expect(m.reasonKey, '');
      expect(m.dispositionKey, '');
    });

    test('legacy match is case-insensitive', () {
      final m = parseWasteOrigin('WASTE:EXPIRED ON SHELF/DONATED');
      expect(m.reasonKey, 'expired');
      expect(m.dispositionKey, 'donated');
    });
  });

  group('loggedByDisplay', () {
    ScrapHistoryLine line({String by = '', String uidName = ''}) =>
        ScrapHistoryLine(
          id: 1,
          productName: 'Milk',
          qty: 1,
          dateDone: '',
          state: 'done',
          origin: '',
          loggedBy: by,
          createUidName: uidName,
        );

    test('create_uid name wins over app login', () {
      expect(line(by: 'clerk', uidName: 'Clerk User').loggedByDisplay,
          'Clerk User');
    });

    test('falls back to by= when Odoo name missing', () {
      expect(line(by: 'clerk').loggedByDisplay, 'clerk');
    });

    test('empty when neither source exists (UI renders dash)', () {
      expect(line().loggedByDisplay, '');
    });
  });

  group('fetchScrapHistory shapes', () {
    test('tolerates legacy minimal rows (no value/create_uid)', () async {
      final client = _scrapMock(rows: [
        {
          'id': 5,
          'product_id': [10, 'Milk'],
          'scrap_qty': 2.0,
          'state': 'done',
          'date_done': '2026-05-01 10:00:00',
          'origin': 'WASTE:test',
        }
      ]).let(OdooClient.new);
      final rows = await client.fetchScrapHistory();
      expect(rows.length, 1);
      expect(rows.first.productName, 'Milk');
      expect(rows.first.unitValue, 0.0);
      expect(rows.first.totalValue, 0.0);
      expect(rows.first.createUid, 0);
      expect(rows.first.loggedByDisplay, '');
    });

    test('qty 0 never divides (unit 0, no throw)', () async {
      final client = _scrapMock(rows: [
        {
          'id': 5,
          'product_id': [10, 'Milk'],
          'scrap_qty': 0,
          'state': 'draft',
          'date_done': false,
          'origin': 'WASTE|reason=expired',
          'value': 99.0,
          'create_uid': false,
          'create_date': false,
        }
      ]).let(OdooClient.new);
      final rows = await client.fetchScrapHistory();
      expect(rows.first.qty, 0.0);
      expect(rows.first.unitValue, 0.0);
      expect(rows.first.dateDone, '');
      expect(rows.first.createDate, '');
    });

    test('create_uid int shape + string value tolerated', () async {
      final client = _scrapMock(rows: [
        {
          'id': 7,
          'product_id': [10, 'Milk'],
          'scrap_qty': 2.0,
          'state': 'done',
          'date_done': '2026-05-01 10:00:00',
          'origin': 'WASTE|reason=spoiled|by=mgr',
          'value': 'not-a-number',
          'create_uid': 9,
          'create_date': '2026-05-01 10:01:00',
        }
      ]).let(OdooClient.new);
      final rows = await client.fetchScrapHistory();
      expect(rows.first.createUid, 9);
      expect(rows.first.createUidName, '');
      expect(rows.first.loggedByDisplay, 'mgr'); // falls back to by=
      expect(rows.first.unitValue, 0.0);
    });

    test('product_id false/absent never throws', () async {
      final client = _scrapMock(rows: [
        {
          'id': 8,
          'product_id': false,
          'scrap_qty': 1.0,
          'state': 'done',
          'date_done': '2026-05-01 10:00:00',
          'origin': '',
          'value': 2.0,
          'create_uid': [3, 'U'],
          'create_date': '2026-05-01 10:01:00',
        }
      ]).let(OdooClient.new);
      final rows = await client.fetchScrapHistory();
      expect(rows.first.productName, 'false');
    });

    test('query is sent server-side; offset is passed through', () async {
      List<dynamic>? seenDomain;
      int? seenOffset;
      final mock = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final params = body['params'] as Map<String, dynamic>;
        final kwargs =
            (params['kwargs'] as Map).cast<String, dynamic>();
        if ((params['model'] as String) == 'stock.location') {
          return http.Response(
              jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': [
                {'id': 8}
              ]}),
              200);
        }
        seenDomain = (kwargs['domain'] as List).toList();
        seenOffset = kwargs['offset'] as int?;
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': []}), 200);
      });
      final client = OdooClient(baseUrl: 'https://x', httpClient: mock);
      await client.fetchScrapHistory(limit: 50, offset: 120, query: 'milk');
      expect(seenOffset, 120);
      expect(seenDomain.toString(), contains('milk'));
      expect(seenDomain.toString(), contains('product_id.name'));
    });

    test('bad domain shape falls back to unfiltered (query not fatal)',
        () async {
      var calls = 0;
      final mock = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final params = body['params'] as Map<String, dynamic>;
        if ((params['model'] as String) == 'stock.location') {
          return http.Response(
              jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': [
                {'id': 8}
              ]}),
              200);
        }
        calls++;
        if (calls == 1) {
          // Simulate old Odoo rejecting product_id.name.
          return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'error': {'code': 400, 'message': 'bad domain'}
              }),
              200);
        }
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': []}), 200);
      });
      final client = OdooClient(baseUrl: 'https://x', httpClient: mock);
      final rows =
          await client.fetchScrapHistory(query: 'milk');
      expect(rows, isEmpty);
      expect(calls, 2);
    });
  });

  group('createScrap origin precedence', () {
    test('reasonKey wins over explicit origin', () async {
      Map<String, dynamic>? sent;
      final client = _scrapMock(
        rows: [],
        onCreate: (v) => sent = v,
      ).let(OdooClient.new);
      await client.createScrap(
        product: _p,
        qty: 1,
        origin: 'CUSTOM-SHOULD-LOSE',
        reasonKey: 'expired',
        dispositionKey: 'trashed',
        loggedBy: 'clerk',
      );
      expect(sent!['origin'].toString(), startsWith('WASTE|'));
      expect(sent!['origin'].toString(), contains('reason=expired'));
      expect(sent!['origin'].toString(), isNot(contains('CUSTOM')));
    });

    test('explicit origin used when no reason/disposition keys', () async {
      Map<String, dynamic>? sent;
      final client = _scrapMock(
        rows: [],
        onCreate: (v) => sent = v,
      ).let(OdooClient.new);
      await client.createScrap(
          product: _p, qty: 1, origin: 'WASTE:Expired on shelf/Trashed');
      expect(sent!['origin'], 'WASTE:Expired on shelf/Trashed');
    });

    test('no origin key at all when both empty', () async {
      Map<String, dynamic>? sent;
      final client = _scrapMock(
        rows: [],
        onCreate: (v) => sent = v,
      ).let(OdooClient.new);
      await client.createScrap(product: _p, qty: 1);
      expect(sent!.containsKey('origin'), isFalse);
    });

    test('structured origin carries barcode/sku/expiry/note/sup', () async {
      Map<String, dynamic>? sent;
      final client = _scrapMock(
        rows: [],
        onCreate: (v) => sent = v,
      ).let(OdooClient.new);
      await client.createScrap(
        product: _p,
        qty: 2,
        reasonKey: 'expired',
        dispositionKey: 'trashed',
        loggedBy: 'clerk',
        packageExpiry: '2026-01-01',
        note: 'shelf check',
        supplierInvoice: 'INV1',
        retailEach: 4.99,
      );
      final o = sent!['origin'].toString();
      expect(o, contains('code=BC1'));
      expect(o, contains('sku=M1'));
      expect(o, contains('expiry=2026-01-01'));
      expect(o, contains('sup=INV1'));
      expect(o, contains('retail=4.99'));
      // Round-trips through the parser (what the browser will decode).
      final meta = parseWasteOrigin(o);
      expect(meta.reasonKey, 'expired');
      expect(meta.loggedBy, 'clerk');
    });
  });

  group('ScrapTotals', () {
    ScrapHistoryLine row(double qty, double unit) => ScrapHistoryLine(
          id: 1,
          productName: 'Milk',
          qty: qty,
          dateDone: '',
          state: 'done',
          origin: '',
          unitValue: unit,
        );

    test('empty set is zero', () {
      final t = ScrapTotals.of(const []);
      expect(t.count, 0);
      expect(t.qty, 0.0);
      expect(t.value, 0.0);
    });

    test('sums qty and frozen value', () {
      final t = ScrapTotals.of([row(2, 2.5), row(1, 3.0)]);
      expect(t.count, 2);
      expect(t.qty, 3.0);
      expect(t.value, closeTo(8.0, 0.001));
    });
  });
}

extension on MockClient {
  OdooClient let(OdooClient Function({required String baseUrl, http.Client? httpClient}) f) =>
      f(baseUrl: 'https://x', httpClient: this);
}
