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
      // Prod Odoo returns HTTP 200 + code 100 "Odoo Session Expired" for a
      // dead cookie (verified against admin.cloud9market.net) — NOT 401.
      // Normalize every session-expired shape to SESSION_EXPIRED so
      // [callKw] can transparently re-login + retry once.
      if (err is Map) {
        final code = err['code'];
        final msg = err['message']?.toString() ?? '';
        final data = err['data'];
        final dataName =
            data is Map ? (data['name']?.toString() ?? '') : '';
        final dataMsg =
            data is Map ? (data['message']?.toString() ?? '') : '';
        final expired = code == 100 ||
            msg.toLowerCase().contains('session expired') ||
            dataName.contains('SessionExpired') ||
            dataMsg.toLowerCase().contains('session expired');
        if (expired) throw OdooException('SESSION_EXPIRED');
      }
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

  /// Scrap location for waste/loss write-offs.
  /// NOTE (prod bug 2026-10-24): this Odoo DB has NO `scrap_location`
  /// field on `stock.location` — querying it throws
  /// "invalid field stock.location.scrap_location in condition".
  /// So resolve purely by usage + name, each step guarded so one bad
  /// domain can never sink the whole chain.
  Future<int> scrapLocationId() async {
    // 1. Inventory-usage location named like Scrap.
    try {
      final named =
          await callKw('stock.location', 'search_read', [], kwargs: {
        'domain': [
          ['usage', '=', 'inventory'],
          ['name', 'ilike', 'scrap'],
        ],
        'fields': ['id'],
        'limit': 1,
      });
      if ((named as List).isNotEmpty) {
        return (((named).first as Map)['id'] as num).toInt();
      }
    } catch (_) {
      // Fall through to the next strategy.
    }
    // 2. Any inventory-usage location (virtual/scrap live here).
    try {
      final anyInv =
          await callKw('stock.location', 'search_read', [], kwargs: {
        'domain': [
          ['usage', '=', 'inventory']
        ],
        'fields': ['id'],
        'limit': 1,
      });
      if ((anyInv as List).isNotEmpty) {
        return (((anyInv).first as Map)['id'] as num).toInt();
      }
    } catch (_) {
      // Fall through.
    }
    // 3. Last resort: the regular internal stock location.
    return _stockLocationId();
  }

  /// Lots for a storable product (for expiry-aware waste logging).
  Future<List<StockLot>> findLots(int variantId, {int limit = 20}) async {
    final result = await callKw('stock.lot', 'search_read', [], kwargs: {
      'domain': [
        ['product_id', '=', variantId]
      ],
      'fields': ['id', 'name', 'expiration_date'],
      'limit': limit,
      'order': 'expiration_date',
    });
    return (result as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      Object? exp = m['expiration_date'];
      return StockLot(
        id: (m['id'] as num).toInt(),
        name: m['name']?.toString() ?? '',
        expirationDate:
            (exp == null || exp is bool) ? '' : exp.toString(),
      );
    }).toList();
  }

  /// Create + validate a scrap move for a waste/loss line.
  /// Returns the scrap id and the frozen unit value Odoo applied.
  /// Throws OdooException on failure (caller keeps an offline draft).
  Future<ScrapResult> createScrap({
    required InventoryProduct product,
    required double qty,
    int? lotId,
    String origin = '',
  }) async {
    final q = qty;
    if (q <= 0) throw OdooException('Scrap qty must be > 0');
    final srcId = await _stockLocationId();
    final dstId = await scrapLocationId();
    final vals = <String, dynamic>{
      'product_id': product.variantId,
      'scrap_qty': q,
      'location_id': srcId,
      'scrap_location_id': dstId,
      if (origin.trim().isNotEmpty) 'origin': origin.trim(),
    };
    if (lotId != null) vals['lot_id'] = lotId;
    int scrapRecordId;
    try {
      scrapRecordId = await callKw('stock.scrap', 'create', [vals]) as int;
    } catch (e) {
      throw OdooException('Scrap not available in Odoo: $e');
    }
    try {
      await callKw('stock.scrap', 'action_validate', [
        [scrapRecordId]
      ]);
    } catch (_) {
      // Some configs auto-validate on create; ignore.
    }
    double unitValue = product.standardPrice;
    try {
      final read = await callKw('stock.scrap', 'read', [
        [scrapRecordId],
        ['value', 'scrap_qty'],
      ]) as List;
      if (read.isNotEmpty) {
        final m = (read.first as Map).cast<String, dynamic>();
        final v = m['value'];
        final sq = m['scrap_qty'];
        if (v is num && sq is num && sq != 0) {
          unitValue = (v / sq).toDouble();
        }
      }
    } catch (_) {
      // Keep standard_price fallback.
    }
    return ScrapResult(scrapId: scrapRecordId, unitValue: unitValue);
  }

  /// Attach a base64 photo to a validated scrap record (best-effort).
  Future<void> attachScrapPhoto({
    required int scrapId,
    required String base64Image,
    String filename = 'waste.jpg',
  }) async {
    await callKw('ir.attachment', 'create', [
      {
        'name': filename,
        'res_model': 'stock.scrap',
        'res_id': scrapId,
        'type': 'binary',
        'datas': base64Image,
        'mimetype': 'image/jpeg',
      }
    ]);
  }

  /// ---- Attendance (hr.attendance, no custom Odoo module) ----
  ///
  /// Graceful when the Attendance app isn't installed: every method throws
  /// OdooException('ATTENDANCE_UNAVAILABLE') and the UI shows setup help.

  /// Employee linked to the current Odoo user (hr.employee.user_id).
  Future<AttendanceEmployee> myEmployee() async {
    dynamic result;
    try {
      result = await callKw('hr.employee', 'search_read', [], kwargs: {
        'domain': [
          ['user_id', '=', await _currentUid()],
        ],
        'fields': ['id', 'name'],
        'limit': 1,
      });
    } catch (e) {
      throw OdooException(_attendanceUnavailable(e));
    }
    final rows = (result as List);
    if (rows.isEmpty) throw OdooException('ATTENDANCE_NO_EMPLOYEE');
    final m = (rows.first as Map).cast<String, dynamic>();
    return AttendanceEmployee(
      id: (m['id'] as num).toInt(),
      name: (m['name'] ?? '').toString(),
    );
  }

  Future<int> _currentUid() async {
    if (debugUid != null) return debugUid!;
    // Standard Odoo session info carries the uid; no extra storage needed.
    try {
      final r = await _http.post(
        Uri.parse('$_base/web/session/get_session_info'),
        headers: _headers,
        body: jsonEncode({'jsonrpc': '2.0', 'params': {}}),
      );
      final body = _decode(r);
      final result = body['result'];
      if (result is Map && result['uid'] is num) {
        return (result['uid'] as num).toInt();
      }
    } catch (_) {}
    return 0;
  }

  // Test hook for the uid (production reads it from the live session).
  int? debugUid;

  /// Open attendance (check_out == False), if any.
  Future<AttendanceRecord?> openAttendance(int employeeId) async {
    dynamic result;
    try {
      result = await callKw('hr.attendance', 'search_read', [], kwargs: {
        'domain': [
          ['employee_id', '=', employeeId],
          ['check_out', '=', false],
        ],
        'fields': ['id', 'check_in', 'check_out'],
        'limit': 1,
        'order': 'check_in desc',
      });
    } catch (e) {
      throw OdooException(_attendanceUnavailable(e));
    }
    final rows = (result as List);
    if (rows.isEmpty) return null;
    return AttendanceRecord.fromMap(
        (rows.first as Map).cast<String, dynamic>());
  }

  static String _odooTs(DateTime d) {
    final u = d.toUtc();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${u.year}-${p(u.month)}-${p(u.day)} ${p(u.hour)}:${p(u.minute)}:${p(u.second)}';
  }

  /// Clock in: creates hr.attendance with check_in = now (UTC).
  Future<AttendanceRecord> clockIn(int employeeId, {DateTime? at}) async {
    final ts = _odooTs(at ?? DateTime.now());
    dynamic id;
    try {
      id = await callKw('hr.attendance', 'create', [
        {'employee_id': employeeId, 'check_in': ts}
      ]);
    } catch (e) {
      throw OdooException(_attendanceUnavailable(e));
    }
    return AttendanceRecord(
        id: (id as num).toInt(), checkIn: ts, checkOut: '');
  }

  /// Clock out: writes check_out = now on the open record.
  Future<void> clockOut(int attendanceId, {DateTime? at}) async {
    try {
      await callKw('hr.attendance', 'write', [
        [attendanceId],
        {'check_out': _odooTs(at ?? DateTime.now())},
      ]);
    } catch (e) {
      throw OdooException(_attendanceUnavailable(e));
    }
  }

  /// Recent attendances for hours + history UI.
  Future<List<AttendanceRecord>> attendanceHistory(int employeeId,
      {int limit = 30}) async {
    dynamic result;
    try {
      result = await callKw('hr.attendance', 'search_read', [], kwargs: {
        'domain': [
          ['employee_id', '=', employeeId]
        ],
        'fields': ['id', 'check_in', 'check_out'],
        'limit': limit,
        'order': 'check_in desc',
      });
    } catch (e) {
      throw OdooException(_attendanceUnavailable(e));
    }
    return (result as List)
        .map((e) => AttendanceRecord.fromMap(
            (e as Map).cast<String, dynamic>()))
        .toList();
  }

  String _attendanceUnavailable(Object e) {
    final m = e.toString();
    if (m.contains('ATTENDANCE_NO_EMPLOYEE')) return 'ATTENDANCE_NO_EMPLOYEE';
    // Missing model / access rights all surface as unavailable with detail.
    return 'ATTENDANCE_UNAVAILABLE: $m';
  }

  /// ---- Native POS checkout (no WebView, no second login) ----
  ///
  /// Flow: open session -> sellable products -> cart -> tender ->
  /// pos.order + pos.payment -> action_pos_order_paid.
  /// Every step throws a descriptive OdooException on failure.

  /// Active POS configs (registers) to sell into.
  Future<List<PosShop>> posConfigs() async {
    dynamic result;
    try {
      result = await callKw('pos.config', 'search_read', [], kwargs: {
        'domain': [
          ['active', '=', true]
        ],
        'fields': ['id', 'name'],
        'order': 'name',
      });
    } catch (e) {
      throw OdooException(_posUnavailable(e));
    }
    return (result as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return PosShop(
          id: (m['id'] as num).toInt(), name: (m['name'] ?? '').toString());
    }).toList();
  }

  /// Open session for a config, newest first. Null = register closed.
  Future<PosSession?> openPosSession(int configId) async {
    dynamic result;
    try {
      result = await callKw('pos.session', 'search_read', [], kwargs: {
        'domain': [
          ['config_id', '=', configId],
          ['state', 'in', ['opened', 'opening_control']],
        ],
        'fields': ['id', 'name', 'state', 'config_id'],
        'limit': 1,
        'order': 'id desc',
      });
    } catch (e) {
      throw OdooException(_posUnavailable(e));
    }
    final rows = (result as List);
    if (rows.isEmpty) return null;
    final m = (rows.first as Map).cast<String, dynamic>();
    final cfg = m['config_id'];
    return PosSession(
      id: (m['id'] as num).toInt(),
      name: (m['name'] ?? '').toString(),
      configId: cfg is List && cfg.isNotEmpty
          ? (cfg[0] as num).toInt()
          : configId,
      state: (m['state'] ?? '').toString(),
    );
  }

  /// Sellable products for checkout: name/barcode search, POS-sellable.
  Future<List<PosProduct>> posProducts(String query, {int limit = 20}) async {
    final q = query.trim();
    dynamic result;
    try {
      final domain = <dynamic>[
        ['sale_ok', '=', true],
      ];
      if (q.isNotEmpty) {
        domain.add('|');
        domain.add(['name', 'ilike', q]);
        domain.add(['barcode', 'ilike', q]);
      }
      result = await callKw('product.product', 'search_read', [], kwargs: {
        'domain': domain,
        'fields': [
          'id',
          'name',
          'barcode',
          'list_price',
          'taxes_id',
          'qty_available'
        ],
        'limit': limit,
        'order': 'name',
      });
    } catch (e) {
      throw OdooException(_posUnavailable(e));
    }
    return (result as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      final taxes = m['taxes_id'];
      return PosProduct(
        id: (m['id'] as num).toInt(),
        name: (m['name'] ?? '').toString(),
        barcode: InventoryProduct._s(m['barcode']),
        listPrice: InventoryProduct._d(m['list_price']),
        taxIds: taxes is List
            ? taxes.map((t) => (t as num).toInt()).toList()
            : const [],
        onHand: InventoryProduct._d(m['qty_available']),
      );
    }).toList();
  }

  /// Tax rates for price math (unknown taxes count as 0% — server total
  /// stays authoritative on the receipt).
  Future<Map<int, PosTax>> posTaxes(List<int> ids) async {
    final out = <int, PosTax>{};
    final clean = ids.toSet().toList();
    if (clean.isEmpty) return out;
    try {
      final result =
          await callKw('account.tax', 'search_read', [], kwargs: {
        'domain': [
          ['id', 'in', clean]
        ],
        'fields': ['id', 'amount', 'price_include'],
      });
      for (final e in (result as List)) {
        final m = (e as Map).cast<String, dynamic>();
        final id = (m['id'] as num).toInt();
        out[id] = PosTax(
          id: id,
          amount: m['amount'] is num ? (m['amount'] as num).toDouble() : 0,
          priceInclude: m['price_include'] == true,
        );
      }
    } catch (_) {
      // Ignore — treated as 0%.
    }
    return out;
  }

  /// Payment methods (cash, card...). Tolerates field differences.
  /// `terminal` names the integrated terminal (e.g. helcim/stripe/adyen)
  /// or '' when the method records payment directly.
  Future<List<PosPayMethod>> posPaymentMethods() async {
    dynamic result;
    try {
      try {
        result = await callKw('pos.payment.method', 'search_read', [],
            kwargs: {
              'domain': [
                ['active', '=', true]
              ],
              'fields': [
                'id',
                'name',
                'is_cash_count',
                'type',
                'use_payment_terminal'
              ],
              'order': 'name',
            });
      } catch (_) {
        result = await callKw('pos.payment.method', 'search_read', [],
            kwargs: {
              'domain': [],
              'fields': ['id', 'name'],
              'order': 'name',
            });
      }
    } catch (e) {
      throw OdooException(_posUnavailable(e));
    }
    return (result as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      final type = (m['type'] ?? '').toString();
      final cash = m['is_cash_count'] == true || type == 'cash';
      final term = m['use_payment_terminal'];
      final terminal =
          (term == null || term is bool || term == 'none' || term == false)
              ? ''
              : term.toString();
      return PosPayMethod(
        id: (m['id'] as num).toInt(),
        name: (m['name'] ?? '').toString(),
        isCash: cash,
        terminal: terminal,
      );
    }).toList();
  }

  /// Full native sale via the frontend's own sync endpoint
  /// (`pos.order/sync_from_ui` on Odoo 18 — `create_from_ui` is gone).
  /// Same UI-shaped dict web POS syncs daily, so custom required fields
  /// (e.g. a required `amount_tax`) are satisfied like prod. The order is
  /// found afterwards by its uuid (sync answers with display data, not
  /// ids). Single call per attempt; a retry uses a fresh uuid so it can
  /// never double-charge. Throws with a clear message at the failing step;
  /// a draft order left behind can always be paid/voided at the register.
  Future<PosReceipt> posCheckout({
    required int sessionId,
    required List<PosCartLine> lines,
    required List<PosTender> tenders,
    double? amountTax,
    bool draft = false,
  }) async {
    if (lines.isEmpty) throw OdooException('Cart is empty.');
    final tendered = tenders.fold(0.0, (a, t) => a + t.amount);
    if (tendered <= 0) throw OdooException('Enter a payment amount.');
    // Local estimate (server recomputes authoritatively).
    double tax = amountTax ?? 0;
    double untaxed = 0;
    for (final l in lines) {
      untaxed += l.qty * l.priceUnit;
    }
    final total = untaxed + tax;
    if (amountTax == null) {
      // No tax table handy — still send a complete dict; server computes.
      tax = 0;
    }
    final change = tendered - total;
    final uuid = _newUuid();
    final now = _odooTs(DateTime.now());
    final orderDict = <String, dynamic>{
      'name': 'Mobile/${DateTime.now().millisecondsSinceEpoch}',
      'uuid': uuid,
      'session_id': sessionId,
      'partner_id': false,
      'to_invoice': false,
      'state': draft ? 'draft' : 'paid',
      'amount_total': _round2(total),
      'amount_tax': _round2(tax),
      'amount_paid': _round2(tendered),
      'amount_return': _round2(change < 0 ? 0 : change),
      'lines': [
        for (final l in lines)
          [
            0,
            0,
            {
              'uuid': _newUuid(),
              'product_id': l.productId,
              'qty': l.qty,
              'price_unit': l.priceUnit,
              'discount': 0,
              'tax_ids': [
                [6, 0, l.taxIds]
              ],
              'price_subtotal': _round2(l.qty * l.priceUnit),
              'price_subtotal_incl':
                  _round2(l.qty * l.priceUnit + _lineTax(l, tax, untaxed)),
            }
          ],
      ],
      'payment_ids': [
        for (final t in tenders)
          [
            0,
            0,
            {
              'uuid': _newUuid(),
              'amount': t.amount,
              'payment_method_id': t.methodId,
              'name': 'Mobile/${t.methodId}',
              'payment_date': now,
            }
          ],
      ],
    };
    try {
      // Odoo 18: sync_from_ui([orders]) — no draft arg (per-order 'state'
      // key instead). Answers with display data, not ids.
      await callKw('pos.order', 'sync_from_ui', [
        [orderDict],
      ]);
    } catch (e) {
      throw OdooException('Could not create the sale: ${_full(e)}');
    }
    // Find our order by its unique uuid (server dedupes on it — exact).
    int? orderId;
    String ref = '';
    double serverTotal = total;
    String state = '';
    try {
      final found = await callKw('pos.order', 'search_read', [], kwargs: {
        'domain': [
          ['uuid', '=', uuid]
        ],
        'fields': ['id', 'pos_reference', 'amount_total', 'state', 'name'],
        'limit': 1,
      }) as List;
      if (found.isNotEmpty) {
        final m = (found.first as Map).cast<String, dynamic>();
        orderId = (m['id'] as num).toInt();
        ref = (m['pos_reference'] ?? m['name'] ?? '#$orderId').toString();
        if (m['amount_total'] is num) {
          serverTotal = (m['amount_total'] as num).toDouble();
        }
        state = (m['state'] ?? '').toString();
      }
    } catch (_) {}
    if (orderId == null) {
      throw OdooException(
          'Sale not confirmed on server (order missing after sync). Check the register before retrying — do NOT rescan to avoid a duplicate.');
    }
    if (!draft && state.isNotEmpty && state != 'paid') {
      try {
        await callKw('pos.order', 'action_pos_order_paid', [
          [orderId]
        ]);
      } catch (e) {
        throw OdooException(
            'Order $ref saved as DRAFT (pay it at the register). Validate failed: ${_short(e)}');
      }
    }
    return PosReceipt(
        orderId: orderId,
        reference: ref,
        total: serverTotal,
        tendered: tendered,
        change: tendered - serverTotal);
  }

  String _posUnavailable(Object e) {
    final m = e.toString();
    return 'POS_UNAVAILABLE: $m';
  }

  /// Read-only probe: what on THIS Odoo can drive a payment terminal?
  /// Lists models mentioning helcim/terminal/pos payment, their fields,
  /// and terminal-configured payment methods. Nothing is created or
  /// written. The report is copyable from the POS setup screen so the
  /// exact server hook can be wired without guessing.
  Future<TerminalProbe> probeTerminalSupport() async {
    final models = <ProbeModel>[];
    final notes = <String>[];
    // 1. Custom/standard models mentioning helcim or terminal.
    try {
      final result =
          await callKw('ir.model', 'search_read', [], kwargs: {
        'domain': [
          '|',
          ['model', 'ilike', 'helcim'],
          '|',
          ['model', 'ilike', 'terminal'],
          ['name', 'ilike', 'terminal'],
        ],
        'fields': ['name', 'model'],
        'limit': 30,
      });
      for (final e in (result as List)) {
        final m = (e as Map).cast<String, dynamic>();
        final modelName = (m['model'] ?? '').toString();
        if (modelName.isEmpty) continue;
        var fields = <String>[];
        try {
          final fr = await callKw('ir.model.fields', 'search_read', [],
              kwargs: {
                'domain': [
                  ['model', '=', modelName]
                ],
                'fields': ['name', 'ttype', 'required'],
                'limit': 100,
              });
          fields = (fr as List).map((f) {
            final fm = (f as Map).cast<String, dynamic>();
            final req = fm['required'] == true ? ' *req' : '';
            return '${fm['name']}(${(fm['ttype'] ?? '').toString()}$req)';
          }).toList();
        } catch (_) {
          fields = ['<fields unreadable>'];
        }
        models.add(ProbeModel(
            name: (m['name'] ?? '').toString(),
            model: modelName,
            fields: fields));
      }
    } catch (e) {
      notes.add('ir.model unreadable: ${_short(e)}');
    }
    // 2. Payment methods with a terminal integration configured.
    final terminals = <String>[];
    try {
      final methods = await posPaymentMethods();
      for (final pm in methods) {
        if (pm.isTerminal) terminals.add('${pm.name} [${pm.terminal}]');
      }
      if (terminals.isEmpty) {
        notes.add(
            'No payment method has a terminal integration (use_payment_terminal empty).');
      }
    } catch (e) {
      notes.add('payment methods unreadable: ${_short(e)}');
    }
    return TerminalProbe(models: models, terminalMethods: terminals, notes: notes);
  }

  double _round2(double v) => (v * 100).round() / 100.0;

  /// Pro-rata share of the order tax for one line (local estimate only).
  double _lineTax(PosCartLine l, double orderTax, double orderUntaxed) {
    if (orderTax <= 0 || orderUntaxed <= 0) return 0;
    return orderTax * (l.qty * l.priceUnit) / orderUntaxed;
  }

  /// uuid v4-ish without a new dependency (unique per attempt — the
  /// server dedupes on it, so a retry never double-charges).
  String _newUuid() {
    final r = DateTime.now().microsecondsSinceEpoch;
    final h = r.toRadixString(16).padLeft(12, '0');
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${(r % 4096).toRadixString(16).padLeft(3, '0')}-8${(r % 4096).toRadixString(16).padLeft(3, '0')}-${h.padLeft(12, '0')}';
  }

  String _short(Object e) {
    final m = e is OdooException ? e.message : e.toString();
    return m.length > 220 ? '${m.substring(0, 220)}…' : m;
  }

  /// Full server message (for the copyable error dialog — nothing hidden).
  String _full(Object e) => e is OdooException ? e.message : e.toString();
}

