// Native POS: whitebox cart math + integration RPC shapes.
// Guards the checkout flow: totals, tender, order+payment+paid sequence.
import 'dart:convert';

import 'package:cloud9_inventory_app/odoo_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // ---- Whitebox: cart math ----
  test('whitebox: lineTotal and tax extraction', () {
    expect(PosCart.lineTotal(2.5, 4), 10.0);
    // 6.625% included in $10.66 -> ~$0.66 tax.
    expect(PosCart.includedTax(10.66, 6.625), closeTo(0.66, 0.01));
    expect(PosCart.includedTax(10.0, 0), 0.0);
    expect(PosCart.excludedTax(10.0, 8.875), closeTo(0.8875, 0.0001));
  });

  test('whitebox: totals mix included + excluded taxes', () {
    const taxes = {
      1: PosTax(id: 1, amount: 10, priceInclude: true),
      2: PosTax(id: 2, amount: 5, priceInclude: false),
    };
    final t = PosCart.totals([
      (price: 11.0, qty: 1, taxIds: [1]), // incl 10% -> tax $1.00
      (price: 20.0, qty: 2, taxIds: [2]), // excl 5% -> tax $2.00
    ], taxes);
    expect(t.subtotal, 51.0);
    expect(t.tax, closeTo(3.0, 0.001));
    expect(t.total, closeTo(53.0, 0.001));
  });

  test('whitebox: unknown taxes count as 0%', () {
    final t = PosCart.totals([
      (price: 5.0, qty: 2, taxIds: [999]),
    ], const {});
    expect(t.subtotal, 10.0);
    expect(t.tax, 0.0);
    expect(t.total, 10.0);
  });

  // ---- Integration: register + catalog ----
  MockClient mockShop() => MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final params = body['params'] as Map<String, dynamic>;
        final model = params['model'];
        if (model == 'pos.config') {
          return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'result': [
                  {'id': 1, 'name': 'Main'}
                ]
              }),
              200);
        }
        if (model == 'pos.session') {
          return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'result': [
                  {
                    'id': 9,
                    'name': 'Session 1',
                    'state': 'opened',
                    'config_id': [1, 'Main']
                  }
                ]
              }),
              200);
        }
        if (model == 'product.product') {
          return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'result': [
                  {
                    'id': 10,
                    'name': 'Milk',
                    'barcode': 'BC1',
                    'list_price': 4.0,
                    'taxes_id': [5],
                    'qty_available': 12.0
                  }
                ]
              }),
              200);
        }
        if (model == 'account.tax') {
          return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'result': [
                  {'id': 5, 'amount': 6.625, 'price_include': true}
                ]
              }),
              200);
        }
        if (model == 'pos.payment.method') {
          return http.Response(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': 1,
                'result': [
                  {'id': 2, 'name': 'Cash', 'type': 'cash'},
                  {'id': 3, 'name': 'Card', 'type': 'bank'}
                ]
              }),
              200);
        }
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': []}), 200);
      });

  test('integration: register, session, products, taxes, methods', () async {
    final c = OdooClient(baseUrl: 'https://x', httpClient: mockShop());
    final shops = await c.posConfigs();
    expect(shops.length, 1);
    final s = await c.openPosSession(1);
    expect(s, isNotNull);
    expect(s!.state, 'opened');
    final prods = await c.posProducts('milk');
    expect(prods.first.barcode, 'BC1');
    final taxes = await c.posTaxes([5]);
    expect(taxes[5]!.amount, 6.625);
    final methods = await c.posPaymentMethods();
    expect(methods.any((m) => m.isCash), isTrue);
  });

  test('integration: closed register returns null session', () async {
    final mock = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final params = body['params'] as Map<String, dynamic>;
      if (params['model'] == 'pos.session') {
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': []}), 200);
      }
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': []}), 200);
    });
    final c = OdooClient(baseUrl: 'https://x', httpClient: mock);
    expect(await c.openPosSession(1), isNull);
  });

  // ---- Integration: full checkout sequence ----
  test('integration: checkout creates order, payment, pays, reads receipt',
      () async {
    final calls = <String>[];
    final mock = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final params = body['params'] as Map<String, dynamic>;
      final key = "${params['model']}/${params['method']}";
      calls.add(key);
      if (key == 'pos.order/create') {
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': 101}), 200);
      }
      if (key == 'pos.payment/create') {
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': 201}), 200);
      }
      if (key == 'pos.order/action_pos_order_paid') {
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': true}), 200);
      }
      if (key == 'pos.order/read') {
        return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'result': [
                {'id': 101, 'pos_reference': 'Order 0001', 'amount_total': 8.0}
              ]
            }),
            200);
      }
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': true}), 200);
    });
    final c = OdooClient(baseUrl: 'https://x', httpClient: mock);
    final r = await c.posCheckout(
      sessionId: 9,
      lines: const [
        PosCartLine(productId: 10, qty: 2, priceUnit: 4.0, taxIds: [5])
      ],
      tenders: const [PosTender(methodId: 2, amount: 10.0)],
    );
    expect(calls, contains('pos.order/create'));
    expect(calls, contains('pos.payment/create'));
    expect(calls, contains('pos.order/action_pos_order_paid'));
    expect(r.reference, 'Order 0001');
    expect(r.total, 8.0);
    expect(r.change, closeTo(2.0, 0.001));
  });

  test('integration: payment failure keeps draft message, not silent',
      () async {
    final mock = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final params = body['params'] as Map<String, dynamic>;
      final key = "${params['model']}/${params['method']}";
      if (key == 'pos.order/create') {
        return http.Response(
            jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': 101}), 200);
      }
      if (key == 'pos.payment/create') {
        return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'error': {
                'code': 200,
                'message': 'Odoo Server Error',
                'data': {'message': 'No payment method'}
              }
            }),
            200);
      }
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': true}), 200);
    });
    final c = OdooClient(baseUrl: 'https://x', httpClient: mock);
    try {
      await c.posCheckout(
        sessionId: 9,
        lines: const [PosCartLine(productId: 10, qty: 1, priceUnit: 4.0)],
        tenders: const [PosTender(methodId: 2, amount: 4.0)],
      );
      fail('expected throw');
    } on OdooException catch (e) {
      expect(e.message, contains('DRAFT'));
      expect(e.message, contains('101'));
    }
  });
}
