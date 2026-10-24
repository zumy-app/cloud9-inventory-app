import 'package:flutter_test/flutter_test.dart';
import 'package:cloud9_inventory_app/waste_store.dart';

WasteLine line({
  String id = 'w1',
  double qty = 2,
  double unit = 2.5,
  WasteDisposition d = WasteDisposition.trashed,
  WasteStatus s = WasteStatus.validated,
  bool quar = false,
  DateTime? at,
}) {
  final now = at ?? DateTime.utc(2026, 3, 5);
  return WasteLine(
    id: id,
    variantId: 1,
    tmplId: 1,
    name: 'Milk',
    barcode: '123',
    sku: 'M1',
    qty: qty,
    reason: WasteReason.expired,
    disposition: d,
    unitValue: unit,
    status: s,
    discoveredAt: now,
    disposedAt: now,
    staff: 'clerk',
    quarantined: quar,
  );
}

void main() {
  test('netDeductible excludes donated, credited, draft, quarantined', () {
    final store = WasteStore.instance;
    store.seedForTest([
      line(id: 'a', d: WasteDisposition.trashed, s: WasteStatus.validated),
      line(id: 'b', d: WasteDisposition.donated, s: WasteStatus.validated),
      line(id: 'c', d: WasteDisposition.vendorCredited, s: WasteStatus.validated),
      line(id: 'd', d: WasteDisposition.trashed, s: WasteStatus.posted),
      line(id: 'e', d: WasteDisposition.trashed, s: WasteStatus.validated, quar: true),
    ]);
    // Only 'a' counts: 2 * 2.5 = 5.0
    expect(store.netDeductible, 5.0);
    expect(store.monthNet(2026, 3), 5.0);
    expect(store.monthNet(2026, 4), 0.0);
  });

  test('validate blocks self-approval and locked months', () {
    final store = WasteStore.instance;
    store.seedForTest([
      line(id: 'v1', s: WasteStatus.posted),
      line(id: 'v2', s: WasteStatus.posted),
    ]);
    expect(store.validate('v1', manager: 'clerk'), isFalse); // self
    expect(store.validate('v1', manager: 'mgr'), isTrue);
    expect(store.lines.firstWhere((l) => l.id == 'v1').status,
        WasteStatus.validated);
    store.lockMonth(DateTime.utc(2026, 3, 5));
    // Locked month blocks even a different manager.
    expect(store.validate('v2', manager: 'mgr2'), isFalse);
  });

  test('void keeps original + reversal, requires reason path', () {
    final store = WasteStore.instance;
    store.seedForTest([
      line(id: 'x', s: WasteStatus.validated),
    ]);
    expect(store.voidLine('x', manager: 'mgr'), isFalse); // reason required
    expect(store.voidLine('x', manager: 'mgr', reason: 'counted wrong'),
        isTrue);
    expect(store.lines.any((l) => l.id == 'x' && l.status == WasteStatus.voided),
        isTrue);
    expect(store.lines.any((l) => l.id == 'x-R'), isTrue);
    // Net now: original voided (excluded) + reversal -5.0 validated donated? No:
    // reversal keeps same disposition (trashed) with negative value -> -5.0.
    expect(store.netDeductible, -5.0);
  });

  test('CSV frozen values do not change after seed', () {
    final store = WasteStore.instance;
    store.seedForTest([line(id: 'c1')]);
    final csv = store.toLinesCsv();
    expect(csv, contains('disposed_at,discovered_at,staff'));
    expect(csv, contains('5.00')); // 2 * 2.50 frozen total
    expect(store.toSummaryCsv(), contains('net_deductible'));
  });
}
