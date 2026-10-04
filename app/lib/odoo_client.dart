// Odoo JSON-RPC client for the MVP POC.
// Zero custom Odoo modules: uses /web/session/authenticate + /web/dataset/call_kw.
// Online-only. Session cookie persisted by the caller in flutter_secure_storage.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class OdooException implements Exception {
  final String message;
  OdooException(this.message);
  @override
  String toString() => 'OdooException: $message';
}

/// Minimal product view used by the Receive screen.
class InventoryProduct {
  final int variantId;
  final int tmplId;
  final String name;
  final String barcode;
  final String defaultCode;
  final double listPrice;
  final double standardPrice;
  final double qtyAvailable;
  final int? posCategId;

  const InventoryProduct({
    required this.variantId,
    required this.tmplId,
    required this.name,
    required this.barcode,
    required this.defaultCode,
    required this.listPrice,
    required this.standardPrice,
    required this.qtyAvailable,
    required this.posCategId,
  });

  static double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  factory InventoryProduct.fromMap(Map<String, dynamic> m) {
    final tmpl = m['product_tmpl_id'];
    final tmplId = tmpl is List && tmpl.isNotEmpty ? (tmpl[0] as num).toInt() : 0;
    final pos = m['pos_categ_ids'];
    int? posId;
    if (pos is List && pos.isNotEmpty) posId = (pos[0] as num).toInt();
    return InventoryProduct(
      variantId: (m['id'] as num).toInt(),
      tmplId: tmplId,
      name: (m['name'] ?? '').toString(),
      barcode: (m['barcode'] ?? '').toString(),
      defaultCode: (m['default_code'] ?? '').toString(),
      listPrice: _d(m['list_price']),
      standardPrice: _d(m['standard_price']),
      qtyAvailable: _d(m['qty_available']),
      posCategId: posId,
    );
  }
}

class PosCategory {
  final int id;
  final String name;
  const PosCategory({required this.id, required this.name});
}

