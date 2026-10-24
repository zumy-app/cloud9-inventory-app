// Helcim Smart Terminal push: request shape + status mapping.
import 'dart:convert';

import 'package:cloud9_inventory_app/helcim_terminal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('push posts to device URL with token header + cents-safe amount',
      () async {
    String? url;
    Map<String, String>? headers;
    Map<String, dynamic>? payload;
    final mock = MockClient((req) async {
      url = req.url.toString();
      headers = req.headers;
      payload = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response('{}', 202);
    });
    final r = await helcimPushPurchase(
      httpClient: mock,
      apiToken: 'tok123',
      deviceCode: 'dy6l',
      amount: 10.99,
      currency: 'USD',
      invoiceNumber: 'POS-1',
    );
    expect(r.accepted, isTrue);
    expect(r.statusCode, 202);
    expect(url,
        'https://api.helcim.com/v2/devices/dy6l/payment/purchase');
    expect(headers!['api-token'], 'tok123');
    expect(payload!['currency'], 'USD');
    expect(payload!['transactionAmount'], 10.99);
    expect(payload!['invoiceNumber'], 'POS-1');
  });

  test('push maps terminal statuses to actionable messages', () async {
    Future<String> msgFor(int code) async {
      final mock = MockClient((req) async => http.Response('{}', code));
      final r = await helcimPushPurchase(
          httpClient: mock,
          apiToken: 't',
          deviceCode: 'AB12',
          amount: 5.0);
      return r.message;
    }

    expect((await msgFor(403)), contains('token'));
    expect((await msgFor(404)), contains('device code'));
    expect((await msgFor(409)), contains('busy/offline'));
    final mock500 = MockClient((req) async => http.Response('boom', 500));
    final r500 = await helcimPushPurchase(
        httpClient: mock500, apiToken: 't', deviceCode: 'AB12', amount: 5.0);
    expect(r500.accepted, isFalse);
    expect(r500.message, contains('500'));
  });

  test('push refuses without config (no silent attempt)', () async {
    var called = false;
    final mock = MockClient((req) async {
      called = true;
      return http.Response('{}', 202);
    });
    final r = await helcimPushPurchase(
        httpClient: mock, apiToken: '', deviceCode: '', amount: 5.0);
    expect(r.accepted, isFalse);
    expect(called, isFalse);
  });
}
