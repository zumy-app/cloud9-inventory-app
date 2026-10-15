// Classic SPP transport for the PM-241Z label printer.
//
// Plumbs PrinterTransport over bonded-device RFCOMM: OS pairing stays in
// Settings (no discovery scan, no location permission); the app opens
// the socket by MAC. Plugin failure modes collapse to typed
// [PrinterException]s — raw strings never reach the UI (message table
// in docs/07 §6 lives with the callers).
library;

import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'printer_service.dart';

class SppTransport implements PrinterTransport {
  static const _connectTimeout = Duration(seconds: 10);

  final StreamController<PrinterStatus> _status =
      StreamController<PrinterStatus>.broadcast();

  bool _connected = false;
  String? _address;

  @override
  Stream<PrinterStatus> get status => _status.stream;

  bool get isConnected => _connected;

  void _emit(PrinterStatus s) {
    if (!_status.isClosed) _status.add(s);
  }

  /// Guard chain shared by list/connect: permission → radio.
  Future<void> _guard() async {
    final perm = await Permission.bluetoothConnect.status;
    if (!perm.isGranted) {
      throw const PrinterException(PrinterFailure.notPermitted);
    }
    final on = await PrintBluetoothThermal.bluetoothEnabled;
    if (!on) throw const PrinterException(PrinterFailure.bluetoothOff);
  }

  /// Bonded devices (name + MAC). Empty when permission/radio blocks —
  /// callers treat empty as "none visible", not as an error.
  Future<List<({String name, String mac})>> bonded() async {
    await _guard();
    final paired = await PrintBluetoothThermal.pairedBluetooths;
    return [
      for (final b in paired) (name: b.name, mac: b.macAdress),
    ];
  }

  @override
  Future<void> connect(String address) async {
    final mac = address.trim();
    if (mac.isEmpty) {
      throw const PrinterException(PrinterFailure.noPrinter);
    }
    await _guard();
    // Fail fast with a named error when the radio sees bonds but not
    // ours (e.g. unpaired since save). An empty list means the query
    // itself was inconclusive — let connect() decide, not us.
    try {
      final paired = await PrintBluetoothThermal.pairedBluetooths;
      if (paired.isNotEmpty &&
          !paired.any((b) => b.macAdress == mac)) {
        throw const PrinterException(PrinterFailure.notFound);
      }
    } on PrinterException {
      rethrow;
    } catch (_) {
      // Inconclusive listing — attempt the connection anyway.
    }
    _emit(PrinterStatus.connecting);
    _connected = false;
    _address = mac;
    try {
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac)
          .timeout(_connectTimeout);
      if (!ok) throw const PrinterException(PrinterFailure.unreachable);
      _connected = true;
    } on PrinterException {
      rethrow;
    } on TimeoutException {
      throw const PrinterException(PrinterFailure.unreachable, 'timeout');
    } catch (e) {
      throw PrinterException(PrinterFailure.unreachable, '$e');
    }
  }

  Future<void> _ensureConnected() async {
    if (_connected) {
      try {
        if (await PrintBluetoothThermal.connectionStatus) return;
      } catch (_) {}
      _connected = false;
    }
    final addr = _address;
    if (addr == null || addr.isEmpty) {
      throw const PrinterException(PrinterFailure.noPrinter);
    }
    await connect(addr);
  }

  @override
  Future<void> write(List<int> bytes) async {
    await _ensureConnected();
    try {
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      if (!ok) throw const PrinterException(PrinterFailure.writeFailed);
    } catch (e) {
      _connected = false;
      if (e is PrinterException) rethrow;
      throw PrinterException(PrinterFailure.writeFailed, '$e');
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _address = null;
    try {
      await PrintBluetoothThermal.disconnect;
    } catch (_) {}
  }
}