class OdooClient {
  OdooClient({required this.baseUrl, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  String? _sessionCookie;

  static const _jsonHeaders = {'Content-Type': 'application/json'};

  String get _base => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers {
    final h = Map<String, String>.from(_jsonHeaders);
    if (_sessionCookie != null) h['Cookie'] = _sessionCookie!;
    return h;
  }

  /// Restore a persisted session cookie (e.g. "session_id=...").
  void setSessionCookie(String? cookie) => _sessionCookie = cookie;
  String? get sessionCookie => _sessionCookie;
  bool get isLoggedIn => _sessionCookie != null;

  void logout() => _sessionCookie = null;

  Map<String, dynamic> _decode(http.Response r) {
    dynamic body;
    try {
      body = jsonDecode(r.body);
    } catch (_) {
      throw OdooException('Bad server response (HTTP ${r.statusCode})');
    }
    if (body is Map && body['error'] != null) {
      final err = body['error'];
      final msg = err is Map
          ? (err['data'] is Map && err['data']['message'] != null
              ? err['data']['message'].toString()
              : err['message']?.toString() ?? 'Odoo error')
          : err.toString();
      throw OdooException(msg);
    }
    return body as Map<String, dynamic>;
  }

  void _storeCookie(http.Response r) {
    final setCookie = r.headers['set-cookie'];
    if (setCookie == null) return;
    final match = RegExp(r'session_id=[^;]+').firstMatch(setCookie);
    if (match != null) _sessionCookie = match.group(0);
  }

  /// POST /web/session/authenticate. Throws OdooException on failure.
  Future<void> authenticate({
    required String db,
    required String login,
    required String password,
  }) async {
    final r = await _http.post(
      Uri.parse('$_base/web/session/authenticate'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'jsonrpc': '2.0',
        'params': {'db': db, 'login': login, 'password': password},
      }),
    );
    final body = _decode(r);
    final result = body['result'];
    if (result == null || (result is Map && result['uid'] == null)) {
      throw OdooException('Invalid login');
    }
    _storeCookie(r);
    // Some proxies strip set-cookie; fall back to session_id in payload.
    if (_sessionCookie == null &&
        result is Map &&
        result['session_id'] != null) {
      _sessionCookie = 'session_id=${result['session_id']}';
    }
    if (_sessionCookie == null) {
      throw OdooException('Login ok but no session cookie (proxy stripped it)');
    }
  }

  Future<dynamic> callKw(
    String model,
    String method,
    List<dynamic> args, {
    Map<String, dynamic>? kwargs,
  }) async {
    final r = await _http.post(
      Uri.parse('$_base/web/dataset/call_kw/$model/$method'),
      headers: _headers,
      body: jsonEncode({
        'jsonrpc': '2.0',
        'params': {
          'model': model,
          'method': method,
          'args': args,
          'kwargs': kwargs ?? {},
        },
      }),
    );
    if (r.statusCode == 401) throw OdooException('SESSION_EXPIRED');
    final body = _decode(r);
    return body['result'];
  }

  /// Lookup by barcode, fallback default_code. Returns null when not found.
  /// Throws on duplicates (shows message, caller picks first is handled by UI).
  Future<({InventoryProduct product, bool duplicate})?> lookupProduct(
      String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;
    final result = await callKw('product.product', 'search_read', [], kwargs: {
      'domain': [
        '|',
        ['barcode', '=', code],
        ['default_code', '=', code],
      ],
      'fields': [
        'id',
        'product_tmpl_id',
        'name',
        'barcode',
        'default_code',
        'list_price',
        'standard_price',
        'pos_categ_ids',
        'qty_available',
      ],
      'limit': 2,
    });
    final rows = (result as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    return (
      product: InventoryProduct.fromMap(rows.first),
      duplicate: rows.length > 1,
    );
  }

  Future<List<PosCategory>> getPosCategories() async {
    final result =
        await callKw('pos.category', 'search_read', [], kwargs: {
      'domain': [],
      'fields': ['id', 'name'],
      'limit': 200,
      'order': 'name',
    });
    return (result as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return PosCategory(
          id: (m['id'] as num).toInt(), name: (m['name'] ?? '').toString());
    }).toList();
  }

  Future<int> _defaultCategId() async {
    final result =
        await callKw('product.category', 'search_read', [], kwargs: {
      'domain': [],
      'fields': ['id'],
      'limit': 1,
    });
    final rows = (result as List);
    if (rows.isEmpty) throw OdooException('No product.category found');
    return ((rows.first as Map)['id'] as num).toInt();
  }

  Future<int> _stockLocationId() async {
    final result =
        await callKw('stock.location', 'search_read', [], kwargs: {
      'domain': [
        ['usage', '=', 'internal'],
        ['name', 'ilike', 'Stock'],
      ],
      'fields': ['id'],
      'limit': 1,
    });
    final rows = (result as List);
    if (rows.isNotEmpty) return ((rows.first as Map)['id'] as num).toInt();
    final any = await callKw('stock.location', 'search_read', [], kwargs: {
      'domain': [
        ['usage', '=', 'internal']
      ],
      'fields': ['id'],
      'limit': 1,
    });
    if ((any as List).isEmpty) throw OdooException('No stock location found');
    return (((any).first as Map)['id'] as num).toInt();
  }

  /// Update sale/cost only when changed.
  Future<void> updatePrices(
      InventoryProduct p, double listPrice, double standardPrice) async {
    final vals = <String, dynamic>{};
    if ((listPrice - p.listPrice).abs() > 0.0001) vals['list_price'] = listPrice;
    if ((standardPrice - p.standardPrice).abs() > 0.0001) {
      vals['standard_price'] = standardPrice;
    }
    if (vals.isEmpty) return;
    await callKw('product.template', 'write', [
      [p.tmplId],
      vals,
    ]);
  }

  /// Bump on-hand by [addQty]: inventory_quantity = current + addQty.
  Future<double> addStock(InventoryProduct p, double addQty) async {
    if (addQty == 0) return p.qtyAvailable;
    final found = await callKw('stock.quant', 'search_read', [], kwargs: {
      'domain': [
        ['product_id', '=', p.variantId],
        ['location_id.usage', '=', 'internal'],
      ],
      'fields': ['id', 'inventory_quantity', 'quantity'],
      'limit': 1,
    });
    final rows = (found as List);
    if (rows.isNotEmpty) {
      final q = (rows.first as Map).cast<String, dynamic>();
      final current = q['quantity'] is num
          ? (q['quantity'] as num).toDouble()
          : p.qtyAvailable;
      final id = (q['id'] as num).toInt();
      await callKw('stock.quant', 'write', [
        [id],
        {'inventory_quantity': current + addQty},
      ]);
      try {
        await callKw('stock.quant', 'action_apply_inventory', [
          [id]
        ]);
      } catch (_) {
        // 18 auto-applies on write in most configs; ignore.
      }
      return current + addQty;
    }
    final locId = await _stockLocationId();
    final created = await callKw('stock.quant', 'create', [
      {
        'product_id': p.variantId,
        'location_id': locId,
        'inventory_quantity': p.qtyAvailable + addQty,
      }
    ]);
    try {
      await callKw('stock.quant', 'action_apply_inventory', [
        [created]
      ]);
    } catch (_) {}
    return p.qtyAvailable + addQty;
  }

  /// Create template + set variant barcode + set initial stock.
  /// Returns the variant id.
  Future<int> createProduct({
    required String name,
    required String barcode,
    required int posCategId,
    required double listPrice,
    required double standardPrice,
    required double qty,
  }) async {
    final categId = await _defaultCategId();
    final tmplId = await callKw('product.template', 'create', [
      {
        'name': name,
        'list_price': listPrice,
        'standard_price': standardPrice,
        'categ_id': categId,
        'pos_categ_ids': [
          [6, 0, [posCategId]]
        ],
        'sale_ok': true,
        'purchase_ok': true,
        'available_in_pos': true,
        'type': 'consu',
      }
    ]) as int;
    // Barcode lives on the variant in Odoo 18: set it on the single variant.
    final variants = await callKw('product.product', 'search_read', [], kwargs: {
      'domain': [
        ['product_tmpl_id', '=', tmplId]
      ],
      'fields': ['id'],
      'limit': 2,
    }) as List;
    if (variants.isNotEmpty) {
      final vid = (((variants.first) as Map)['id'] as num).toInt();
      if (barcode.trim().isNotEmpty) {
        await callKw('product.product', 'write', [
          [vid],
          {'barcode': barcode.trim()},
        ]);
      }
      if (qty != 0) {
        final locId = await _stockLocationId();
        final qid = await callKw('stock.quant', 'create', [
          {
            'product_id': vid,
            'location_id': locId,
            'inventory_quantity': qty,
          }
        ]);
        try {
          await callKw('stock.quant', 'action_apply_inventory', [
            [qid]
          ]);
        } catch (_) {}
      }
      return vid;
    }
    return 0;
  }
}
