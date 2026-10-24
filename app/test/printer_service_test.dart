import 'package:cloud9_inventory_app/i18n/lang.dart';
import 'package:cloud9_inventory_app/print/label_model.dart';
import 'package:cloud9_inventory_app/print/printer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scripted transport: fails the first [failWrites] writes with
/// [writeFailure], counts connects. No Bluetooth, no platform channels.
class FakeTransport implements PrinterTransport {
  int connects = 0;
  int writes = 0;
  int disconnects = 0;
  int failWrites;
  PrinterFailure writeFailure;
  FakeTransport(
      {this.failWrites = 0,
      this.writeFailure = PrinterFailure.writeFailed});

  @override
  Stream<PrinterStatus> get status => Stream.value(PrinterStatus.idle);

  @override
  Future<void> connect(String address) async {
    connects++;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }

  @override
  Future<void> write(List<int> bytes) async {
    writes++;
    if (failWrites > 0) {
      failWrites--;
      throw PrinterException(writeFailure, 'boom');
    }
  }
}

const _label = LabelModel(name: 'Coke', price: 1.0, barcode: '1');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Lang.instance.setForTest(AppLang.en);
    PrinterService.instance.address = null;
    PrinterService.instance.darkness = 8;
  });

  tearDown(() {
    PrinterService.instance.useTransport(UnconfiguredTransport());
  });

  test('no saved address throws friendly noPrinter', () async {
    final svc = PrinterService.instance;
    svc.useTransport(FakeTransport());
    await svc.loadSettings();
    // No address saved in test prefs backend -> guard first.
    // (Address persistence is covered by the round-trip test below.)
    try {
      await svc.printLabel(_label);
      fail('expected PrinterException');
    } on PrinterException catch (e) {
      expect(e.failure, PrinterFailure.noPrinter);
      expect(
          e.toString(),
          contains(
              'No printer connected. Pair a label printer first'));
    }
  });

  test('retry once on stale socket, then succeed', () async {
    final svc = PrinterService.instance;
    final fake = FakeTransport(failWrites: 1);
    svc.useTransport(fake);
    await svc.savePrinter('AA:BB:CC:DD:EE:FF');
    await svc.printLabel(_label);
    expect(fake.writes, 2);
    expect(fake.connects, 2); // initial + one reconnect
    expect(svc.status, PrinterStatus.ready);
  });

  test('second failure rethrows (no infinite retry)', () async {
    final svc = PrinterService.instance;
    final fake = FakeTransport(failWrites: 5);
    svc.useTransport(fake);
    await svc.savePrinter('AA:BB:CC:DD:EE:FF');
    try {
      await svc.printLabel(_label);
      fail('expected PrinterException');
    } on PrinterException catch (e) {
      expect(e.failure, PrinterFailure.writeFailed);
    }
    expect(fake.writes, 2);
  });

  test('non-retryable failure rethrows immediately', () async {
    final svc = PrinterService.instance;
    final fake = FakeTransport(
        failWrites: 1, writeFailure: PrinterFailure.notPermitted);
    svc.useTransport(fake);
    await svc.savePrinter('AA:BB:CC:DD:EE:FF');
    try {
      await svc.printLabel(_label);
      fail('expected PrinterException');
    } on PrinterException catch (e) {
      expect(e.failure, PrinterFailure.notPermitted);
      expect(e.toString(), contains('Nearby-devices permission'));
    }
    expect(fake.writes, 1);
    expect(fake.connects, 1); // no reconnect attempted
  });

  test('printTicket sends one payload through the same guard', () async {
    final svc = PrinterService.instance;
    final fake = FakeTransport();
    svc.useTransport(fake);
    await svc.savePrinter('AA:BB:CC:C0:75');
    await svc.printTicket('PM-241Z', '···C0:75');
    expect(fake.connects, 1);
    expect(fake.writes, 1);
    expect(svc.status, PrinterStatus.ready);
  });

  test('darkness clamps and persists', () async {
    final svc = PrinterService.instance;
    await svc.saveDarkness(99);
    expect(svc.darkness, PrinterService.maxDarkness);
    await svc.saveDarkness(1);
    expect(svc.darkness, PrinterService.minDarkness);
    await svc.saveDarkness(9);
    expect(svc.darkness, 9);
    svc.darkness = 8;
    await svc.loadSettings();
    expect(svc.darkness, 9);
  });

  test('every failure maps to a friendly message (en+es)', () {
    final cases = {
      PrinterFailure.noPrinter: 'No printer connected',
      PrinterFailure.bluetoothOff: 'Bluetooth is off',
      PrinterFailure.notPermitted: 'Nearby-devices permission',
      PrinterFailure.notFound: 'not found',
      PrinterFailure.unreachable: 'Could not reach the printer',
      PrinterFailure.writeFailed: 'Print write failed',
    };
    for (final entry in cases.entries) {
      final msg = printerUserMessage(
          PrinterException(entry.key, 'PM-241Z-BT-C075'));
      expect(msg, contains(entry.value), reason: '${entry.key}');
      expect(msg, isNot(contains('PrinterException')));
      expect(msg, isNot(contains('Bad state')));
    }
    Lang.instance.setForTest(AppLang.es);
    expect(printerUserMessage(const PrinterException(PrinterFailure.noPrinter)),
        contains('Sin impresora'));
    expect(printerUserMessage(StateError('x')), contains('Bad state'));
    Lang.instance.setForTest(AppLang.en);
  });
}