/// A model found by the terminal probe.
class ProbeModel {
  final String name;
  final String model;
  final List<String> fields;
  const ProbeModel(
      {required this.name, required this.model, this.fields = const []});
}

/// Read-only report of what on this Odoo can drive a payment terminal.
class TerminalProbe {
  final List<ProbeModel> models;
  final List<String> terminalMethods;
  final List<String> notes;
  const TerminalProbe(
      {this.models = const [],
      this.terminalMethods = const [],
      this.notes = const []});

  /// Copyable plain-text report for the setup screen.
  String report() {
    final sb = StringBuffer('ODOO TERMINAL PROBE\n');
    sb.writeln('payment methods with terminal: '
        '${terminalMethods.isEmpty ? 'NONE' : terminalMethods.join(', ')}');
    if (models.isEmpty) {
      sb.writeln('models mentioning helcim/terminal: NONE');
    } else {
      for (final m in models) {
        sb.writeln('model ${m.model} (${m.name})');
        for (final f in m.fields) {
          sb.writeln('  - $f');
        }
      }
    }
    for (final n in notes) {
      sb.writeln('note: $n');
    }
    return sb.toString();
  }
}

/// Employee linked to the logged-in Odoo user.
class AttendanceEmployee {
  final int id;
  final String name;
  const AttendanceEmployee({required this.id, required this.name});
}

