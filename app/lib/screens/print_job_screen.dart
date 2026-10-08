// Print-job status screen: per-label preview + status, pause/resume,
// cancel, retry-failed (all or manually selected). One physical label
// per row (copies expanded by PrintJobRunner).
library;

import 'package:flutter/material.dart';

import '../print/label_model.dart';
import '../print/print_job.dart';
import '../widgets/label_preview.dart';

class PrintJobScreen extends StatefulWidget {
  final List<LabelModel> models;
  final String title;
  const PrintJobScreen({super.key, required this.models, this.title = 'Printing'});

  @override
  State<PrintJobScreen> createState() => _PrintJobScreenState();
}

class _PrintJobScreenState extends State<PrintJobScreen> {
  late final PrintJobRunner _job;
  final Set<int> _retrySel = {};

  @override
  void initState() {
    super.initState();
    _job = PrintJobRunner(widget.models);
    _job.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _job.start());
  }

  @override
  void dispose() {
    _job.removeListener(_refresh);
    _job.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Widget _statusIcon(LabelPrintStatus s, bool isCurrent) {
    switch (s) {
      case LabelPrintStatus.done:
        return const Icon(Icons.check_circle, color: Colors.green);
      case LabelPrintStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
      case LabelPrintStatus.printing:
        return const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2));
      case LabelPrintStatus.cancelled:
        return const Icon(Icons.cancel, color: Colors.grey);
      case LabelPrintStatus.queued:
        return Icon(Icons.hourglass_empty,
            color: isCurrent ? Colors.blue : Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _job.labels.length;
    final done = _job.doneCount;
    final failed = _job.failedCount;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} ($done/$total)'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () {
            if (_job.isRunning) _job.cancel();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: total == 0 ? 0 : done / total),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _job.isFinished
                        ? 'Done: $done printed${failed > 0 ? ', $failed failed' : ''}'
                        : _job.isPaused
                            ? 'Paused${failed > 0 ? ' — $failed failed (reload paper / check printer)' : ''}'
                            : 'Printing… $done/$total',
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                if (!_job.isPaused && _job.isRunning)
                  OutlinedButton(
                      onPressed: _job.pause, child: const Text('Pause')),
                if (_job.isPaused && !_job.isFinished)
                  FilledButton(
                      onPressed: () => _job.resume(),
                      child: const Text('Resume')),
                if (!_job.isFinished)
                  TextButton(
                      onPressed: () => _job.cancel(),
                      child: const Text('Cancel')),
                if (failed > 0)
                  FilledButton.tonal(
                    onPressed: _job.isRunning
                        ? null
                        : () => _job.retryFailed(
                            _retrySel.isEmpty ? null : Set.of(_retrySel)),
                    child: Text(_retrySel.isEmpty
                        ? 'Retry failed ($failed)'
                        : 'Retry selected (${_retrySel.length})'),
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: total == 0
                ? const Center(child: Text('Nothing to print.'))
                : ListView.builder(
                    itemCount: total,
                    itemBuilder: (_, i) {
                      final jl = _job.labels[i];
                      final isCurrent = i == _job.currentIndex &&
                          jl.status == LabelPrintStatus.printing;
                      final selectable =
                          jl.status == LabelPrintStatus.failed;
                      return Card(
                        color: isCurrent ? Colors.blue.shade50 : null,
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (selectable)
                                Checkbox(
                                  value: _retrySel.contains(i),
                                  onChanged: (_) => setState(() {
                                    if (_retrySel.contains(i)) {
                                      _retrySel.remove(i);
                                    } else {
                                      _retrySel.add(i);
                                    }
                                  }),
                                ),
                              SizedBox(
                                width: 140,
                                child: LabelPreview(
                                    model: jl.model, compact: true),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(jl.model.displayName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(
                                        '${jl.model.code.isEmpty ? 'NO BARCODE' : jl.model.code} • ${jl.model.priceText}'),
                                    if (jl.error != null)
                                      Text(jl.error!,
                                          style: const TextStyle(
                                              color: Colors.red,
                                              fontSize: 12)),
                                    Text(jl.status.name,
                                        style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                              _statusIcon(jl.status, isCurrent),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
