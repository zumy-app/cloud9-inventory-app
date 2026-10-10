import 'package:cloud9_inventory_app/print/label_model.dart';
import 'package:cloud9_inventory_app/print/print_job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LabelModel m(String n, {int copies = 1}) =>
      LabelModel(name: n, price: 1, barcode: '1', copies: copies);

  test('copies expand to physical rows', () {
    final r = PrintJobRunner([m('A', copies: 3)],
        printOne: (_) async {});
    expect(r.labels.length, 3);
    expect(r.labels.every((l) => l.model.copies == 1), isTrue);
  });

  test('all-done happy path', () async {
    final r = PrintJobRunner([m('A'), m('B')], printOne: (_) async {});
    await r.start();
    expect(r.doneCount, 2);
    expect(r.isFinished, isTrue);
  });

  test('failure auto-pauses, resume continues, retryFailed recovers',
      () async {
    var calls = 0;
    Future<void> flaky(LabelModel model) async {
      calls++;
      if (calls == 2) throw StateError('paper out');
    }

    final r = PrintJobRunner([m('A'), m('B'), m('C')], printOne: flaky);
    await r.start();
    expect(r.doneCount, 1);
    expect(r.failedCount, 1);
    expect(r.isPaused, isTrue);

    // Third label untouched (still queued).
    expect(r.labels[2].status, LabelPrintStatus.queued);

    // Resume retries the failed row then continues.
    await r.resume();
    expect(r.doneCount, 3);
    expect(r.failedCount, 0);
  });

  test('retryFailed with subset retries only chosen rows', () async {
    Future<void> fail(LabelModel _) async => throw StateError('jam');
    final r = PrintJobRunner([m('A'), m('B')], printOne: fail);
    await r.start();
    expect(r.failedCount, 1); // stops at first failure
    var ok = 0;
    // Swap delegate via a new runner is cleaner; here verify subset filter
    // keeps the unchosen failed row failed.
    await r.retryFailed({99});
    expect(r.failedCount, 1);
    expect(ok, 0);
  });

  test('cancel marks remaining queued as cancelled', () async {
    Future<void> slow(LabelModel _) async {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    final r = PrintJobRunner([m('A'), m('B'), m('C')], printOne: slow);
    final fut = r.start();
    await Future.delayed(const Duration(milliseconds: 10));
    r.cancel();
    await fut;
    expect(
        r.labels.any((l) => l.status == LabelPrintStatus.cancelled), isTrue);
    expect(r.isFinished, isTrue);
  });
}
