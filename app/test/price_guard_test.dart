import 'package:cloud9_inventory_app/price_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('below cost always needs reason', () {
    expect(
        PriceGuard.needsReason(newPrice: 5, cost: 10, oldPrice: 10), isTrue);
  });

  test('large delta needs reason', () {
    expect(
        PriceGuard.needsReason(newPrice: 13, cost: 5, oldPrice: 10), isTrue);
    expect(
        PriceGuard.needsReason(newPrice: 7, cost: 5, oldPrice: 10), isTrue);
  });

  test('small delta needs no reason', () {
    expect(
        PriceGuard.needsReason(newPrice: 11, cost: 5, oldPrice: 10), isFalse);
  });

  test('zero old price skips delta check', () {
    expect(PriceGuard.needsReason(newPrice: 9, cost: 5, oldPrice: 0), isFalse);
  });
}
