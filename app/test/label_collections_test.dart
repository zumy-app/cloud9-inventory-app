import 'package:cloud9_inventory_app/label_collections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => LabelCollections.instance.resetForTest());

  test('create + setActive switches without losing data', () {
    final store = LabelCollections.instance;
    final a = store.create('Drinks');
    store.addToActive(barcode: '1', name: 'Coke 12pk', price: 9.99);
    final b = store.create('Snacks');
    expect(store.active!.id, b.id);
    expect(store.activeLines, isEmpty);
    store.setActive(a.id);
    expect(store.active!.id, a.id);
    expect(store.activeLines.single.model.displayName, 'Coke, 12pk');
  });

  test('same code merges, barcode-less never merge', () {
    final store = LabelCollections.instance;
    store.create('Today');
    store.addToActive(barcode: '1', name: 'Coke', price: 1);
    store.addToActive(barcode: '1', name: 'Coke', price: 1);
    expect(store.activeLines.single.copies, 2);
    store.addToActive(barcode: '', name: 'Bulk A', price: 1);
    store.addToActive(barcode: '', name: 'Bulk B', price: 1);
    expect(store.activeLines.length, 3);
  });

  test('size auto-parses, explicit size wins, updateSize edits', () {
    final store = LabelCollections.instance;
    store.create('Today');
    final l = store.addToActive(
      barcode: '1',
      name: 'Pecan Spinwheels, 2.1 oz',
      price: 2.49,
    );
    expect(l.name, 'Pecan Spinwheels');
    expect(l.size, '2.1 oz');
    store.updateSize(l, '4 oz');
    expect(store.activeLines.single.size, '4 oz');
  });

  test('duplicate copies lines, delete keeps one collection', () {
    final store = LabelCollections.instance;
    final a = store.create('Drinks');
    store.addToActive(barcode: '1', name: 'Coke', price: 1);
    final copy = store.duplicate(a);
    expect(copy.lines.length, 1);
    expect(store.collections.length, 2);
    store.delete(a);
    store.delete(copy);
    expect(store.collections.length, 1);
    expect(store.active, isNotNull);
  });

  test('toTsv embeds size in the name column for compat', () {
    final store = LabelCollections.instance;
    store.create('Today');
    store.addToActive(barcode: '1', name: 'Coke 12pk', price: 9.99);
    final tsv = store.toTsv();
    expect(tsv, contains('name\tlist_price\tbarcode'));
    expect(tsv, contains('Coke, 12pk'));
  });

  test('byId finds pinned target, null when missing', () {
    final store = LabelCollections.instance;
    final a = store.create('Drinks');
    store.create('Snacks');
    expect(store.byId(a.id)?.name, 'Drinks');
    expect(store.byId('nope'), isNull);
  });

  test('addTo pins items to opener while active differs', () {
    final store = LabelCollections.instance;
    final a = store.create('A');
    final b = store.create('B');
    expect(store.active!.id, b.id);
    const item = (
      barcode: '1',
      name: 'Coke 12pk',
      price: 9.99,
      size: '',
      defaultCode: '',
      category: 'Drinks',
      variantId: 7,
    );
    final r = store.addTo(a, item);
    expect(r.merged, isFalse);
    expect(r.line.name, 'Coke');
    expect(r.line.size, '12pk');
    expect(r.line.variantId, 7);
    expect(a.lines.length, 1);
    expect(b.lines, isEmpty);
  });

  test('addAllTo reports added vs merged with one summary', () {
    final store = LabelCollections.instance;
    final a = store.create('A');
    store.addToActive(barcode: '1', name: 'Coke', price: 1);
    store.setActive(a.id);
    final summary = store.addAllTo(a, const [
      (
        barcode: '1',
        name: 'Coke',
        price: 1.0,
        size: '',
        defaultCode: '',
        category: '',
        variantId: null,
      ),
      (
        barcode: '2',
        name: 'Pepsi',
        price: 1.0,
        size: '',
        defaultCode: '',
        category: '',
        variantId: null,
      ),
      (
        barcode: '',
        name: 'Bulk Candy',
        price: 1.0,
        size: '',
        defaultCode: '',
        category: '',
        variantId: null,
      ),
    ]);
    expect(summary, (added: 2, merged: 1));
    expect(a.totalCopies, 4); // 1 + merged+1 + 1 + 1
  });

  test('serialization round-trips', () {
    final store = LabelCollections.instance;
    final c = store.create('Drinks');
    store.addToActive(barcode: '1', name: 'Coke 12pk', price: 9.99);
    final back = LabelCollection.fromJson(c.toJson());
    expect(back.name, 'Drinks');
    expect(back.lines.single.model.displayName, 'Coke, 12pk');
    expect(back.idempotencyKey, isNotEmpty);
  });
}
