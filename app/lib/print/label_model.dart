// Canonical label content for price labels (2"x1").
// Single source for BOTH outputs: Bluetooth printing (lib/print/tspl.dart)
// and the back-office TSV export (lib/batch_store.dart). Add fields here,
// not in each consumer.
library;

import '../odoo_client.dart';

class LabelModel {
  /// Item name as printed (includes size, e.g. "Pecan Spinwheels, 2.1 oz").
  final String name;

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
    this.defaultCode = '',
    this.category = '',
    this.copies = 1,
  });

  /// Scannable code: barcode first, SKU fallback, '' when neither.
  String get code {
    if (barcode.trim().isNotEmpty) return barcode.trim();
    return defaultCode.trim();
  }

  bool get hasCode => code.isNotEmpty;

  factory LabelModel.fromProduct(
    InventoryProduct p, {
    double? priceOverride,
    String? nameOverride,
    int copies = 1,
  }) {
    return LabelModel(
      name: (nameOverride ?? p.name).trim(),
      price: priceOverride ?? p.listPrice,
      barcode: p.barcode,
      defaultCode: p.defaultCode,
      copies: copies < 1 ? 1 : copies,
    );
  }

  String get priceText => '\$${price.toStringAsFixed(2)}';
}
