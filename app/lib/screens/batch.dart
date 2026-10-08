// Label collections tab: switcher, line list, copies stepper,
// preview sheet (with size edit), Share TSV, BT print-all.
library;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../batch_store.dart';
import '../label_collections.dart';
import '../odoo_client.dart';
import '../print/label_model.dart';
import '../widgets/label_preview.dart';
import 'browse.dart';
import 'print_job_screen.dart';

class BatchScreen extends StatefulWidget {
  final OdooClient client;
  final String user;
  const BatchScreen({super.key, required this.client, required this.user});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  bool _ready = false;

  /// Line-level selection for Print-selected (keys, not objects:
  /// updateSize replaces line objects).
  bool _lineSel = false;
  final Set<String> _lineKeys = {};

  static String _lineKey(CollectionLine l) => LabelCollections.keyOf(
    barcode: l.barcode,
    defaultCode: l.defaultCode,
    name: l.name,
  );

  @override
  void initState() {
    super.initState();
    LabelCollections.instance.addListener(_refresh);
    _ensureLoaded();
  }

  @override
  void dispose() {
    LabelCollections.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    // Prune selected keys that no longer exist (delete/clear/switch).
    final keys = {
      for (final l in LabelCollections.instance.activeLines) _lineKey(l),
    };
    _lineKeys.removeWhere((k) => !keys.contains(k));
    if (_lineKeys.isEmpty) _lineSel = false;
    setState(() {});
  }

  void _toggleLine(CollectionLine l) {
    setState(() {
      final k = _lineKey(l);
      if (_lineKeys.contains(k)) {
        _lineKeys.remove(k);
        if (_lineKeys.isEmpty) _lineSel = false;
      } else {
        _lineKeys.add(k);
      }
    });
  }

