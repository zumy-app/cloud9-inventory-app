// Canonical label content for price labels (2"x1").
// Single source for BOTH outputs: Bluetooth printing (lib/print/tspl.dart)
// and the back-office TSV export (lib/batch_store.dart). Add fields here,
// not in each consumer.
//
// Wireframe label types (labels-wireframes/): [LabelKind] selects the
// template; promo + kitchen payloads are nullable so legacy lines and
// persisted collections load unchanged.
library;

import '../odoo_client.dart';

/// Wireframe template selector (2_x_1_thermal_label_*).
enum LabelKind { standard, promo, rapidScan, kitchen }

/// On-demand kitchen fridge-tag payload (Type 04). All strings are
/// preformatted display text; the composer places them, never parses.
class PrepInfo {
  final String item;
  final String qty;
  final String lot;
  final String preppedBy;
  final String preppedAt;
  final String useBy;
  final String fifoChip;
  final String station;
  final String temp;
  final String allergens;
  final String origin;
  final String pan;
  final String unitText;

  const PrepInfo({
    required this.item,
    this.qty = '',
    this.lot = '',
    this.preppedBy = '',
    this.preppedAt = '',
    this.useBy = '',
    this.fifoChip = '',
    this.station = '',
    this.temp = '',
    this.allergens = '',
    this.origin = '',
    this.pan = '',
    this.unitText = '',
  });
}

class LabelModel {
  /// Base item name as printed (without size).
  /// Use [displayName] for the full "name, size" line.
  final String name;

  /// Display size parsed from the product name (e.g. "2.1 oz", "12pk").
  /// '' when none detected; editable per label line in the UI.
  final String size;

  /// Sale price printed on the label.
  final double price;

  /// Primary code (barcode preferred, SKU fallback).
  final String barcode;
  final String defaultCode;
  final String category;

  /// Copies for PRINT n.
  final int copies;

  /// Wireframe template. Defaults to standard so every existing call
  /// site and persisted line keeps rendering.
  final LabelKind kind;

  /// Promo payload (Type 02). Null = not a promo; a promo kind with null
  /// [wasPrice] renders as standard (defensive, tested).
  final double? wasPrice;
  final String promoEnds;
  final String saveText;

  /// Kitchen payload (Type 04). Null unless [kind] is kitchen.
  final PrepInfo? prep;

  const LabelModel({
    required this.name,
    required this.price,
    required this.barcode,
    this.size = '',
    this.defaultCode = '',
    this.category = '',
    this.copies = 1,
    this.kind = LabelKind.standard,
    this.wasPrice,
    this.promoEnds = '',
    this.saveText = '',
    this.prep,
  });

  /// Full name line as printed: "name, size" when a size is present.
  /// Legacy callers may pass a name that already ends with the size;
  /// in that case it is not duplicated.
  String get displayName {
    final n = name.trim();
    final s = size.trim();
    if (s.isEmpty) return n;
    if (n.toLowerCase().endsWith(s.toLowerCase())) return n;
    return '$n, $s';
  }

  /// Scannable code: barcode first, SKU fallback, '' when neither.
  String get code {
    if (barcode.trim().isNotEmpty) return barcode.trim();
    return defaultCode.trim();
  }

  bool get hasCode => code.isNotEmpty;

  /// Split a product name into base + trailing size token.
  /// Matches a trailing `[qty] [unit]` token at the very end (e.g.
  /// "Coke 12pk", "Pecan Spinwheels, 2.1 oz", "Milk 1 Gal").
  /// Returns `(full, '')` when no size is detected so the name is
  /// never blanked.
  static ({String name, String size}) splitNameSize(String full) {
    final t = full.trim();
    if (t.isEmpty) return (name: t, size: '');
    final m = _sizeTail.firstMatch(t);
    if (m == null) return (name: t, size: '');
    final size = m.group(1)!.trim().replaceAll(RegExp(r'\s+'), ' ');
    var base = t.substring(0, m.start).trim();
    // Strip a single trailing separator left behind (",", "-", ":").
    base = base.replaceAll(RegExp(r'[\s,:\-–—;]+$'), '').trim();
    if (base.length < 2) return (name: t, size: '');
    return (name: base, size: size);
  }

  static final RegExp _sizeTail = RegExp(
    r'[\s,:\-–—;]+(\d+(?:\.\d+)?\s*(?:fl\s*oz|oz|lb|lbs|g|kg|ml|l|gal|qt|pt|ct|pk|pack|packs|bunch|ea|pcs))\s*$',
    caseSensitive: false,
  );

  factory LabelModel.fromProduct(
    InventoryProduct p, {
    double? priceOverride,
    String? nameOverride,
    String? sizeOverride,
    int copies = 1,
  }) {
    final split = splitNameSize((nameOverride ?? p.name).trim());
    return LabelModel(
      name: split.name,
      size: (sizeOverride ?? split.size).trim(),
      price: priceOverride ?? p.listPrice,
      barcode: p.barcode,
      defaultCode: p.defaultCode,
      copies: copies < 1 ? 1 : copies,
    );
  }

  LabelModel copyWith({
    String? name,
    String? size,
    double? price,
    String? barcode,
    String? defaultCode,
    String? category,
    int? copies,
    LabelKind? kind,
    double? wasPrice,
    bool clearWasPrice = false,
    String? promoEnds,
    String? saveText,
    PrepInfo? prep,
  }) {
    return LabelModel(
      name: name ?? this.name,
      size: size ?? this.size,
      price: price ?? this.price,
      barcode: barcode ?? this.barcode,
      defaultCode: defaultCode ?? this.defaultCode,
      category: category ?? this.category,
      copies: copies ?? this.copies,
      kind: kind ?? this.kind,
      wasPrice: clearWasPrice ? null : (wasPrice ?? this.wasPrice),
      promoEnds: promoEnds ?? this.promoEnds,
      saveText: saveText ?? this.saveText,
      prep: prep ?? this.prep,
    );
  }

  String get priceText => '\$${price.toStringAsFixed(2)}';
}
