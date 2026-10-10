import 'package:cloud9_inventory_app/print/label_model.dart';
import 'package:cloud9_inventory_app/widgets/label_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('type01 shows full name, hero price, digits, unit cell',
      (tester) async {
    const m = LabelModel(
      name: 'Colgate - Cavity Protection Toothpaste',
      size: '5 oz',
      price: 4.49,
      barcode: '035000510892',
      category: 'Dental',
    );
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LabelPreview(model: m))));
    // Full name, uppercased, never truncated (no ellipsis widgets).
    expect(find.textContaining('COLGATE - CAVITY PROTECTION'),
        findsOneWidget);
    expect(find.textContaining('TOOTHPASTE, 5 OZ'), findsOneWidget);
    // Three-part hero lockup.
    expect(find.text('\$'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('.49'), findsOneWidget);
    // Normalized UPC-A digits + computed unit cell + chip.
    expect(find.text('035000510892'), findsOneWidget);
    expect(find.textContaining('\$0.90 / OZ'), findsOneWidget);
    expect(find.text('RETAIL'), findsOneWidget);
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

  testWidgets('preview shows NO BARCODE placeholder when codeless',
      (tester) async {
    const m = LabelModel(name: 'Bulk Candy', price: 1.5, barcode: '');
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LabelPreview(model: m))));
    expect(find.text('NO BARCODE'), findsOneWidget);
  });
}
