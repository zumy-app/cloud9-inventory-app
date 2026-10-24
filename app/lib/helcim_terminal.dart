// Helcim Smart Terminal push: POST the order total to the physical
// terminal so the customer taps there. The API token never leaves secure
// storage except in the HTTPS Authorization header to api.helcim.com.
// Card data never touches the phone — the terminal handles it (PCI scope).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'session_store.dart';

/// Result of pushing a total to the terminal. 202 = terminal lit up and
/// waiting for the customer (NOT paid). Completion is confirmed by the
/// cashier watching the terminal, then recorded in Odoo.
class HelcimPushResult {
  final bool accepted;
  final int statusCode;
  final String message;
  const HelcimPushResult(
      {required this.accepted,
      required this.statusCode,
      required this.message});
}

/// POST /v2/devices/{code}/payment/purchase. Pure + mock-tested.
Future<HelcimPushResult> helcimPushPurchase({
  http.Client? httpClient,
  required String apiToken,
  required String deviceCode,
  required double amount,
  String currency = 'USD',
  String? invoiceNumber,
}) async {
  final client = httpClient ?? http.Client();
  final code = deviceCode.trim();
  if (apiToken.trim().isEmpty || code.isEmpty) {
    return const HelcimPushResult(
        accepted: false,
        statusCode: 0,
        message: 'Helcim not configured (token/device code missing).');
  }
  if (amount <= 0) {
    return const HelcimPushResult(
        accepted: false, statusCode: 0, message: 'Amount must be > 0.');
  }
  try {
    final r = await client.post(
      Uri.parse('https://api.helcim.com/v2/devices/$code/payment/purchase'),
      headers: {
        'accept': 'application/json',
        'content-type': 'application/json',
        'api-token': apiToken,
      },
      body: jsonEncode({
        'currency': currency,
        'transactionAmount': (amount * 100).round() / 100.0,
        if (invoiceNumber != null && invoiceNumber.isNotEmpty)
          'invoiceNumber': invoiceNumber,
      }),
    );
    switch (r.statusCode) {
      case 202:
        return const HelcimPushResult(
            accepted: true,
            statusCode: 202,
            message: 'Terminal notified — waiting for customer.');
      case 403:
        return const HelcimPushResult(
            accepted: false,
            statusCode: 403,
            message: 'Helcim rejected the token (403). Check the API token.');
      case 404:
        return const HelcimPushResult(
            accepted: false,
            statusCode: 404,
            message:
                'Terminal not found (404). Check the 4-character device code.');
      case 409:
        return const HelcimPushResult(
            accepted: false,
            statusCode: 409,
            message:
                'Terminal busy/offline (409). Finish or cancel the current payment on the device first.');
      default:
        return HelcimPushResult(
            accepted: false,
            statusCode: r.statusCode,
            message:
                'Helcim error ${r.statusCode}: ${_shortBody(r.body)}');
    }
  } catch (e) {
    return HelcimPushResult(
        accepted: false, statusCode: 0, message: 'Network error: $e');
  }
}

String _shortBody(String b) {
  final s = b.trim();
  return s.length > 160 ? '${s.substring(0, 160)}…' : s;
}

/// Helcim device config: token in secure storage, code/currency in prefs.
class HelcimStore extends ChangeNotifier {
  HelcimStore._();
  static final HelcimStore instance = HelcimStore._();

  static const _kDevice = 'helcim_device';
  static const _kCurrency = 'helcim_currency';

  String deviceCode = '';
  String currency = 'USD';
  bool hasToken = false;

  bool get isConfigured => hasToken && deviceCode.trim().isNotEmpty;

  Future<void> load() async {
    try {
      final t = await SessionStore.loadHelcimToken();
      hasToken = t != null && t.isNotEmpty;
      final p = await SharedPreferences.getInstance();
      deviceCode = p.getString(_kDevice) ?? '';
      currency = p.getString(_kCurrency) ?? 'USD';
      notifyListeners();
    } catch (_) {}
  }

  Future<void> save(
      {required String token,
      required String device,
      required String curr}) async {
    if (token.trim().isNotEmpty) {
      await SessionStore.saveHelcimToken(token.trim());
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDevice, device.trim().toUpperCase());
    await p.setString(_kCurrency, curr);
    await load();
  }

  Future<void> clearToken() async {
    await SessionStore.clearHelcimToken();
    await load();
  }
}
