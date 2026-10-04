// Label batch tab: list, copies stepper, clear, Share TSV.
library;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../batch_store.dart';

class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  @override
  void initState() {
    super.initState();
    BatchStore.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    BatchStore.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _share() async {
    final tsv = BatchStore.instance.toTsv();
    final params = ShareParams(text: tsv, subject: 'cloud9-labels.tsv');
    await SharePlus.instance.share(params);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Shared TSV — run gen-label-pngs.js on the PC')));
  }

  @override
  Widget build(BuildContext context) {
    final lines = BatchStore.instance.lines;
    return Scaffold(
      appBar: AppBar(
        title: Text('Labels (${BatchStore.instance.totalCopies})'),
        actions: [
          if (lines.isNotEmpty)
            TextButton(
              onPressed: () => BatchStore.instance.clear(),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: lines.isEmpty
          ? const Center(
              child: Text('Empty.\nScan in Receive with "+ Label" on.',
                  textAlign: TextAlign.center))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: lines.length,
                    itemBuilder: (_, i) {
                      final l = lines[i];
                      return Dismissible(
                        key: ValueKey(l.barcode),
                        direction: DismissDirection.endToStart,
                        background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(Icons.delete,
                                color: Colors.white)),
                        onDismissed: (_) =>
                            BatchStore.instance.remove(l),
                        child: ListTile(
                          title: Text(l.name),
                          subtitle: Text(
                              '${l.barcode}  •  \$${l.price.toStringAsFixed(2)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove),
                                onPressed: () =>
                                    BatchStore.instance.dec(l),
                              ),
                              Text('${l.copies}',
                                  style: const TextStyle(fontSize: 18)),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () =>
                                    BatchStore.instance.inc(l),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.share),
                      label: const Text('Share TSV for PC printing',
                          style: TextStyle(fontSize: 16)),
                      onPressed: _share,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
