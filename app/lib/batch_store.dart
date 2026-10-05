// In-memory label batch for the MVP (no DB, no backend).
// Each entry: product name + price + barcode + copies.
library;

import 'package:flutter/foundation.dart';

class LabelLine {
  final String barcode;
  final String name;
  final double price;
  final String defaultCode;
  final String category;
  int copies;

  LabelLine({
    required this.barcode,
    required this.name,
    required this.price,
    this.defaultCode = '',
    this.category = '',
    this.copies = 1,
  });
}

class BatchStore extends ChangeNotifier {
  BatchStore._();
  static final BatchStore instance = BatchStore._();

  final List<LabelLine> _lines = [];

  List<LabelLine> get lines => List.unmodifiable(_lines);
  int get totalCopies => _lines.fold(0, (a, l) => a + l.copies);

  /// Line key: barcode || defaultCode || name (so barcode-less items
  /// never merge into one line).
  static String keyOf({
    required String barcode,
    required String defaultCode,
    required String name,
  }) {
    if (barcode.trim().isNotEmpty) return 'b:${barcode.trim()}';
    if (defaultCode.trim().isNotEmpty) return 's:${defaultCode.trim()}';
    return 'n:${name.trim().toLowerCase()}';
  }

  void add({
    required String barcode,
    required String name,
    required double price,
    String defaultCode = '',
    String category = '',
  }) {
    final key = keyOf(barcode: barcode, defaultCode: defaultCode, name: name);
    for (final l in _lines) {
      if (keyOf(
              barcode: l.barcode,
              defaultCode: l.defaultCode,
              name: l.name) ==
          key) {
        l.copies++;
        notifyListeners();
        return;
      }
    }
    _lines.add(LabelLine(
        barcode: barcode,
        name: name,
        price: price,
        defaultCode: defaultCode,
        category: category));
    notifyListeners();
  }

  void inc(LabelLine l) {
    l.copies++;
    notifyListeners();
  }

  void dec(LabelLine l) {
    if (l.copies > 1) {
      l.copies--;
    } else {
      _lines.remove(l);
    }
    notifyListeners();
  }

  void remove(LabelLine l) {
    _lines.remove(l);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  /// TSV compatible with price-labels/gen-label-pngs.js
  /// (name, list_price, barcode, default_code, category).
  String toTsv() {
    final sb = StringBuffer('name\tlist_price\tbarcode\tdefault_code\tcategory\n');
    String esc(String s) => s.replaceAll('\t', ' ').replaceAll('\n', ' ');
    for (final l in _lines) {
      for (var i = 0; i < l.copies; i++) {
        sb.writeln(
            '${esc(l.name)}\t${l.price.toStringAsFixed(2)}\t${esc(l.barcode)}\t${esc(l.defaultCode)}\t${esc(l.category)}');
      }
    }
    return sb.toString();
  }
}
