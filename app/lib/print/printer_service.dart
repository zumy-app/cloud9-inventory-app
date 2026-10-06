// Printer plumbing for Bluetooth label printing.
//
// Transport (Classic SPP vs BLE) is decided by the Phase-0 hardware spike
// (docs/05-LABEL-PRINTING.md). Until a transport is plugged in,
// writes fail with an actionable message and the UI routes to pairing
// setup instead of crashing. No app behavior changes before then.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'label_model.dart';
import 'tspl.dart';

enum PrinterStatus { idle, connecting, ready, printing, error }

/// Byte transport to the printer. Implemented by the spike winner
/// (SPP serial or BLE GATT); UI and queue code only sees this.
abstract class PrinterTransport {
  Stream<PrinterStatus> get status;
  Future<void> connect(String address);
  Future<void> disconnect();
  Future<void> write(List<int> bytes);
}

class UnconfiguredTransport implements PrinterTransport {
  @override
  Stream<PrinterStatus> get status => Stream.value(PrinterStatus.idle);

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> connect(String address) => throw StateError(_msg);

  @override
  Future<void> write(List<int> bytes) => throw StateError(_msg);

  static const _msg =
      'No printer connected. Pair a label printer first (Labels tab).';
}

class PrinterService extends ChangeNotifier {
  PrinterService._(this._transport);
  static final PrinterService instance =
      PrinterService._(UnconfiguredTransport());

  PrinterTransport _transport;
  PrinterStatus status = PrinterStatus.idle;
  String? statusMessage;
  String? address;
  int darkness = 8;

  /// Swap in the real transport (called once, post-spike).
  void useTransport(PrinterTransport t) {
    _transport = t;
    notifyListeners();
  }

  Future<void> loadSettings() async {
    final p = await SharedPreferences.getInstance();
    address = p.getString(_kAddress);
    darkness = p.getInt(_kDarkness) ?? 8;
    notifyListeners();
  }

  Future<void> savePrinter(String addr) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAddress, addr);
    address = addr;
    notifyListeners();
  }

  Future<void> forgetPrinter() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kAddress);
    address = null;
    await _transport.disconnect();
    status = PrinterStatus.idle;
    notifyListeners();
  }

  bool get isConfigured => _transport is! UnconfiguredTransport;

  bool _sending = false;

  /// Compose + send one label. Single-flight: concurrent calls queue
  /// behind the in-flight job instead of interleaving bytes.
  Future<void> printLabel(LabelModel m) => printLabels([m]);

  Future<void> printLabels(List<LabelModel> models) async {
    while (_sending) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _sending = true;
    status = PrinterStatus.printing;
    notifyListeners();
    try {
      final addr = address;
      if (addr == null || addr.isEmpty) {
        throw StateError(UnconfiguredTransport._msg);
      }
      await _transport.connect(addr);
      for (final m in models) {
        await _transport.write(
            Tspl.encode(Tspl.compose(m, density: darkness)));
      }
      await _transport.disconnect();
      status = PrinterStatus.ready;
      statusMessage = null;
    } catch (e) {
      status = PrinterStatus.error;
      statusMessage = e.toString();
      rethrow;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  static const _kAddress = 'printer_address';
  static const _kDarkness = 'printer_darkness';
}