/// One hr.attendance row. Odoo timestamps are 'yyyy-MM-dd HH:mm:ss' UTC.
class AttendanceRecord {
  final int id;
  final String checkIn;
  final String checkOut; // '' = still open
  const AttendanceRecord(
      {required this.id, required this.checkIn, required this.checkOut});

  bool get isOpen => checkOut.isEmpty || checkOut == 'false';

  factory AttendanceRecord.fromMap(Map<String, dynamic> m) {
    Object? out = m['check_out'];
    return AttendanceRecord(
      id: (m['id'] as num).toInt(),
      checkIn: (m['check_in'] ?? '').toString(),
      checkOut: (out == null || out is bool) ? '' : out.toString(),
    );
  }

  static DateTime? _parse(String s) {
    if (s.isEmpty || s == 'false') return null;
    try {
      // Odoo returns naive UTC wall times ('yyyy-MM-dd HH:mm:ss').
      // Parse as UTC explicitly — parsing as local would skew hours
      // by the device UTC offset.
      var t = s.replaceFirst(' ', 'T');
      if (!t.endsWith('Z') &&
          !RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(t)) {
        t = '${t}Z';
      }
      return DateTime.parse(t).toUtc();
    } catch (_) {
      return null;
    }
  }

  /// Public parse of Odoo 'yyyy-MM-dd HH:mm:ss' UTC timestamps.
  static DateTime? tryParseTs(String s) => _parse(s);