  /// Browse-and-pick into the pinned opener collection. The target id is
  /// captured at open; items land there even if active changes mid-pick.
  Future<void> _openPicker() async {
    final store = LabelCollections.instance;
    final target = store.active;
    if (target == null) return;
    final targetId = target.id;
    final keys = {for (final l in target.lines) _lineKey(l)};
    final res = await Navigator.of(context).push<PickResult>(
      MaterialPageRoute(
        builder: (_) => BrowseScreen(
          client: widget.client,
          user: widget.user,
          editable: false,
          title: 'Add to ${target.name}',
          pickMode: true,
          existingKeys: keys,
        ),
      ),
    );
    if (res == null || res.items.isEmpty || !mounted) return;
    final dest = store.byId(targetId) ?? store.active;
    if (dest == null) return;
    final summary = store.addAllTo(dest, res.items);
    final deleted = store.byId(targetId) == null
        ? 'Collection was deleted — '
        : '';
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${deleted}Added ${summary.added} to ${dest.name}'
          '${summary.merged > 0 ? ' (${summary.merged} already in, +1 copy)' : ''}',
        ),
        action: store.active?.id == dest.id
            ? null
            : SnackBarAction(
                label: 'View',
                onPressed: () => store.setActive(dest.id),
              ),
      ),
    );
    if (res.printNow && mounted) {
      final models = res.items
          .map(
            (p) => LabelModel(
              name: p.name,
              size: p.size,
              price: p.price,
              barcode: p.barcode,
              defaultCode: p.defaultCode,
              category: p.category,
              copies: 1,
            ),
          )
          .toList();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PrintJobScreen(models: models, title: 'Printing ${dest.name}'),
        ),
      );
    }
  }

  Future<void> _printSelected() async {
    final active = LabelCollections.instance.active;
    final models = LabelCollections.instance.activeLines
        .where((l) => _lineKeys.contains(_lineKey(l)))
        .map((l) => l.model)
        .toList();
    if (models.isEmpty || active == null) return;
    setState(() {
      _lineSel = false;
      _lineKeys.clear();
    });
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PrintJobScreen(models: models, title: 'Printing selection'),
      ),
    );
  }

  Future<void> _ensureLoaded() async {
    await LabelCollections.instance.load();
    // One-time migration from the legacy single batch.
    if (BatchStore.instance.lines.isNotEmpty) {
      LabelCollections.instance.migrateFromLegacy(
        lines: BatchStore.instance.lines
            .map(
              (l) => LabelModel(
                name: l.name,
                price: l.price,
                barcode: l.barcode,
                defaultCode: l.defaultCode,
                category: l.category,
                copies: l.copies,
              ),
            )
            .toList(),
        copies: BatchStore.instance.lines.map((l) => l.copies).toList(),
      );
      BatchStore.instance.clear();
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<String?> _askName(String title, [String initial = '']) async {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _share() async {
    final tsv = LabelCollections.instance.toTsv();
    final params = ShareParams(text: tsv, subject: 'cloud9-labels.tsv');
    await SharePlus.instance.share(params);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Shared TSV — run gen-label-pngs.js on the PC'),
      ),
    );
  }

  Future<void> _printAll() async {
    final active = LabelCollections.instance.active;
    final models = LabelCollections.instance.activeLines
        .map((l) => l.model)
        .toList();
    if (models.isEmpty || active == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PrintJobScreen(models: models, title: 'Printing ${active.name}'),
      ),
    );
  }

  void _openPreview(CollectionLine l) {
    showLabelPreviewSheet(
      context,
      l.model,
      initialSize: l.size,
      onSizeChanged: (v) {
        LabelCollections.instance.updateSize(l, v);
        Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = LabelCollections.instance;
    final active = store.active;
    if (!_ready || active == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final lines = store.activeLines;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _lineSel
              ? '${_lineKeys.length} selected'
              : '${active.name} (${store.activeTotalCopies})',
        ),
        actions: [
          if (_lineSel)
            IconButton(
              tooltip: 'Done selecting',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _lineSel = false;
                _lineKeys.clear();
              }),
            )
          else ...[
            IconButton(
              tooltip: 'Browse items',
              icon: const Icon(Icons.playlist_add),
              onPressed: _openPicker,
            ),
            if (lines.isNotEmpty)
              IconButton(
                tooltip: 'Print all labels',
                icon: const Icon(Icons.print),
                onPressed: _printAll,
              ),
          ],
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'new':
                  final n = await _askName('New collection');
                  if (n != null && n.isNotEmpty) store.create(n);
                  break;
                case 'rename':
                  final n = await _askName('Rename collection', active.name);
                  if (n != null && n.isNotEmpty) store.rename(active, n);
                  break;
                case 'duplicate':
                  store.duplicate(active);
                  break;
                case 'delete':
                  store.delete(active);
                  break;
                case 'clear':
                  store.clearActive();
                  break;
                case 'share':
                  await _share();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('New collection')),
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
              PopupMenuItem(value: 'delete', child: Text('Delete collection')),
              PopupMenuItem(value: 'clear', child: Text('Clear lines')),
              PopupMenuItem(value: 'share', child: Text('Share TSV')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (store.collections.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DropdownButtonFormField<String>(
                initialValue: active.id,
                decoration: const InputDecoration(
                  labelText: 'Collection',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in store.collections)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text('${c.name} (${c.totalCopies})'),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) store.setActive(v);
                },
              ),
            ),
          Expanded(
            child: lines.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Empty.\nScan in Receive with "+ Label" on,\nor browse items to add some.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('Browse items'),
                            onPressed: _openPicker,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: lines.length,
                    itemBuilder: (_, i) {
                      final l = lines[i];
                      final sel = _lineSel && _lineKeys.contains(_lineKey(l));
                      return Dismissible(
                        key: ValueKey(
                          LabelCollections.keyOf(
                            barcode: l.barcode,
                            defaultCode: l.defaultCode,
                            name: l.name,
                          ),
                        ),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => store.remove(l),
                        child: ListTile(
                          leading: _lineSel
                              ? Checkbox(
                                  value: sel,
                                  onChanged: (_) => _toggleLine(l),
                                )
                              : null,
                          selected: sel,
                          title: Text(l.model.displayName),
                          subtitle: Text(
                            '${l.barcode.isEmpty ? (l.defaultCode.isEmpty ? 'NO BARCODE' : l.defaultCode) : l.barcode}  •  \$${l.price.toStringAsFixed(2)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove),
                                onPressed: () => store.dec(l),
                              ),
                              Text(
                                '${l.copies}',
                                style: const TextStyle(fontSize: 18),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () => store.inc(l),
                              ),
                            ],
                          ),
                          onTap: () =>
                              _lineSel ? _toggleLine(l) : _openPreview(l),
                          onLongPress: () {
                            if (!_lineSel) {
                              setState(() => _lineSel = true);
                            }
                            _toggleLine(l);
                          },
                        ),
                      );
                    },
                  ),
          ),
          if (lines.isNotEmpty && _lineSel)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  icon: const Icon(Icons.print),
                  label: Text('Print selected (${_lineKeys.length})'),
                  onPressed: _lineKeys.isEmpty ? null : _printSelected,
                ),
              ),
            ),
          if (lines.isNotEmpty && !_lineSel)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.share),
                      label: const Text('Share TSV'),
                      onPressed: _share,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.print),
                      label: const Text('Print all'),
                      onPressed: _printAll,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New collection',
        child: const Icon(Icons.add),
        onPressed: () async {
          final n = await _askName('New collection');
          if (n != null && n.isNotEmpty) store.create(n);
        },
      ),
    );
  }
}
