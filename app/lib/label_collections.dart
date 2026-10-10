// Multiple named label collections with one active collection.
// Local persistence now (SharedPreferences JSON); schema carries
// serverBatchId + idempotencyKey so a future Odoo POST /label-batches
// needs no remodel. Lines carry a display size parsed from the name.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'print/label_model.dart';

/// Payload returned by the labels picker (browse) for one chosen item.
/// Mapped at pick time (category + size resolved there); the
/// collections tab never touches Odoo types.
typedef PickedLabel = ({
  String barcode,
  String name,
  double price,
  String size,
  String defaultCode,
  String category,
  int? variantId,
});

/// Result popped by the labels picker (browse in pick mode).
typedef PickResult = ({List<PickedLabel> items, bool printNow});

class CollectionLine {
  final String barcode;
  final String name;
  final String size;
  final double price;
  final String defaultCode;
  final String category;
  final int? variantId;
  int copies;
  final DateTime addedAt;

  /// Wireframe template + promo payload. Nullable/absent in old JSON
  /// loads as standard (tolerant fromJson below).
  LabelKind kind;
  double? wasPrice;
  String promoEnds;
  String saveText;

  CollectionLine({
    required this.barcode,
    required this.name,
    this.size = '',
    required this.price,
    this.defaultCode = '',
    this.category = '',
    this.variantId,
    this.copies = 1,
    DateTime? addedAt,
    this.kind = LabelKind.standard,
    this.wasPrice,
    this.promoEnds = '',
    this.saveText = '',
  }) : addedAt = addedAt ?? DateTime.now();

  LabelModel get model => LabelModel(
    name: name,
    size: size,
    price: price,
    barcode: barcode,
    defaultCode: defaultCode,
    category: category,
    copies: copies,
    kind: kind,
    wasPrice: wasPrice,
    promoEnds: promoEnds,
    saveText: saveText,
  );

  Map<String, dynamic> toJson() => {
    'barcode': barcode,
    'name': name,
    'size': size,
    'price': price,
    'defaultCode': defaultCode,
    'category': category,
    'variantId': variantId,
    'copies': copies,
    'addedAt': addedAt.toIso8601String(),
    'kind': kind.name,
    'wasPrice': wasPrice,
    'promoEnds': promoEnds,
    'saveText': saveText,
  };

  static LabelKind _kindOf(dynamic v) {
    for (final k in LabelKind.values) {
      if (k.name == v) return k;
    }
    return LabelKind.standard;
  }

  static CollectionLine fromJson(Map<String, dynamic> m) => CollectionLine(
    barcode: (m['barcode'] ?? '').toString(),
    name: (m['name'] ?? '').toString(),
    size: (m['size'] ?? '').toString(),
    price: (m['price'] is num) ? (m['price'] as num).toDouble() : 0,
    defaultCode: (m['defaultCode'] ?? '').toString(),
    category: (m['category'] ?? '').toString(),
    variantId: m['variantId'] is num ? (m['variantId'] as num).toInt() : null,
    copies: (m['copies'] is num)
        ? (m['copies'] as num).toInt().clamp(1, 999)
        : 1,
    addedAt:
        DateTime.tryParse((m['addedAt'] ?? '').toString()) ?? DateTime.now(),
    kind: _kindOf(m['kind']),
    wasPrice: (m['wasPrice'] is num)
        ? (m['wasPrice'] as num).toDouble()
        : null,
    promoEnds: (m['promoEnds'] ?? '').toString(),
    saveText: (m['saveText'] ?? '').toString(),
  );
}

class LabelCollection {
  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  final String idempotencyKey;
  String? serverBatchId;
  final List<CollectionLine> lines;

