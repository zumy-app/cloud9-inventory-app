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

  /// Translate known Odoo server errors into actionable staff-facing text.
  static String friendly(String msg) {
    if (msg.contains('Quants cannot be created')) {
      return 'Odoo refuses stock for products without stock tracking. '
          'In Odoo, open the product and enable stock tracking '
          '(Storable / Track Inventory), then try again. ($msg)';
    }
    if (msg.contains('not allowed to modify')) {
      return 'Your Odoo user is not allowed to change products. '
          'Ask a manager to grant product edit rights in Odoo '
          '(Settings → Users → access rights), then try again. ($msg)';
    }
    return msg;
  }
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
  final String type; // 'consu' | 'service' | 'combo'
  final bool isStorable; // Odoo 18 gate for quants (type stays 'consu')

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
    this.type = 'consu',
    this.isStorable = true,
  });

  bool get tracksStock => isStorable;

  InventoryProduct asStorable() => InventoryProduct(
        variantId: variantId,
        tmplId: tmplId,
        name: name,
        barcode: barcode,
        defaultCode: defaultCode,
        listPrice: listPrice,
        standardPrice: standardPrice,
        qtyAvailable: qtyAvailable,
        posCategId: posCategId,
        type: type,
        isStorable: true,
      );

  static double _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  /// Odoo returns boolean false for unset char fields — never show "false".
  static String _s(dynamic v) {
    if (v == null || v is bool) return '';
    return v.toString();
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
      name: _s(m['name']),
      barcode: _s(m['barcode']),
      defaultCode: _s(m['default_code']),
      listPrice: _d(m['list_price']),
      standardPrice: _d(m['standard_price']),
      qtyAvailable: _d(m['qty_available']),
      posCategId: posId,
      type: (m['type'] ?? 'consu').toString(),
      isStorable: m['is_storable'] is bool ? m['is_storable'] as bool : true,
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

  // In-memory category cache (per MVP tech plan: fetch once, cache 24h).
  // The app holds one shared OdooClient, so this covers every screen.
  static const _catsTtl = Duration(hours: 24);
  List<PosCategory>? _posCatsCache;
  DateTime _posCatsCacheAt = DateTime.fromMillisecondsSinceEpoch(0);
  List<PosCategory>? _internalCatsCache;
  DateTime _internalCatsCacheAt = DateTime.fromMillisecondsSinceEpoch(0);

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

  /// Supplies stored credentials for one transparent re-login when a call
  /// hits 401 (see [callKw]). Null/absent means "no auto-refresh".
  Future<({String db, String login, String password})?> Function()?
      credentialsProvider;

  /// Invoked with the fresh cookie after a transparent re-login so the
  /// caller can persist it (form state is untouched — nothing is lost).
  Future<void> Function(String cookie)? onSessionRefreshed;

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
      throw OdooException(OdooException.friendly(msg));
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

  /// Single RPC round-trip. Throws OdooException('SESSION_EXPIRED') on 401.
  Future<dynamic> _postCallKw(
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

  /// RPC with one transparent re-login on 401: if [credentialsProvider]
  /// yields stored creds, re-authenticate, persist the fresh cookie via
  /// [onSessionRefreshed], and retry the call once. The in-progress screen
  /// never notices (no logout, no lost form). Throws SESSION_EXPIRED when
  /// refresh is unavailable or fails.
  Future<dynamic> callKw(
    String model,
    String method,
    List<dynamic> args, {
    Map<String, dynamic>? kwargs,
  }) async {
    try {
      return await _postCallKw(model, method, args, kwargs: kwargs);
    } on OdooException catch (e) {
      if (e.message != 'SESSION_EXPIRED' || credentialsProvider == null) {
        rethrow;
      }
      final creds = await credentialsProvider!();
      if (creds == null) rethrow;
      try {
        await authenticate(
            db: creds.db, login: creds.login, password: creds.password);
      } catch (_) {
        throw OdooException('SESSION_EXPIRED');
      }
      final cookie = sessionCookie;
      if (cookie != null) await onSessionRefreshed?.call(cookie);
      return await _postCallKw(model, method, args, kwargs: kwargs);
    }
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
        'type',
        'is_storable',
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
    final now = DateTime.now();
    if (_posCatsCache != null &&
        now.difference(_posCatsCacheAt) < _catsTtl) {
      return _posCatsCache!;
    }
    final result =
        await callKw('pos.category', 'search_read', [], kwargs: {
      'domain': [],
      'fields': ['id', 'name'],
      'limit': 200,
      'order': 'name',
    });
    final cats = (result as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return PosCategory(
          id: (m['id'] as num).toInt(), name: (m['name'] ?? '').toString());
    }).toList();
    _posCatsCache = cats;
    _posCatsCacheAt = now;
    return cats;
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

  /// Internal product categories (for the unified category mapping).
  Future<List<PosCategory>> getProductCategories() async {
    final now = DateTime.now();
    if (_internalCatsCache != null &&
        now.difference(_internalCatsCacheAt) < _catsTtl) {
      return _internalCatsCache!;
    }
    final result =
        await callKw('product.category', 'search_read', [], kwargs: {
      'domain': [],
      'fields': ['id', 'name'],
      'limit': 200,
      'order': 'name',
    });
    final cats = (result as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return PosCategory(
          id: (m['id'] as num).toInt(), name: (m['name'] ?? '').toString());
    }).toList();
    _internalCatsCache = cats;
    _internalCatsCacheAt = now;
    return cats;
  }

  /// All variants matching a barcode/default_code (for the duplicate picker).
  Future<List<InventoryProduct>> findVariants(String code) async {
    final c = code.trim();
    if (c.isEmpty) return [];
    final result = await callKw('product.product', 'search_read', [], kwargs: {
      'domain': [
        '|',
        ['barcode', '=', c],
        ['default_code', '=', c],
      ],
      'fields': _productFields,
      'limit': 5,
    });
    return _toProducts(result);
  }

  /// Variants using [sku] as default_code (for the SKU collision check).
  Future<List<InventoryProduct>> findBySku(String sku) async {
    final s = sku.trim();
    if (s.isEmpty) return [];
    final result = await callKw('product.product', 'search_read', [], kwargs: {
      'domain': [
        ['default_code', '=', s]
      ],
      'fields': _productFields,
      'limit': 2,
    });
    return _toProducts(result);
  }

  static const List<String> _productFields = [
    'id',
    'product_tmpl_id',
    'name',
    'barcode',
    'default_code',
    'list_price',
    'standard_price',
    'pos_categ_ids',
    'qty_available',
    'type',
    'is_storable',
  ];

  static List<InventoryProduct> _toProducts(dynamic result) => (result as List)
      .map((e) =>
          InventoryProduct.fromMap((e as Map).cast<String, dynamic>()))
      .toList();

  /// Browse products for the Manage list: free-text search over
  /// name/barcode/SKU/internal-category/POS-category plus optional
  /// POS-category filter, paged.
  /// Returns at most [limit] rows; [more] is true when a full page came
  /// back (caller bumps [offset] for the next page).
  Future<({List<InventoryProduct> rows, bool more})> searchProducts({
    String query = '',
    int? posCategId,
    int limit = 50,
    int offset = 0,
  }) async {
    final q = query.trim();
    final domain = <dynamic>[];
    if (q.isNotEmpty) {
      // OR-chain over every searchable text field.
      final ors = [
        ['name', 'ilike', q],
        ['barcode', 'ilike', q],
        ['default_code', 'ilike', q],
        ['categ_id', 'ilike', q],
        ['pos_categ_ids', 'ilike', q],
      ];
      for (var i = 0; i < ors.length - 1; i++) {
        domain.add('|');
      }
      domain.addAll(ors);
    }
    if (posCategId != null) {
      if (domain.isNotEmpty) domain.insert(0, '&');
      domain.add([
        'pos_categ_ids',
        'in',
        [posCategId]
      ]);
    }
    final result = await callKw('product.product', 'search_read', [], kwargs: {
      'domain': domain,
      'fields': _productFields,
      'limit': limit,
      'offset': offset,
      'order': 'name',
    });
    final rows = _toProducts(result);
    return (rows: rows, more: rows.length >= limit);
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

  /// Update template name only when changed.
  Future<void> updateName(InventoryProduct p, String name) async {
    final n = name.trim();
    if (n.isEmpty || n == p.name) return;
    await callKw('product.template', 'write', [
      [p.tmplId],
      {'name': n},
    ]);
  }

  /// Update variant SKU (default_code) only when changed.
  Future<void> updateSku(InventoryProduct p, String sku) async {
    final s = sku.trim();
    if (s == p.defaultCode) return;
    await callKw('product.product', 'write', [
      [p.variantId],
      {'default_code': s.isEmpty ? false : s},
    ]);
  }

  /// Archive (deactivate) a product template: hides it from POS and scans.
  /// Reversible in Odoo via the Archived filter. Used to clean up
  /// duplicates / bad items from the app (with a confirm dialog).
  Future<void> archiveProduct(InventoryProduct p) async {
    await callKw('product.template', 'write', [
      [p.tmplId],
      {'active': false},
    ]);
  }

  /// Enable stock tracking on the template so it can hold quants.
  /// Odoo 18 gate is is_storable (type stays 'consu'). In-app recovery
  /// for pre-existing untracked products.
  Future<void> setStorable(InventoryProduct p) async {
    await callKw('product.template', 'write', [
      [p.tmplId],
      {'is_storable': true},
    ]);
  }

  Future<double> _writeQuant(InventoryProduct p, double target) async {
    final found = await callKw('stock.quant', 'search_read', [], kwargs: {
      'domain': [
        ['product_id', '=', p.variantId],
        ['location_id.usage', '=', 'internal'],
      ],
      'fields': ['id', 'quantity'],
      'limit': 1,
    });
    final rows = (found as List);
    if (rows.isNotEmpty) {
      final q = (rows.first as Map).cast<String, dynamic>();
      final id = (q['id'] as num).toInt();
      await callKw('stock.quant', 'write', [
        [id],
        {'inventory_quantity': target},
      ]);
      try {
        await callKw('stock.quant', 'action_apply_inventory', [
          [id]
        ]);
      } catch (_) {
        // 18 auto-applies on write in most configs; ignore.
      }
      return target;
    }
    final locId = await _stockLocationId();
    final created = await callKw('stock.quant', 'create', [
      {
        'product_id': p.variantId,
        'location_id': locId,
        'inventory_quantity': target,
      }
    ]);
    try {
      await callKw('stock.quant', 'action_apply_inventory', [
        [created]
      ]);
    } catch (_) {}
    return target;
  }

  /// Bump on-hand by [addQty]: inventory_quantity = current + addQty.
  Future<double> addStock(InventoryProduct p, double addQty) async {
    if (addQty == 0) return p.qtyAvailable;
    final found = await callKw('stock.quant', 'search_read', [], kwargs: {
      'domain': [
        ['product_id', '=', p.variantId],
        ['location_id.usage', '=', 'internal'],
      ],
      'fields': ['id', 'quantity'],
      'limit': 1,
    });
    final rows = (found as List);
    double current = p.qtyAvailable;
    if (rows.isNotEmpty) {
      final q = (rows.first as Map).cast<String, dynamic>();
      if (q['quantity'] is num) current = (q['quantity'] as num).toDouble();
    }
    return _writeQuant(p, current + addQty);
  }

  /// Set on-hand to [counted] (Count = mode): inventory_quantity = counted.
  Future<double> setStock(InventoryProduct p, double counted) {
    return _writeQuant(p, counted);
  }

  /// Create template + set variant barcode/SKU + set initial stock.
  /// Returns the variant id.
  Future<int> createProduct({
    required String name,
    required String barcode,
    required int posCategId,
    required double listPrice,
    required double standardPrice,
    required double qty,
    int? categId,
    String sku = '',
    bool saleOk = true,
    bool purchaseOk = true,
  }) async {
    final internalCateg = categId ?? await _defaultCategId();
    final tmplId = await callKw('product.template', 'create', [
      {
        'name': name,
        'list_price': listPrice,
        'standard_price': standardPrice,
        'categ_id': internalCateg,
        'pos_categ_ids': [
          [6, 0, [posCategId]]
        ],
        'sale_ok': saleOk,
        'purchase_ok': purchaseOk,
        'available_in_pos': saleOk,
        // Odoo 18: type stays 'consu'; stock tracking is the is_storable
        // flag (the quant gate). 'product' is not a valid type value.
        'type': 'consu',
        'is_storable': true,
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
      final variantVals = <String, dynamic>{};
      if (barcode.trim().isNotEmpty) variantVals['barcode'] = barcode.trim();
      if (sku.trim().isNotEmpty) variantVals['default_code'] = sku.trim();
      if (variantVals.isNotEmpty) {
        await callKw('product.product', 'write', [
          [vid],
          variantVals,
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