  /// Worked hours for this record (open record counts up to [now]).
  double hours({DateTime? now}) {
    final inn = _parse(checkIn);
    if (inn == null) return 0;
    final out = _parse(checkOut) ?? (now ?? DateTime.now()).toUtc();
    final h = out.difference(inn).inMinutes / 60.0;
    return h < 0 ? 0 : h;
  }
}

/// Minimal lot view for waste logging.
class StockLot {
  final int id;
  final String name;
  final String expirationDate;
  const StockLot(
      {required this.id, required this.name, required this.expirationDate});
}

/// Result of a validated scrap write: server id + frozen unit value.
class ScrapResult {
  final int scrapId;
  final double unitValue;
  const ScrapResult({required this.scrapId, required this.unitValue});
}

/// Read-only server scrap line for the history/report view.
class ScrapHistoryLine {
  final int id;
  final String productName;
  final double qty;
  final String dateDone;
  final String state;
  final String origin;
  const ScrapHistoryLine({
    required this.id,
    required this.productName,
    required this.qty,
    required this.dateDone,
    required this.state,
    required this.origin,
  });
}

/// ---- Native POS models (pure cart/tax math lives in PosCart) ----

/// A register (pos.config).
class PosShop {
  final int id;
  final String name;
  const PosShop({required this.id, required this.name});
}

