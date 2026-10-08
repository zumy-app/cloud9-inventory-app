import 'package:cloud9_inventory_app/print/label_model.dart';
import 'package:cloud9_inventory_app/print/tspl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('symbology: 12-13 digit numerics get EAN13, else Code128', () {
    expect(Tspl.symbologyFor('810120476612'), 'EAN13');
    expect(Tspl.symbologyFor('024300837968'), 'EAN13');
    expect(Tspl.symbologyFor('ABC-123'), '128');
    expect(Tspl.symbologyFor('6934747812005'), 'EAN13');
  });

  test('code prefers barcode, falls back to SKU', () {
    const a = LabelModel(name: 'n', price: 1, barcode: 'B', defaultCode: 'S');
    expect(a.code, 'B');
    const b = LabelModel(name: 'n', price: 1, barcode: '', defaultCode: 'S');
    expect(b.code, 'S');
    expect(b.hasCode, isTrue);
    const c = LabelModel(name: 'n', price: 1, barcode: '');
    expect(c.hasCode, isFalse);
  });

  test('composed label fits 2x1 budget and quotes safely', () {
    const m = LabelModel(
      name: 'Pecan Spinwheels',
      size: '2.1 "oz"',
      price: 2.49,
      barcode: '810120476612',
      copies: 2,
    );
    final out = Tspl.compose(m);
    expect(out, contains('SIZE 48 mm,25 mm'));
    expect(out, contains('BARCODE '));
    expect(out, contains('"EAN13"'));
    expect(out, contains('"810120476612"'));
    expect(out, contains('PRINT 2'));
    expect(out, isNot(contains('"oz"')));
    // Name line uses the full "name, size" display string.
    expect(out, contains('Pecan Spinwheels'));
    // Price is the BIG font "3".
    expect(out, contains('"3",0,1,1,"\$2.49"'));
    // Barcode block must start above the 200-dot bottom edge (4-dot margin).
    final by = int.parse(
        RegExp(r'BARCODE (\d+),(\d+),').firstMatch(out)!.group(2)!);
    expect(by, lessThanOrEqualTo(200 - 64 - 4));
  });

  test('barcode is centered and width scales with content', () {
    expect(Tspl.barcodeWidthFor('810120476612', 'EAN13'), 200);
    final wide =
        Tspl.barcodeWidthFor('ABC-123-LONG-SKU-999', '128');
    final narrow = Tspl.barcodeWidthFor('AB', '128');
    expect(wide, greaterThan(narrow));
    const m = LabelModel(name: 'n', price: 1, barcode: '810120476612');
    final out = Tspl.compose(m);
    final bx =
        int.parse(RegExp(r'BARCODE (\d+),').firstMatch(out)!.group(1)!);
    expect(bx, equals((384 - 200) ~/ 2));
  });

  test('empty code prints NO BARCODE placeholder, never blank', () {
    const m = LabelModel(name: 'Bulk Candy', price: 1.5, barcode: '');
    final out = Tspl.compose(m);
    expect(RegExp(r'^BARCODE ', multiLine: true).hasMatch(out), isFalse);
    expect(out, contains('NO BARCODE'));
  });

  test('logo bitmap centers and packs bits MSB-first', () {
    const m = LabelModel(name: 'n', price: 1, barcode: '1');
    // 8x1 all-black row -> one byte FF.
    final out = Tspl.compose(m, logoMono: List.filled(8, 1), logoWidth: 8);
    expect(out, contains('BITMAP'));
    expect(out, contains(',1,1,1,FF'));
  });

  test('encode is byte-stable ascii', () {
    final bytes = Tspl.encode('SIZE 48 mm,25 mm\n');
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes), contains('SIZE'));
  });
}
