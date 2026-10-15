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

import '../i18n/lang.dart';
import 'label_model.dart';
import 'logo_raster.dart';
import 'tspl.dart';

enum PrinterStatus { idle, connecting, ready, printing, error }

/// Byte transport to the printer (Classic SPP today; UI and queue code
/// only ever see this seam).
abstract class PrinterTransport {
  Stream<PrinterStatus> get status;
  Future<void> connect(String address);
  Future<void> disconnect();
  Future<void> write(List<int> bytes);
}

enum PrinterFailure {
  noPrinter,
  bluetoothOff,
  notPermitted,
  notFound,
  unreachable,
  writeFailed,
}

/// Typed transport failure. toString() is the user-facing message
/// (localized via t()), so every existing '$e' call site — snackbars,
/// print-job rows — renders friendly text with no per-screen mapping.
class PrinterException implements Exception {
  final PrinterFailure failure;
  final String detail;
  const PrinterException(this.failure, [this.detail = '']);
  @override
  String toString() => printerUserMessage(this);
}

/// Failure → localized message. Unknown errors pass through untouched.
String printerUserMessage(Object e) {
  if (e is PrinterException) {
    switch (e.failure) {
      case PrinterFailure.noPrinter:
        return t('ptr_noprntr');
      case PrinterFailure.bluetoothOff:
        return t('ptr_btoff');
      case PrinterFailure.notPermitted:
        return t('ptr_noperm');
      case PrinterFailure.notFound:
        return Lang.instance.f('ptr_notfound', {'detail': e.detail});
      case PrinterFailure.unreachable:
        return t('ptr_unreach');
      case PrinterFailure.writeFailed:
        return Lang.instance
            .f('ptr_writefail', {'detail': e.detail});
    }
  }
  return e.toString();
}

class UnconfiguredTransport implements PrinterTransport {
  @override
  Stream<PrinterStatus> get status => Stream.value(PrinterStatus.idle);

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> connect(String address) =>
      throw const PrinterException(PrinterFailure.noPrinter);

  @override
  Future<void> write(List<int> bytes) =>
      throw const PrinterException(PrinterFailure.noPrinter);
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
    try {
      // Time-bounded like SessionStore: a wedged or unmocked prefs
      // backend must never stall app boot (see widget_test).
      final p = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      address = p.getString(_kAddress);
      darkness = (p.getInt(_kDarkness) ?? 8).clamp(4, 12);
    } catch (_) {
      // Stay unconfigured; the error surfaces when printing instead.
    }
    notifyListeners();
  }

  static const minDarkness = 4;
  static const maxDarkness = 12;

  Future<void> saveDarkness(int v) async {
    darkness = v.clamp(minDarkness, maxDarkness);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kDarkness, darkness);
    } catch (_) {
      // Persist best-effort; the in-memory value still applies.
    }
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

  Future<void> printLabels(List<LabelModel> models) =>
      _guarded(() async {
        final addr = _requireAddress();
        await _transport.connect(addr);
        // Best-effort logo: same raster the preview shows. Null (missing
        // asset, decode failure) prints text-only without shifting zones.
      List<int>? logoMono;
      var logoWidth = 0;
      try {
        final logo = await LogoRaster.bundled();
        if (logo != null) {
          logoMono = logo.mono;
          logoWidth = logo.width;
        }
      } catch (_) {}
      for (final m in models) {
        await _writeWithRetry(
            addr,
            Tspl.encode(Tspl.compose(m,
                density: darkness,
                logoMono: logoMono,
                logoWidth: logoWidth)));
      }
      // Stay connected: a per-job handshake costs seconds on SPP.
      // disconnect() happens on forgetPrinter and on dead sockets only.
      });

  /// Connectivity ticket (printer-sheet test print): printer name, MAC,
  /// one Code128. Burns minimal stock by design.
  Future<void> printTicket(String name, String mac) =>
      _guarded(() async {
        final addr = _requireAddress();
        await _transport.connect(addr);
        await _writeWithRetry(
            addr,
            Tspl.encode(Tspl.composeTicket(
                name: name, mac: mac, density: darkness)));
      });

  String _requireAddress() {
    final addr = address;
    if (addr == null || addr.isEmpty) {
      throw const PrinterException(PrinterFailure.noPrinter);
    }
    return addr;
  }

  /// One reconnect + retry covers a socket that died while idle
  /// (printer sleep, Doze). Anything else - or a second failure -
  /// fails the job into the existing retry rows.
  Future<void> _writeWithRetry(String addr, List<int> bytes) async {
    try {
      await _transport.write(bytes);
    } on PrinterException catch (e) {
      if (e.failure != PrinterFailure.writeFailed &&
          e.failure != PrinterFailure.unreachable) {
        rethrow;
      }
      await _transport.disconnect();
      await _transport.connect(addr);
      await _transport.write(bytes);
    }
  }

  Future<void> _guarded(Future<void> Function() job) async {
    while (_sending) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _sending = true;
    status = PrinterStatus.printing;
    statusMessage = null;
    notifyListeners();
    try {
      await job();
      status = PrinterStatus.ready;
      statusMessage = null;
    } catch (e) {
      status = PrinterStatus.error;
      statusMessage = printerUserMessage(e);
      rethrow;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  static const _kAddress = 'printer_address';
  static const _kDarkness = 'printer_darkness';
}