  LabelCollection({
    required this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? idempotencyKey,
    this.serverBatchId,
    List<CollectionLine>? lines,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       idempotencyKey = idempotencyKey ?? _newKey(),
       lines = lines ?? [];

  int get totalCopies => lines.fold(0, (a, l) => a + l.copies);

  void touch() => updatedAt = DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'idempotencyKey': idempotencyKey,
    'serverBatchId': serverBatchId,
    'lines': lines.map((l) => l.toJson()).toList(),
  };

  static LabelCollection fromJson(Map<String, dynamic> m) => LabelCollection(
    id: (m['id'] ?? _newKey()).toString(),
    name: ((m['name'] ?? 'Batch') as String).isEmpty
        ? 'Batch'
        : (m['name'] as String),
    createdAt: DateTime.tryParse((m['createdAt'] ?? '').toString()),
    updatedAt: DateTime.tryParse((m['updatedAt'] ?? '').toString()),
    idempotencyKey: (m['idempotencyKey'] ?? _newKey()).toString(),
    serverBatchId: m['serverBatchId']?.toString(),
    lines: ((m['lines'] as List?) ?? const [])
        .map((e) => CollectionLine.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );

  static String _newKey() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
  static int _counter = 0;
}

class LabelCollections extends ChangeNotifier {
  LabelCollections._();
  static final LabelCollections instance = LabelCollections._();

  final List<LabelCollection> _collections = [];
  String? _activeId;
  bool _loaded = false;

  List<LabelCollection> get collections => List.unmodifiable(_collections);
  bool get isLoaded => _loaded;

  LabelCollection? get active {
    if (_collections.isEmpty) return null;
    for (final c in _collections) {
      if (c.id == _activeId) return c;
    }
    return _collections.first;
  }

  List<CollectionLine> get activeLines =>
      List.unmodifiable(active?.lines ?? const []);

  int get activeTotalCopies => active?.totalCopies ?? 0;

  /// Line key: barcode || defaultCode || name (barcode-less never merge).
  static String keyOf({
    required String barcode,
    required String defaultCode,
    required String name,
  }) {
    if (barcode.trim().isNotEmpty) return 'b:${barcode.trim()}';
    if (defaultCode.trim().isNotEmpty) return 's:${defaultCode.trim()}';
    return 'n:${name.trim().toLowerCase()}';
  }

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';
  static int _idCounter = 0;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kCollections);
      _activeId = p.getString(_kActive);
      _collections.clear();
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final m in list) {
          try {
            _collections.add(LabelCollection.fromJson(m));
          } catch (_) {}
        }
      }
      if (_collections.isEmpty) {
        _collections.add(LabelCollection(id: _newId(), name: 'Batch 1'));
      }
      if (_activeId == null || !_collections.any((c) => c.id == _activeId)) {
        _activeId = _collections.first.id;
      }
    } catch (_) {
      if (_collections.isEmpty) {
        _collections.add(LabelCollection(id: _newId(), name: 'Batch 1'));
        _activeId = _collections.first.id;
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kCollections,
        jsonEncode(_collections.map((c) => c.toJson()).toList()),
      );
      if (_activeId != null) await p.setString(_kActive, _activeId!);
    } catch (_) {}
  }

  LabelCollection create([String? name]) {
    final n = (name ?? '').trim();
    final c = LabelCollection(
      id: _newId(),
      name: n.isEmpty ? 'Batch ${_collections.length + 1}' : n,
    );
    _collections.add(c);
    _activeId = c.id;
    c.touch();
    notifyListeners();
    _save();
    return c;
  }

  LabelCollection? byId(String id) {
    for (final c in _collections) {
      if (c.id == id) return c;
    }
    return null;
  }

  void setActive(String id) {
    if (!_collections.any((c) => c.id == id)) return;
    _activeId = id;
    notifyListeners();
    _save();
  }

  void rename(LabelCollection c, String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    c.name = n;
    c.touch();
    notifyListeners();
    _save();
  }

  LabelCollection duplicate(LabelCollection c, [String? name]) {
    final copy = LabelCollection(
      id: _newId(),
      name: (name ?? '').trim().isEmpty ? '${c.name} copy' : name!.trim(),
      lines: c.lines
          .map(
            (l) => CollectionLine(
              barcode: l.barcode,
              name: l.name,
              size: l.size,
              price: l.price,
              defaultCode: l.defaultCode,
              category: l.category,
              variantId: l.variantId,
              copies: l.copies,
            ),
          )
          .toList(),
    );
    _collections.add(copy);
    _activeId = copy.id;
    notifyListeners();
    _save();
    return copy;
  }

  void delete(LabelCollection c) {
    _collections.removeWhere((x) => x.id == c.id);
    if (_collections.isEmpty) {
      _collections.add(LabelCollection(id: _newId(), name: 'Batch 1'));
    }
    if (_activeId == c.id) _activeId = _collections.first.id;
    notifyListeners();
    _save();
  }

  void clearActive() {
    active?.lines.clear();
    active?.touch();
    notifyListeners();
    _save();
  }

  /// Add one label to the active collection (creates it when missing).
  /// Empty [size] is auto-parsed from [name]; explicit size wins.
  CollectionLine addToActive({
    required String barcode,
    required String name,
    required double price,
    String size = '',
    String defaultCode = '',
    String category = '',
    int? variantId,
  }) {
    var c = active;
    c ??= create('Batch 1');
    return _insert(
      c,
      barcode: barcode,
      name: name,
      price: price,
      size: size,
      defaultCode: defaultCode,
      category: category,
      variantId: variantId,
    ).line;
  }

  /// Add one picked label to a specific (pinned) collection.
  /// Returns whether the insert merged into an existing line.
  ({CollectionLine line, bool merged}) addTo(
    LabelCollection target,
    PickedLabel item,
  ) {
    return _insert(
      target,
      barcode: item.barcode,
      name: item.name,
      price: item.price,
      size: item.size,
      defaultCode: item.defaultCode,
      category: item.category,
      variantId: item.variantId,
    );
  }

  /// Bulk add picked labels to a specific collection with a single
  /// touch/notify/save at the end (no per-line churn on 1000-item adds).
  ({int added, int merged}) addAllTo(
    LabelCollection target,
    List<PickedLabel> items,
  ) {
    var added = 0;
    var merged = 0;
    for (final item in items) {
      final r = _insert(
        target,
        barcode: item.barcode,
        name: item.name,
        price: item.price,
        size: item.size,
        defaultCode: item.defaultCode,
        category: item.category,
        variantId: item.variantId,
        quiet: true,
      );
      if (r.merged) {
        merged++;
      } else {
        added++;
      }
    }
    target.touch();
    notifyListeners();
    _save();
    return (added: added, merged: merged);
  }

  ({CollectionLine line, bool merged}) _insert(
    LabelCollection c, {
    required String barcode,
    required String name,
    required double price,
    String size = '',
    String defaultCode = '',
    String category = '',
    int? variantId,
    bool quiet = false,
  }) {
    var s = size.trim();
    var base = name.trim();
    if (s.isEmpty) {
      final split = LabelModel.splitNameSize(base);
      base = split.name;
      s = split.size;
    }
    final key = keyOf(barcode: barcode, defaultCode: defaultCode, name: base);
    for (final l in c.lines) {
      if (keyOf(barcode: l.barcode, defaultCode: l.defaultCode, name: l.name) ==
          key) {
        l.copies = (l.copies + 1).clamp(1, 999);
        if (!quiet) {
          c.touch();
          notifyListeners();
          _save();
        }
        return (line: l, merged: true);
      }
    }
    final line = CollectionLine(
      barcode: barcode,
      name: base,
      size: s,
      price: price,
      defaultCode: defaultCode,
      category: category,
      variantId: variantId,
    );
    c.lines.add(line);
    if (!quiet) {
      c.touch();
      notifyListeners();
      _save();
    }
    return (line: line, merged: false);
  }

  void inc(CollectionLine l) {
    l.copies = (l.copies + 1).clamp(1, 999);
    active?.touch();
    notifyListeners();
    _save();
  }

  void dec(CollectionLine l) {
    final c = active;
    if (c == null) return;
    if (l.copies > 1) {
      l.copies--;
    } else {
      c.lines.remove(l);
    }
    c.touch();
    notifyListeners();
    _save();
  }

  void remove(CollectionLine l) {
    active?.lines.remove(l);
    active?.touch();
    notifyListeners();
    _save();
  }

  void updateSize(CollectionLine l, String size) {
    // Lines are mutable on purpose (copies/size/promo only). A size edit
    // must preserve kind + promo payload (else promos silently vanish).
    final i = active?.lines.indexOf(l) ?? -1;
    if (i < 0) return;
    active!.lines[i] = CollectionLine(
      barcode: l.barcode,
      name: l.name,
      size: size.trim(),
      price: l.price,
      defaultCode: l.defaultCode,
      category: l.category,
      variantId: l.variantId,
      copies: l.copies,
      addedAt: l.addedAt,
      kind: l.kind,
      wasPrice: l.wasPrice,
      promoEnds: l.promoEnds,
      saveText: l.saveText,
    );
    active!.touch();
    notifyListeners();
    _save();
  }

  /// Attach a promo payload to a line (flips kind to promo).
  void setPromo(
    CollectionLine l, {
    required double wasPrice,
    String promoEnds = '',
    String saveText = '',
  }) {
    l.kind = LabelKind.promo;
    l.wasPrice = wasPrice;
    l.promoEnds = promoEnds.trim();
    l.saveText = saveText.trim();
    active?.touch();
    notifyListeners();
    _save();
  }

  /// Remove a promo payload (reverts kind to standard).
  void clearPromo(CollectionLine l) {
    l.kind = LabelKind.standard;
    l.wasPrice = null;
    l.promoEnds = '';
    l.saveText = '';
    active?.touch();
    notifyListeners();
    _save();
  }

  /// One-time migration from the legacy single BatchStore.
  void migrateFromLegacy({
    required List<LabelModel> lines,
    required List<int> copies,
  }) {
    if (lines.isEmpty) return;
    var c = active;
    if (c == null || c.lines.isNotEmpty) return;
    for (var i = 0; i < lines.length; i++) {
      final m = lines[i];
      c.lines.add(
        CollectionLine(
          barcode: m.barcode,
          name: m.name,
          size: m.size,
          price: m.price,
          defaultCode: m.defaultCode,
          category: m.category,
          copies: i < copies.length ? copies[i].clamp(1, 999) : m.copies,
        ),
      );
    }
    c.touch();
    notifyListeners();
    _save();
  }

  /// TSV compatible with price-labels/gen-label-pngs.js
  /// (name, list_price, barcode, default_code, category).
  /// Size travels inside the name column ("name, size") for compat.
  String toTsv([LabelCollection? c]) {
    final col = c ?? active;
    final sb = StringBuffer(
      'name\tlist_price\tbarcode\tdefault_code\tcategory\n',
    );
    String esc(String s) => s.replaceAll('\t', ' ').replaceAll('\n', ' ');
    for (final l in col?.lines ?? const <CollectionLine>[]) {
      for (var i = 0; i < l.copies; i++) {
        sb.writeln(
          '${esc(l.model.displayName)}\t${l.price.toStringAsFixed(2)}\t${esc(l.barcode)}\t${esc(l.defaultCode)}\t${esc(l.category)}',
        );
      }
    }
    return sb.toString();
  }

  /// Test-only reset (no prefs I/O).
  void resetForTest() {
    _collections.clear();
    _activeId = null;
    _loaded = true;
  }

  static const _kCollections = 'label_collections_v1';
  static const _kActive = 'label_active_collection_v1';
}
