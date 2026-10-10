import 'package:cloud9_inventory_app/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('promo memory round-trips per product key', () async {
    expect(await SessionStore.loadPromo('b:123'), isNull);
    await SessionStore.savePromo('b:123',
        wasPrice: 8.99, promoEnds: 'SUN 11/03', saveText: 'SAVE \$1.50');
    final mem = await SessionStore.loadPromo('b:123');
    expect(mem, isNotNull);
    expect(mem!.wasPrice, 8.99);
    expect(mem.promoEnds, 'SUN 11/03');
    expect(mem.saveText, 'SAVE \$1.50');
    // Other products unaffected.
    expect(await SessionStore.loadPromo('b:999'), isNull);
    await SessionStore.clearPromo('b:123');
    expect(await SessionStore.loadPromo('b:123'), isNull);
  });

  test('corrupt promo memory loads as null, never throws', () async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('promo_bad', ['not-a-number']);
    expect(await SessionStore.loadPromo('bad'), isNull);
  });
}