/// An open register session (pos.session).
class PosSession {
  final int id;
  final String name;
  final int configId;
  final String state;
  const PosSession(
      {required this.id,
      required this.name,
      required this.configId,
      required this.state});
}

/// A sellable product for checkout.
class PosProduct {
  final int id;
  final String name;
  final String barcode;
  final double listPrice;
  final List<int> taxIds;
  final double onHand;
  const PosProduct({
    required this.id,
    required this.name,
    required this.barcode,
    required this.listPrice,
    this.taxIds = const [],
    this.onHand = 0,
  });
}

/// A sales tax (account.tax) for local total estimates.
class PosTax {
  final int id;
  final double amount; // percent, e.g. 6.625
  final bool priceInclude;
  const PosTax(
      {required this.id, required this.amount, this.priceInclude = true});
}

/// One line the cashier sends to the server.
class PosCartLine {
  final int productId;
  final double qty;
  final double priceUnit;
  final List<int> taxIds;
  const PosCartLine(
      {required this.productId,
      required this.qty,
      required this.priceUnit,
      this.taxIds = const []});
}

/// One tender the cashier sends to the server.
class PosTender {
  final int methodId;
  final double amount;
  const PosTender({required this.methodId, required this.amount});
}

/// Payment method (pos.payment.method).
class PosPayMethod {
  final int id;
  final String name;
  final bool isCash;

