// Phase-0 spike entrypoint — DELETE after the go/no-go.
// Lists bonded devices, connects to the PM-241Z (or SPIKE_MAC), sends a
// TSPL hello + one full Type 01 with logo, then exits.
//
// Run: flutter run -t lib/spike_bt.dart -d <pixel>
//      [--dart-define SPIKE_MAC=AA:BB:CC:DD:EE:FF]
// Printer must be powered on and OS-paired first.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'print/label_model.dart';
import 'print/logo_raster.dart';
import 'print/spp_transport.dart';
import 'print/tspl.dart';

const _mac = String.fromEnvironment('SPIKE_MAC', defaultValue: '');

// ignore: avoid_print
void say(String s) => print('[SPIKE] $s');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    var perm = await Permission.bluetoothConnect.status;
    if (!perm.isGranted) perm = await Permission.bluetoothConnect.request();
    say('bluetoothConnect=$perm');
    if (!perm.isGranted) throw StateError('permission denied');
    say('bluetoothEnabled='
        '${await PrintBluetoothThermal.bluetoothEnabled}');
    final paired = await PrintBluetoothThermal.pairedBluetooths;
    if (paired.isEmpty) {
      say('bonded: (none visible)');
    }
    for (final b in paired) {
      say('bonded: ${b.name} [${b.macAdress}]');
    }
    var mac = _mac;
    if (mac.isEmpty) {
      mac = paired
          .where((b) => b.name.toUpperCase().contains('PM-241'))
          .map((b) => b.macAdress)
          .first;
    }
    say('target=$mac');
    final t = SppTransport();
    await t.connect(mac);
    say('connected');
    await t.write(Tspl.encode(
        'SIZE 48 mm,25 mm\nGAP 3 mm,0\nCLS\nTEXT 10,10,"2",0,1,1,"C9 SPIKE OK"\nPRINT 1\n'));
    say('hello sent');
    List<int>? mono;
    var lw = 0;
    try {
      final r = await LogoRaster.bundled();
      if (r != null) {
        mono = r.mono;
        lw = r.width;
      }
      say('logo raster: ${lw}x${mono?.length ?? 0}');
    } catch (e) {
      say('logo skipped: $e');
    }
    const m = LabelModel(
      name: 'C9 Artisan Roast Turkey Club Wrap',
      size: '12.4 oz',
      price: 7.49,
      barcode: '048192730194',
      category: 'Deli',
      shelfLoc: 'AISLE 04-B2',
      dept: '04',
      eachText: 'EACH',
    );
    await t.write(
        Tspl.encode(Tspl.compose(m, logoMono: mono, logoWidth: lw)));
    say('type01 sent');
    await t.disconnect();
    say('DONE-OK');
  } catch (e) {
    say('DONE-FAIL: $e');
  }
  await Future.delayed(const Duration(seconds: 5));
  exit(0);
}
