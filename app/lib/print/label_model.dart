// Canonical label content for price labels (2"x1").
// Single source for BOTH outputs: Bluetooth printing (lib/print/tspl.dart)
// and the back-office TSV export (lib/batch_store.dart). Add fields here,
// not in each consumer.
library;

import '../odoo_client.dart';

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

  const LabelModel({
    required this.name,
    required this.price,
    required this.barcode,
    this.size = '',
    this.defaultCode = '',
    this.category = '',
    this.copies = 1,
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
  }) {
    return LabelModel(
      name: name ?? this.name,
      size: size ?? this.size,
      price: price ?? this.price,
      barcode: barcode ?? this.barcode,
      defaultCode: defaultCode ?? this.defaultCode,
      category: category ?? this.category,
      copies: copies ?? this.copies,
    );
  }

  String get priceText => '\$${price.toStringAsFixed(2)}';
}