  /// Integrated terminal (e.g. 'helcim') or '' for direct methods.
  final String terminal;
  const PosPayMethod(
      {required this.id,
      required this.name,
      this.isCash = false,
      this.terminal = ''});

  bool get isTerminal => terminal.isNotEmpty;
}

/// Server receipt after a paid sale.
class PosReceipt {
  final int orderId;
  final String reference;
  final double total;
  final double tendered;
  final double change;
  const PosReceipt(
      {required this.orderId,
      required this.reference,
      required this.total,
      required this.tendered,
      required this.change});
}

/// Pure cart math for the checkout screen. Whitebox-tested: given lines +
/// tax rates, estimate subtotal / tax / total exactly like the UI shows.
/// Server totals stay authoritative on the receipt.
class PosCart {
  /// Per-line total at register price (before tax extraction).
  static double lineTotal(double priceUnit, double qty) => priceUnit * qty;

  /// Tax portion of a tax-INCLUDED line total at [ratePct].
  static double includedTax(double lineTotal, double ratePct) {
    if (ratePct <= 0) return 0;
    final r = ratePct / 100.0;
    return lineTotal - lineTotal / (1 + r);
  }

  /// Added tax for a tax-EXCLUDED line total at [ratePct].
  static double excludedTax(double lineTotal, double ratePct) =>
      ratePct <= 0 ? 0 : lineTotal * ratePct / 100.0;

