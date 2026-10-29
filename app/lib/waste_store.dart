// Waste / loss log for expired, damaged, spoiled items (IRS-ready).
// Append-only: corrections are reversing entries, originals never mutate.
// Disposition date (disposedAt, server-validated) is the tax date;
// packageExpiry is supporting detail only.
//
// Persistence: lines + locks survive restarts via SharedPreferences so the
// history/report view is not wiped by reinstalls/updates. Server scraps
// remain the cross-check (see OdooClient.fetchScrapHistory).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Stable DB keys for the shared Odoo `origin` encoding (see
/// OdooClient.buildWasteOrigin). Labels stay human-facing; keys are what
/// the server browser filters on so renames never break history.
String wasteReasonKey(WasteReason r) => r.name;

String wasteDispositionKey(WasteDisposition d) => d.name;

WasteReason wasteReasonFromKey(String key) {
  for (final r in WasteReason.values) {
    if (r.name == key) return r;
  }
  return WasteReason.expired;
}

WasteDisposition wasteDispositionFromKey(String key) {
  for (final d in WasteDisposition.values) {
    if (d.name == key) return d;
  }
  return WasteDisposition.trashed;
}

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'variantId': variantId,
        'tmplId': tmplId,
        'name': name,
        'barcode': barcode,
        'sku': sku,
        'qty': qty,
        'reason': reason.index,
        'disposition': disposition.index,
        'packageExpiry': packageExpiry,
        'note': note,
        'supplierInvoice': supplierInvoice,
        'unitValue': unitValue,
        'retailEach': retailEach,
        'scrapId': scrapId,
        'status': status.index,
        'discoveredAt': discoveredAt.toIso8601String(),
        'disposedAt': disposedAt?.toIso8601String(),
        'staff': staff,
        'validatedBy': validatedBy,
        'quarantined': quarantined,
        'voidChain': voidChain,
      };

  factory WasteLine.fromJson(Map<String, dynamic> j) => WasteLine(
        id: (j['id'] ?? '').toString(),
        variantId: (j['variantId'] as num?)?.toInt() ?? 0,
        tmplId: (j['tmplId'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        barcode: (j['barcode'] ?? '').toString(),
        sku: (j['sku'] ?? '').toString(),
        qty: (j['qty'] as num?)?.toDouble() ?? 0,
        reason: WasteReason.values[
            ((j['reason'] as num?)?.toInt() ?? 0) % WasteReason.values.length],
        disposition: WasteDisposition.values[((j['disposition'] as num?)
                ?.toInt() ??
            0) % WasteDisposition.values.length],
        packageExpiry: (j['packageExpiry'] ?? '').toString(),
        note: (j['note'] ?? '').toString(),
        supplierInvoice: (j['supplierInvoice'] ?? '').toString(),
        unitValue: (j['unitValue'] as num?)?.toDouble() ?? 0,
        retailEach: (j['retailEach'] as num?)?.toDouble() ?? 0,
        scrapId: (j['scrapId'] as num?)?.toInt(),
        status: WasteStatus.values[
            ((j['status'] as num?)?.toInt() ?? 0) % WasteStatus.values.length],
        discoveredAt: DateTime.tryParse((j['discoveredAt'] ?? '').toString()) ??
            DateTime.now().toUtc(),
        disposedAt: j['disposedAt'] == null
            ? null
            : DateTime.tryParse(j['disposedAt'].toString()),
        staff: (j['staff'] ?? '').toString(),
        validatedBy: (j['validatedBy'] ?? '').toString(),
        quarantined: j['quarantined'] == true,
        voidChain: j['voidChain']?.toString(),
      );

  /// Live loss math used by the form: qty × effective unit cost.
  /// Whitebox-tested; the form must call this (not a stale snapshot).
  static double liveTotal(double qty, double effectiveUnitCost) =>
      qty * effectiveUnitCost;
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
    persist();
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
    persist();
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
    persist();
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
    persist();
    return true;
  }

  void lockMonth(DateTime d) {
    _lockedMonths.add(monthKey(d));
    notifyListeners();
    persist();
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
    persist();
  }

  static const _kLines = 'waste_lines_v1';
  static const _kLocks = 'waste_locks_v1';

  /// Best-effort persistence; never throws (history must not block logging).
  Future<void> persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = jsonEncode(_lines.map((l) => l.toJson()).toList());
      await p.setString(_kLines, raw);
      await p.setStringList(_kLocks, _lockedMonths.toList());
    } catch (_) {}
  }

  /// Load persisted lines/locks (call once from the Waste screen init).
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kLines);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List)
            .map((e) => WasteLine.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        _lines
          ..clear()
          ..addAll(list);
      }
      final locks = p.getStringList(_kLocks) ?? const [];
      _lockedMonths
        ..clear()
        ..addAll(locks);
      notifyListeners();
    } catch (_) {}
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
