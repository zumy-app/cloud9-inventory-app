// Waste / loss log for expired, damaged, spoiled items (IRS-ready).
// Append-only: corrections are reversing entries, originals never mutate.
// Disposition date (disposedAt, server-validated) is the tax date;
// packageExpiry is supporting detail only.
library;

import 'package:flutter/foundation.dart';

/// Loss reason (what happened to the product).
enum WasteReason { expired, damaged, spoiled, recall }

/// Disposition (what happened to the physical goods).
enum WasteDisposition { trashed, donated, vendorCreditPending, vendorCredited }

enum WasteStatus { draft, posted, validated, voided }

String wasteReasonLabel(WasteReason r) => switch (r) {
      WasteReason.expired => 'Expired on shelf',
      WasteReason.damaged => 'Damaged / broken',
      WasteReason.spoiled => 'Spoiled / sour',
      WasteReason.recall => 'Recall',
    };

String wasteDispositionLabel(WasteDisposition d) => switch (d) {
      WasteDisposition.trashed => 'Trashed / destroyed',
      WasteDisposition.donated => 'Donated',
      WasteDisposition.vendorCreditPending => 'Vendor credit pending',
      WasteDisposition.vendorCredited => 'Vendor credit received',
    };

class WasteLine {
  final String id;
  final int variantId;
  final int tmplId;
  final String name;
  final String barcode;
  final String sku;
  final double qty;
  final WasteReason reason;
  final WasteDisposition disposition;
  final String packageExpiry; // '' = illegible / none
  final String note;
  final String supplierInvoice;
  final double unitValue; // frozen at post time (Odoo layer value)
  final double retailEach; // info only
  final int? scrapId; // Odoo stock.scrap id once posted
  final WasteStatus status;
  final DateTime discoveredAt; // device time (contemporaneous proof)
  final DateTime? disposedAt; // server-validated time (tax date)
  final String staff;
  final String validatedBy;
  final bool quarantined; // qty > on-hand override, needs manager review
  final String? voidChain; // id of reversing entry when voided

  const WasteLine({
    required this.id,
    required this.variantId,
    required this.tmplId,
    required this.name,
    required this.barcode,
    required this.sku,
    required this.qty,
    required this.reason,
    required this.disposition,
    this.packageExpiry = '',
    this.note = '',
    this.supplierInvoice = '',
    required this.unitValue,
    this.retailEach = 0,
    this.scrapId,
    this.status = WasteStatus.draft,
    required this.discoveredAt,
    this.disposedAt,
    this.staff = '',
    this.validatedBy = '',
    this.quarantined = false,
    this.voidChain,
  });

  double get totalValue => qty * unitValue;

  /// Deductible only when validated, not voided, not donated/credited,
  /// and not quarantined-pending-review.
  bool get isDeductible =>
      status == WasteStatus.validated &&
      !quarantined &&
      disposition != WasteDisposition.donated &&
      disposition != WasteDisposition.vendorCredited;

  WasteLine copyWith({
    double? qty,
    WasteReason? reason,
    WasteDisposition? disposition,
    String? packageExpiry,
    String? note,
    String? supplierInvoice,
    double? unitValue,
    double? retailEach,
    int? scrapId,
    WasteStatus? status,
    DateTime? disposedAt,
    String? validatedBy,
    bool? quarantined,
    String? voidChain,
  }) {
    return WasteLine(
      id: id,
      variantId: variantId,
      tmplId: tmplId,
      name: name,
      barcode: barcode,
      sku: sku,
      qty: qty ?? this.qty,
      reason: reason ?? this.reason,
      disposition: disposition ?? this.disposition,
      packageExpiry: packageExpiry ?? this.packageExpiry,
      note: note ?? this.note,
      supplierInvoice: supplierInvoice ?? this.supplierInvoice,
      unitValue: unitValue ?? this.unitValue,
      retailEach: retailEach ?? this.retailEach,
      scrapId: scrapId ?? this.scrapId,
      status: status ?? this.status,
      discoveredAt: discoveredAt,
      disposedAt: disposedAt ?? this.disposedAt,
      staff: staff,
      validatedBy: validatedBy ?? this.validatedBy,
      quarantined: quarantined ?? this.quarantined,
      voidChain: voidChain ?? this.voidChain,
    );
  }

  static String _esc(String s) =>
      s.replaceAll('\t', ' ').replaceAll('\n', ' ').replaceAll(',', ';');

  String toCsvRow() {
    String fmt(DateTime? d) => d == null ? '' : d.toIso8601String();
    return [
      fmt(disposedAt),
      fmt(discoveredAt),
      _esc(staff),
      _esc(validatedBy),
      _esc(barcode),
      _esc(sku),
      _esc(name),
      wasteReasonLabel(reason),
      wasteDispositionLabel(disposition),
      qty.toString(),
      unitValue.toStringAsFixed(2),
      totalValue.toStringAsFixed(2),
      packageExpiry,
      _esc(supplierInvoice),
      _esc(note),
      scrapId?.toString() ?? '',
      status.name,
      quarantined ? 'yes' : 'no',
      voidChain ?? '',
    ].join(',');
  }
}

class WasteStore extends ChangeNotifier {
  WasteStore._();
  static final WasteStore instance = WasteStore._();

  final List<WasteLine> _lines = [];
  final Set<String> _lockedMonths = {}; // 'yyyy-MM' validated + locked

