// Print-job runner: one physical label per row (copies expanded),
// per-label status, pause/resume/cancel, retry-failed.
// Transport errors (jam, out-of-paper, disconnect, timeout surface as
// exceptions from PrinterTransport.write) mark the row failed and
// auto-pause the job; nothing after the failure is skipped silently.
library;

import 'package:flutter/foundation.dart';

import 'label_model.dart';
import 'printer_service.dart';

enum LabelPrintStatus { queued, printing, done, failed, cancelled }

class JobLabel {
  final LabelModel model;
  LabelPrintStatus status;
  String? error;
  JobLabel(this.model)
      : status = LabelPrintStatus.queued,
        error = null;
}

class PrintJobRunner extends ChangeNotifier {
  final Future<void> Function(LabelModel m) _printOne;
  final List<JobLabel> labels;
  int currentIndex = -1;
  bool _paused = false;
  bool _cancelled = false;
  bool _running = false;

  PrintJobRunner(
    List<LabelModel> models, {
    Future<void> Function(LabelModel m)? printOne,
  })  : _printOne =
            printOne ?? ((m) => PrinterService.instance.printLabel(m)),
        labels = [
          for (final m in models)
            for (var i = 0; i < (m.copies < 1 ? 1 : m.copies); i++)
              JobLabel(m.copyWith(copies: 1)),
        ];

  bool get isRunning => _running;
  bool get isPaused => _paused;
  int get doneCount =>
      labels.where((l) => l.status == LabelPrintStatus.done).length;
  int get failedCount =>
      labels.where((l) => l.status == LabelPrintStatus.failed).length;
  bool get isFinished => labels.every((l) =>
      l.status == LabelPrintStatus.done ||
      l.status == LabelPrintStatus.failed ||
      l.status == LabelPrintStatus.cancelled);

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _cancelled = false;
    notifyListeners();
    await _runFrom(0);
    _running = false;
    notifyListeners();
  }

  Future<void> _runFrom(int start) async {
    for (var i = start; i < labels.length; i++) {
      if (_cancelled) {
        for (var j = i; j < labels.length; j++) {
          if (labels[j].status == LabelPrintStatus.queued) {
            labels[j].status = LabelPrintStatus.cancelled;
          }
        }
        notifyListeners();
        return;
      }
      while (_paused && !_cancelled) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
      if (_cancelled) {
        for (var j = i; j < labels.length; j++) {
          if (labels[j].status == LabelPrintStatus.queued) {
            labels[j].status = LabelPrintStatus.cancelled;
          }
        }
        notifyListeners();
        return;
      }
      final job = labels[i];
      if (job.status == LabelPrintStatus.done) continue;
      currentIndex = i;
      job.status = LabelPrintStatus.printing;
      job.error = null;
      notifyListeners();
      try {
        await _printOne(job.model);
        job.status = LabelPrintStatus.done;
      } catch (e) {
        job.status = LabelPrintStatus.failed;
        job.error = e.toString();
        _paused = true; // auto-pause on first failure (jam/paper/BT drop)
      }
      notifyListeners();
      if (job.status == LabelPrintStatus.failed) {
        // Stop the pass here; resume()/retryFailed() continue after i.
        // Remaining queued rows stay queued (still retryable).
        return;
      }
    }
  }

  void pause() {
    _paused = true;
    notifyListeners();
  }

  Future<void> resume() async {
    if (!_paused && _running) return;
    _paused = false;
    if (_running) {
      notifyListeners();
      return;
    }
    _running = true;
    notifyListeners();
    final next = labels.indexWhere((l) =>
        l.status == LabelPrintStatus.queued ||
        l.status == LabelPrintStatus.failed);
    if (next >= 0) {
      // Reset failed head to queued so the pass retries it once.
      if (labels[next].status == LabelPrintStatus.failed) {
        labels[next].status = LabelPrintStatus.queued;
        labels[next].error = null;
      }
      await _runFrom(next);
    }
    _running = false;
    notifyListeners();
  }

  void cancel() {
    _cancelled = true;
    _paused = false;
    notifyListeners();
  }

  /// Re-queue failed rows (or a manual subset) and run them.
  Future<void> retryFailed([Set<int>? only]) async {
    final targets = <int>[];
    for (var i = 0; i < labels.length; i++) {
      if (labels[i].status != LabelPrintStatus.failed) continue;
      if (only != null && !only.contains(i)) continue;
      targets.add(i);
    }
    if (targets.isEmpty || _running) return;
    _cancelled = false;
    _paused = false;
    _running = true;
    notifyListeners();
    for (final i in targets) {
      while (_paused && !_cancelled) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
      if (_cancelled) break;
      currentIndex = i;
      labels[i].status = LabelPrintStatus.printing;
      labels[i].error = null;
      notifyListeners();
      try {
        await _printOne(labels[i].model);
        labels[i].status = LabelPrintStatus.done;
      } catch (e) {
        labels[i].status = LabelPrintStatus.failed;
        labels[i].error = e.toString();
        _paused = true;
        notifyListeners();
        break;
      }
      notifyListeners();
    }
    _running = false;
    notifyListeners();
  }
}
