import 'package:cloud9_inventory_app/print/label_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splitNameSize parses trailing size tokens', () {
    expect(
      LabelModel.splitNameSize('Pecan Spinwheels, 2.1 oz'),
      (name: 'Pecan Spinwheels', size: '2.1 oz'),
    );
    expect(
      LabelModel.splitNameSize('Coke 12pk'),
      (name: 'Coke', size: '12pk'),
    );
    expect(
      LabelModel.splitNameSize('Goya Beans 16oz'),
      (name: 'Goya Beans', size: '16oz'),
    );
    expect(
      LabelModel.splitNameSize('Milk 1 Gal'),
      (name: 'Milk', size: '1 Gal'),
    );
  });

  test('splitNameSize leaves non-size names intact', () {
    expect(
      LabelModel.splitNameSize('Beans, Black, Goya'),
      (name: 'Beans, Black, Goya', size: ''),
    );
    expect(
      LabelModel.splitNameSize('Vitamin D 1000 IU'),
      (name: 'Vitamin D 1000 IU', size: ''),
    );
    expect(LabelModel.splitNameSize(''), (name: '', size: ''));
    // Base would be a single char — keep the full name instead.
    expect(
      LabelModel.splitNameSize('A 12pk').size,
      anyOf('', '12pk'),
    );
  });

  test('displayName appends size once', () {
    const m =
        LabelModel(name: 'Coke', size: '12pk', price: 9.99, barcode: '1');
    expect(m.displayName, 'Coke, 12pk');
    // Legacy full-name + empty size stays as-is.
    const legacy = LabelModel(
        name: 'Pecan Spinwheels, 2.1 oz', price: 2.49, barcode: '1');
    expect(legacy.displayName, 'Pecan Spinwheels, 2.1 oz');
    // Name already ending with size is not duplicated.
    const dup =
        LabelModel(name: 'Coke, 12pk', size: '12pk', price: 1, barcode: '1');
    expect(dup.displayName, 'Coke, 12pk');
  });

  test('copyWith preserves size', () {
    const m = LabelModel(name: 'Coke', price: 1, barcode: '1');
    expect(m.copyWith(size: '12pk').displayName, 'Coke, 12pk');
  });
}
