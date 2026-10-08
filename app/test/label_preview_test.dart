import 'package:cloud9_inventory_app/print/label_model.dart';
import 'package:cloud9_inventory_app/widgets/label_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('preview shows name+size, big price and code',
      (tester) async {
    const m = LabelModel(
        name: 'Coke', size: '12pk', price: 9.99, barcode: '810120476612');
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LabelPreview(model: m))));
    expect(find.text('Coke, 12pk'), findsOneWidget);
    expect(find.text('\$9.99'), findsOneWidget);
    expect(find.text('810120476612'), findsOneWidget);
  });

  testWidgets('preview shows NO BARCODE placeholder when codeless',
      (tester) async {
    const m = LabelModel(name: 'Bulk Candy', price: 1.5, barcode: '');
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LabelPreview(model: m))));
    expect(find.text('NO BARCODE'), findsOneWidget);
  });
}