  /// Combined rate for a product from its taxes (unknown ids count 0%).
  /// If ANY tax is price-included, the register price counts as included.
  static ({double rate, bool included}) combineRate(
      List<int> taxIds, Map<int, PosTax> taxes) {
    var rate = 0.0;
    var included = false;
    for (final id in taxIds) {
      final t = taxes[id];
      if (t == null) continue;
      rate += t.amount;
      if (t.priceInclude) included = true;
    }
    return (rate: rate, included: included);
  }

  /// Cart totals from lines + tax table.
  static ({double subtotal, double tax, double total}) totals(
      List<({double price, double qty, List<int> taxIds})> lines,
      Map<int, PosTax> taxes) {
    var subtotal = 0.0;
    var tax = 0.0;
    for (final l in lines) {
      final lt = lineTotal(l.price, l.qty);
      subtotal += lt;
      final c = combineRate(l.taxIds, taxes);
      tax += c.included ? includedTax(lt, c.rate) : excludedTax(lt, c.rate);
    }
    final total = subtotal +
        lines.fold(0.0, (a, l) {
          final lt = lineTotal(l.price, l.qty);
          final c = combineRate(l.taxIds, taxes);
          return a + (c.included ? 0 : excludedTax(lt, c.rate));
        });
    return (subtotal: subtotal, tax: tax, total: total);
  }
}

extension ScrapHistory on OdooClient {
  /// Recent scraps across all products/devices (server truth).
  /// Used to back the Waste history when the local log is empty
  /// (reinstall, second device) or to cross-check it.
  Future<List<ScrapHistoryLine>> fetchScrapHistory({int limit = 100}) async {
    final result = await callKw('stock.scrap', 'search_read', [], kwargs: {
      'domain': [],
      'fields': ['id', 'product_id', 'scrap_qty', 'state', 'date_done', 'origin'],
      'limit': limit,
      'order': 'id desc',
    });
    return (result as List).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      final prod = m['product_id'];
      final name = prod is List && prod.length > 1
          ? prod[1].toString()
          : prod.toString();
      final q = m['scrap_qty'];
      final dd = m['date_done'];
      return ScrapHistoryLine(
        id: (m['id'] as num).toInt(),
        productName: name,
        qty: q is num ? q.toDouble() : 0,
        dateDone: (dd == null || dd is bool) ? '' : dd.toString(),
        state: (m['state'] ?? '').toString(),
        origin: (m['origin'] ?? '').toString(),
      );
    }).toList();
  }
}
