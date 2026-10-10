import 'dart:convert';

import 'package:cloud9_inventory_app/i18n/lang.dart';
import 'package:cloud9_inventory_app/price_guard.dart';
import 'package:cloud9_inventory_app/screens/add_item.dart';
import 'package:cloud9_inventory_app/screens/inventory_home.dart';
import 'package:cloud9_inventory_app/screens/login.dart';
import 'package:cloud9_inventory_app/odoo_client.dart';
import 'package:cloud9_inventory_app/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance =
        TestFlutterSecureStoragePlatform({});
    Lang.instance.setForTest(AppLang.en);
  });

  test('en/es key parity (no half-translated screen)', () {
    final missing =
        Lang.enKeys.difference(Lang.esKeys).union(Lang.esKeys.difference(Lang.enKeys));
    expect(missing, isEmpty, reason: 'Untranslated keys: $missing');
  });

  test('spanish translations are real (not english copies)', () {
    Lang.instance.setForTest(AppLang.es);
    expect(t('login_signin'), 'Iniciar sesión');
    expect(t('nav_labels'), 'Etiquetas');
    expect(t('add_submit'), 'Agregar al inventario');
    expect(t('recv_setcount'), 'Fijar conteo');
    expect(Lang.instance.q('batch_sel_one', 'batch_sel_other', 1),
        '1 seleccionado');
    expect(Lang.instance.q('batch_sel_one', 'batch_sel_other', 5),
        '5 seleccionados');
  });

  test('unknown key falls back to english, then key', () {
    expect(t('nav_inventory'), 'Inventory');
    expect(t('definitely_missing_key_xyz'), 'definitely_missing_key_xyz');
  });

  test('price guard messages follow UI language', () {
    expect(
        PriceGuard.describe(newPrice: 1, cost: 2, oldPrice: 2),
        'Below cost — reason required.');
    Lang.instance.setForTest(AppLang.es);
    expect(
        PriceGuard.describe(newPrice: 1, cost: 2, oldPrice: 2),
        'Bajo costo — motivo obligatorio.');
  });

  test('language choice persists per device', () async {
    expect(await SessionStore.loadLang(), isNull);
    await Lang.instance.load();
    expect(Lang.instance.current, AppLang.en); // device locale in tests is en
    await Lang.instance.set(AppLang.es);
    expect(await SessionStore.loadLang(), 'es');
    await Lang.instance.load();
    expect(Lang.instance.current, AppLang.es);
  });

  testWidgets('login renders spanish chrome', (tester) async {
    Lang.instance.setForTest(AppLang.es);
    final client = OdooClient(baseUrl: 'https://x');
    await tester.pumpWidget(MaterialApp(
        home: LoginScreen(client: client, onLoggedIn: () {})));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Usuario'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Español'), findsWidgets);
  });

  testWidgets('add-item form renders spanish with no overflow', (tester) async {
    Lang.instance.setForTest(AppLang.es);
    final mock = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final model = (body['params'] as Map)['model'];
      final rows = model == 'pos.category'
          ? [
              {'id': 3, 'name': 'Bebidas'}
            ]
          : [
              {'id': 10, 'name': 'Todo'}
            ];
      return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': rows}), 200);
    });
    final client = OdooClient(baseUrl: 'https://x', httpClient: mock);
    await tester.pumpWidget(MaterialApp(
        home: AddItemScreen(client: client, user: 'u')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Agregar inventario'), findsWidgets);
    expect(find.text('Sin código'), findsOneWidget);
    // Below the fold in the test viewport: assert present including
    // offstage (the form scrolls; the old Print snackbar-action is gone
    // so nothing may cover it).
    expect(find.text('Agregar al inventario', skipOffstage: false),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inventory home renders spanish tiles', (tester) async {
    Lang.instance.setForTest(AppLang.es);
    final client = OdooClient(baseUrl: 'https://x');
    await tester.pumpWidget(MaterialApp(
        home: InventoryHome(client: client, user: 'u')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('¿Qué vas a hacer?'), findsOneWidget);
    expect(find.text('Agregar inventario'), findsOneWidget);
    expect(find.text('Actualizar conteo'), findsOneWidget);
  });
}
