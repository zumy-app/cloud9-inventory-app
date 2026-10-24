import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:cloud9_inventory_app/print/label_model.dart';
import 'package:cloud9_inventory_app/widgets/label_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('type01 shows title, hero price, digits, unit knockout',
      (tester) async {
    const m = LabelModel(
      name: 'Colgate - Cavity Protection Toothpaste',
      size: '5 oz',
      price: 4.49,
      barcode: '035000510892',
      category: 'Dental',
      shelfLoc: 'AISLE 04-B2',
      slot: 'MK-203D\nST-084',
      dept: '04',
      allergens: 'CONTAINS MILK',
      taxable: true,
      eachText: 'EACH',
    );
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LabelPreview(model: m))));
    expect(tester.takeException(), isNull);
    // Two-tier title: the 44-char name fits the smaller cut whole.
    expect(find.text('COLGATE - CAVITY PROTECTION TOOTHPASTE, 5 OZ'),
        findsOneWidget);
    // Three-part hero lockup + EACH word.
    expect(find.text('\$'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('.49'), findsOneWidget);
    expect(find.text('EACH'), findsOneWidget);
    // Normalized UPC-A digits + computed unit knockout + furniture.
    expect(find.text('035000510892'), findsOneWidget);
    expect(find.textContaining('\$0.90 / OZ'), findsOneWidget);
    expect(find.text('EVERYDAY RETAIL'), findsOneWidget);
    expect(find.text('DEPT 04'), findsOneWidget);
    expect(find.text('TAXABLE'), findsOneWidget);
    expect(find.text('GS1 COMPLIANT SHELF EDGE'), findsOneWidget);
    expect(find.textContaining('AISLE 04-B2'), findsOneWidget);
    expect(find.textContaining('VERIF:'), findsOneWidget);
    expect(find.text('MK-203D'), findsOneWidget);
    // Bars actually render (the reported bug class).
    expect(find.byWidgetPredicate((w) => w is bw.BarcodeWidget),
        findsOneWidget);
  });

  testWidgets('type01 hides optional zones when unset', (tester) async {
    const m = LabelModel(
      name: 'Coke',
      price: 1.0,
      barcode: '036000291452',
    );
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LabelPreview(model: m))));
    expect(tester.takeException(), isNull);
    expect(find.text('EVERYDAY RETAIL'), findsOneWidget);
    expect(find.text('GS1 COMPLIANT SHELF EDGE'), findsOneWidget);
    expect(find.text('TAXABLE'), findsNothing);
    expect(find.text('EACH'), findsNothing);
    expect(find.textContaining('DEPT'), findsNothing);
    expect(find.text('MK-203D'), findsNothing);
  });

  testWidgets('type01 compact renders bars without overflow', (tester) async {
    const m = LabelModel(
      name: 'Colgate - Cavity Protection Toothpaste',
      size: '5 oz',
      price: 4.49,
      barcode: '035000510892',
      category: 'Dental',
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 180,
                    child: LabelPreview(model: m, compact: true))))));
    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate((w) => w is bw.BarcodeWidget),
        findsOneWidget);
    expect(find.text('035000510892'), findsOneWidget);
    // Detail rows stay at full scale only.
    expect(find.text('GS1 COMPLIANT SHELF EDGE'), findsNothing);
  });

  testWidgets('rapid preview shows LOC band, title, digits', (tester) async {
    const m = LabelModel(
      name: 'Organic Artisan Trail Mix',
      price: 4.99,
      barcode: '07824919284',
      category: 'Aisle 04-B2',
      kind: LabelKind.rapidScan,
    );
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LabelPreview(model: m))));
    expect(find.textContaining('LOC: AISLE 04-B2'), findsOneWidget);
    expect(find.textContaining('ORGANIC ARTISAN TRAIL MIX'),
        findsOneWidget);
    expect(find.text('078249192848'), findsOneWidget);
  });

  testWidgets('promo preview shows banner, WAS strike, NOW hero',
      (tester) async {
    const m = LabelModel(
      name: 'Chef Artisan Roast Turkey',
      price: 7.49,
      barcode: '074829100412',
      kind: LabelKind.promo,
      wasPrice: 8.99,
      promoEnds: 'SUN 11/03',
      saveText: 'SAVE \$1.50',
    );
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LabelPreview(model: m))));
    expect(find.text('SPECIAL VALUE'), findsOneWidget);
    expect(find.text('SAVE \$1.50'), findsOneWidget);
    expect(find.textContaining('WAS \$8.99'), findsOneWidget);
    expect(find.text('NOW'), findsOneWidget);
    expect(find.text('REWARDS MEMBER'), findsOneWidget);
  });

  testWidgets('preview shows ADD BARCODE placeholder when codeless',
      (tester) async {
    const m = LabelModel(name: 'Bulk Candy', price: 1.5, barcode: '');
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LabelPreview(model: m))));
    expect(tester.takeException(), isNull);
    expect(find.text('ADD BARCODE'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is bw.BarcodeWidget),
        findsNothing);
  });
}
