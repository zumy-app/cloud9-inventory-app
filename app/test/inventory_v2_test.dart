import 'package:cloud9_inventory_app/audit_log.dart';
import 'package:cloud9_inventory_app/batch_store.dart';
import 'package:cloud9_inventory_app/category_map.dart';
import 'package:cloud9_inventory_app/odoo_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category map resolves seeded pair', () {
    final pair = CategoryMap.resolve(
      pos: const PosCategory(id: 3, name: 'Drinks'),
      internalCats: const [
        PosCategory(id: 10, name: 'All'),
        PosCategory(id: 11, name: 'Drinks'),
      ],
    );
    expect(pair, isNotNull);
    expect(pair!.posId, 3);
    expect(pair.internalId, 11);
  });

  test('category map returns null when unmapped', () {
    final pair = CategoryMap.resolve(
      pos: const PosCategory(id: 3, name: 'Drinks'),
      internalCats: const [PosCategory(id: 10, name: 'All')],
    );
    expect(pair, isNull);
  });

  test('category filter matches substring case-insensitively', () {
    const cats = [
      PosCategory(id: 1, name: 'Drinks'),
      PosCategory(id: 2, name: 'Snacks'),
    ];
    expect(CategoryMap.filter(cats, 'dri').length, 1);
    expect(CategoryMap.filter(cats, '').length, 2);
  });

  test('batch key keeps barcode-less items separate', () {
    expect(
        BatchStore.keyOf(barcode: '', defaultCode: 'SKU1', name: 'A'),
        isNot(BatchStore.keyOf(
            barcode: '', defaultCode: 'SKU2', name: 'B')));
    expect(
        BatchStore.keyOf(barcode: '', defaultCode: '', name: 'A'),
        BatchStore.keyOf(barcode: '', defaultCode: '', name: 'a'));
  });

  test('audit log caps at 200 entries', () {
    final log = AuditLog.instance;
    log.clear();
    for (var i = 0; i < 250; i++) {
      log.add(AuditEntry(
        when: DateTime(2026, 1, 1),
        who: 't',
        mode: 'receive',
        productId: i,
        productName: 'p$i',
        field: 'qty',
        oldValue: '0',
        newValue: '1',
      ));
    }
    expect(log.entries.length, AuditLog.cap);
    expect(log.entries.first.productId, 249);
  });
}
