// In-app audit log for the v2 inventory loop.
// One line per price/qty/create write. No Odoo model in this slice —
// stepping stone to cloud9.inventory.log (04 §3.5).
library;

import 'package:flutter/foundation.dart';

class AuditEntry {
  final DateTime when;
  final String who;
  final String mode; // 'receive' | 'count' | 'create'
  final int productId;
  final String productName;
  final String field;
  final String oldValue;
  final String newValue;
  final String reason;

  AuditEntry({
    required this.when,
    required this.who,
    required this.mode,
    required this.productId,
    required this.productName,
    required this.field,
    required this.oldValue,
    required this.newValue,
    this.reason = '',
  });

  String describe() {
    final r = reason.trim().isEmpty ? '' : ' (reason: $reason)';
    return '$productName: $field $oldValue → $newValue$r';
  }
}

class AuditLog extends ChangeNotifier {
  AuditLog._();
  static final AuditLog instance = AuditLog._();

  static const int cap = 200;
  final List<AuditEntry> _entries = [];

  List<AuditEntry> get entries => List.unmodifiable(_entries);

  void add(AuditEntry e) {
    _entries.insert(0, e);
    while (_entries.length > cap) {
      _entries.removeLast();
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
