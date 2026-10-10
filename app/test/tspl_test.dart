import 'package:cloud9_inventory_app/print/label_model.dart';
import 'package:cloud9_inventory_app/print/tspl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizer: UPC-A aware, Mod10, separators stripped', () {
    // 11-digit base gains its check digit -> UPCA.
    expect(Tspl.normalizeCode('07824919284'),
        (digits: '078249192848', symbology: 'UPCA'));
    // 12-digit UPC-A (incl. the reference 035000510892) -> UPCA, not EAN13:
    // declaring EAN13 for 12-digit data is what printed digits with no
    // scannable bars on the PM-241-BT.
    expect(Tspl.normalizeCode('035000510892'),
        (digits: '035000510892', symbology: 'UPCA'));
    expect(Tspl.normalizeCode('810120476612'),
        (digits: '810120476612', symbology: 'UPCA'));
    expect(Tspl.normalizeCode('6934747812005'),
        (digits: '6934747812005', symbology: 'EAN13'));
    // Separators stripped before classification.
    expect(Tspl.normalizeCode('035-00051-0892'),
        (digits: '035000510892', symbology: 'UPCA'));
    expect(Tspl.normalizeCode('ABC-123'),
        (digits: 'ABC-123', symbology: '128'));
    expect(Tspl.symbologyFor('035000510892'), 'UPCA');
  });

  test('upc check digit matches known values', () {
    expect(Tspl.upcCheckDigit('07824919284'), '8');
    // Coca-Cola 12oz classic: 036000291452.
    expect(Tspl.upcCheckDigit('03600029145'), '2');
  });

  test('title wraps to two uppercase lines, never truncates mid-word', () {
    expect(
      Tspl.titleLines('Colgate - Cavity Protection Toothpaste - 5 oz'),
      ['COLGATE - CAVITY PROTECTION', 'TOOTHPASTE - 5 OZ'],
    );
    expect(Tspl.titleLines('Coke'), ['COKE']);
    expect(Tspl.titleLines(''), ['']);
  });

  test('unit price derives from parsed size qty', () {
    expect(Tspl.unitPriceText(4.49, '5 oz'), '\$0.90 / OZ');
    expect(Tspl.unitPriceText(9.99, '12pk'), '\$0.83 / PK');
    expect(Tspl.unitPriceText(1.0, ''), isNull);
    expect(Tspl.unitPriceText(1.0, 'Bulk'), isNull);
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

  test('type01: zones, hero lockup, digits text, budget', () {
    const m = LabelModel(
      name: 'Colgate - Cavity Protection Toothpaste',
      size: '5 oz',
      price: 4.49,
      barcode: '035000510892',
      defaultCode: 'CG-5OZ',
      category: 'Dental',
      copies: 2,
    );
    final out = Tspl.compose(m);
    expect(out, contains('SIZE 48 mm,25 mm'));
    // UPC-A declared (not EAN13), bars without printer digits ...
    expect(out, contains('"UPCA"'));
    expect(out, contains('"035000510892"'));
    expect(out, contains(',0,0,2,2,'));
    // ... digits as separate centered micro text instead.
    expect(out, contains('"1",0,1,1,"035000510892"'));
    expect(out, contains('PRINT 2'));
    expect(out, isNot(contains('"oz"')));
    // Full name across two uppercase lines, never mid-truncated.
    expect(out, contains('COLGATE - CAVITY PROTECTION'));
    expect(out, contains('TOOTHPASTE, 5 OZ'));
    // Three-part hero lockup: small $, font-5 int, raised cents.
    expect(out, contains('"3",0,1,1,"\$"'));
    expect(out, contains('"5",0,1,1,"4"'));
    expect(out, contains('"3",0,1,1,".49"'));
    expect(out, contains('"1",0,1,1,"RETAIL"'));
    // Computed unit-price cell from parsed size qty.
    expect(out, contains('\$0.90 / OZ'));
    // Every TEXT/BARCODE y stays inside 200 dots (bottom margin kept).
    for (final mm in RegExp(r'(?:TEXT|BARCODE|BOX|BAR) (\d+),(\d+)')
        .allMatches(out)) {
      expect(int.parse(mm.group(2)!), lessThanOrEqualTo(192),
          reason: '${mm.group(0)} exceeds budget');
    }
  });

  test('type03: knockout bands, maxi bay, budget', () {
    final m = LabelModel(
      name: 'Organic Artisan Trail Mix Sweet & Salty',
      price: 4.99,
      barcode: '07824919284',
      defaultCode: 'C9-84920',
      category: 'Aisle 04-B2',
      kind: LabelKind.promo,
      wasPrice: null, // promo without payload renders as standard
    );
    // Defensive fallback first (Phase B wires the real promo composer).
    expect(m.kind, LabelKind.promo);
    expect(
        Tspl.compose(m.copyWith(kind: LabelKind.standard)),
        contains('RETAIL'));

    const r = LabelModel(
      name: 'Organic Artisan Trail Mix',
      price: 4.99,
      barcode: '07824919284',
      defaultCode: 'C9-84920',
      category: 'Aisle 04-B2',
      kind: LabelKind.rapidScan,
    );
    final out = Tspl.compose(r);
    // 11-digit base completed to UPC-A with check digit.
    expect(out, contains('"UPCA"'));
    expect(out, contains('"078249192848"'));
    // Knockout bands via REVERSE (graceful when firmware ignores it).
    expect(out, contains('REVERSE 0,0,384,30'));
    expect(out, contains('SCAN'));
    expect(out, contains('C9-84920'));
    for (final mm in RegExp(r'(?:TEXT|BARCODE|BOX|BAR) (\d+),(\d+)')
        .allMatches(out)) {
      expect(int.parse(mm.group(2)!), lessThanOrEqualTo(192),
          reason: '${mm.group(0)} exceeds budget');
    }
  });

  test('type02: knockout banner, WAS strike, NOW hero, budget', () {
    const m = LabelModel(
      name: 'Chef Artisan Roast Turkey',
      price: 7.49,
      barcode: '074829100412',
      defaultCode: '94821',
      kind: LabelKind.promo,
      wasPrice: 8.99,
      promoEnds: 'SUN 11/03',
      saveText: 'SAVE \$1.50',
    );
    final out = Tspl.compose(m);
    expect(out, contains('SPECIAL VALUE'));
    expect(out, contains('SAVE \$1.50'));
    expect(out, contains('REVERSE 0,0,384,30'));
    expect(out, contains('ENDS: SUN 11/03'));
    // Struck WAS row (text + overlay bar).
    expect(out, contains('WAS \$8.99'));
    expect(out, contains('REWARDS MEMBER'));
    expect(out, contains('"UPCA"'));
    for (final mm in RegExp(r'(?:TEXT|BARCODE|BOX|BAR) (\d+),(\d+)')
        .allMatches(out)) {
      expect(int.parse(mm.group(2)!), lessThanOrEqualTo(192),
          reason: '${mm.group(0)} exceeds budget');
    }
  });

  test('promo without payload falls back to standard', () {
    const m = LabelModel(
      name: 'Coke',
      price: 1.0,
      barcode: '1',
      kind: LabelKind.promo,
    );
    final out = Tspl.compose(m);
    expect(out, contains('RETAIL'));
    expect(out, isNot(contains('SPECIAL VALUE')));
  });

  test('barcode width table per symbology', () {
    expect(Tspl.barcodeWidthFor('035000510892', 'UPCA'), 190);
    expect(Tspl.barcodeWidthFor('6934747812005', 'EAN13'), 200);
    final wide = Tspl.barcodeWidthFor('ABC-123-LONG-SKU-999', '128');
    final narrow = Tspl.barcodeWidthFor('AB', '128');
    expect(wide, greaterThan(narrow));
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