  List<WasteLine> get lines => List.unmodifiable(_lines);

  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  bool isLocked(DateTime d) => _lockedMonths.contains(monthKey(d));

  void add(WasteLine line) {
    _lines.insert(0, line);
    notifyListeners();
  }

  void markPosted(String id, {required int scrapId, required double unitValue, DateTime? disposedAt}) {
    final i = _lines.indexWhere((l) => l.id == id);
    if (i < 0) return;
    final l = _lines[i];
    _lines[i] = l.copyWith(
      scrapId: scrapId,
      unitValue: unitValue,
      status: WasteStatus.posted,
      disposedAt: disposedAt ?? DateTime.now().toUtc(),
    );
    notifyListeners();
  }

  /// Manager validation. Blocked for locked months and self-approval.
  /// Returns false when blocked.
  bool validate(String id, {required String manager}) {
    final i = _lines.indexWhere((l) => l.id == id);
    if (i < 0) return false;
    final l = _lines[i];
    final ref = l.disposedAt ?? l.discoveredAt;
    if (isLocked(ref)) return false;
    if (l.staff.isNotEmpty && l.staff == manager) return false;
    if (l.status != WasteStatus.posted) return false;
    _lines[i] = l.copyWith(status: WasteStatus.validated, validatedBy: manager);
    notifyListeners();
    return true;
  }

  /// Void via reversal: original stays, status -> voided with chain link.
  bool voidLine(String id, {required String manager, String reason = ''}) {
    final i = _lines.indexWhere((l) => l.id == id);
    if (i < 0) return false;
    final l = _lines[i];
    final ref = l.disposedAt ?? l.discoveredAt;
    if (isLocked(ref)) return false;
    if (reason.trim().isEmpty) return false;
    final reversal = WasteLine(
      id: '${l.id}-R',
      variantId: l.variantId,
      tmplId: l.tmplId,
      name: l.name,
      barcode: l.barcode,
      sku: l.sku,
      qty: l.qty,
      reason: l.reason,
      disposition: l.disposition,
      packageExpiry: l.packageExpiry,
      note: 'VOID of ${l.id}: $reason',
      supplierInvoice: l.supplierInvoice,
      unitValue: -l.unitValue,
      retailEach: l.retailEach,
      status: WasteStatus.validated,
      discoveredAt: DateTime.now().toUtc(),
      disposedAt: DateTime.now().toUtc(),
      staff: manager,
      validatedBy: manager,
    );
    _lines[i] = l.copyWith(status: WasteStatus.voided, voidChain: reversal.id);
    _lines.insert(0, reversal);
    notifyListeners();
    return true;
  }

  void lockMonth(DateTime d) {
    _lockedMonths.add(monthKey(d));
    notifyListeners();
  }

  double get netDeductible =>
      _lines.where((l) => l.isDeductible).fold(0, (a, l) => a + l.totalValue);

  double monthNet(int year, int month) => _lines
      .where((l) =>
          l.isDeductible &&
          (l.disposedAt ?? l.discoveredAt).year == year &&
          (l.disposedAt ?? l.discoveredAt).month == month)
      .fold(0, (a, l) => a + l.totalValue);

  String toLinesCsv() {
    final sb = StringBuffer(
        'disposed_at,discovered_at,staff,validated_by,barcode,sku,name,reason,disposition,qty,unit_value,total_value,package_expiry,supplier_invoice,note,scrap_id,status,quarantined,void_chain\n');
    for (final l in _lines) {
      sb.writeln(l.toCsvRow());
    }
    return sb.toString();
  }

  String toSummaryCsv({String inventoryMethod = 'AVCO'}) {
    final byMonth = <String, List<WasteLine>>{};
    for (final l in _lines) {
      if (l.status == WasteStatus.draft) continue;
      final d = l.disposedAt ?? l.discoveredAt;
      byMonth.putIfAbsent(monthKey(d), () => []).add(l);
    }
    final sb = StringBuffer(
        'month,lines,units,scrap_value,vendor_credits,donations,net_deductible,inventory_method\n');
    final keys = byMonth.keys.toList()..sort();
    for (final k in keys) {
      final ls = byMonth[k]!;
      final units = ls.fold(0.0, (a, l) => a + l.qty);
      final gross = ls
          .where((l) => l.status == WasteStatus.validated)
          .fold(0.0, (a, l) => a + l.totalValue);
      final credits = ls
          .where((l) =>
              l.status == WasteStatus.validated &&
              l.disposition == WasteDisposition.vendorCredited)
          .fold(0.0, (a, l) => a + l.totalValue);
      final donations = ls
          .where((l) =>
              l.status == WasteStatus.validated &&
              l.disposition == WasteDisposition.donated)
          .fold(0.0, (a, l) => a + l.totalValue);
      final net = ls.where((l) => l.isDeductible).fold(0.0, (a, l) => a + l.totalValue);
      sb.writeln(
          '$k,${ls.length},${units.toStringAsFixed(0)},${gross.toStringAsFixed(2)},${credits.toStringAsFixed(2)},${donations.toStringAsFixed(2)},${net.toStringAsFixed(2)},$inventoryMethod');
    }
    return sb.toString();
  }

  void clear() {
    _lines.clear();
    _lockedMonths.clear();
    notifyListeners();
  }

  @visibleForTesting
  void seedForTest(List<WasteLine> rows) {
    _lines
      ..clear()
      ..addAll(rows);
    _lockedMonths.clear();
    notifyListeners();
  }
}
