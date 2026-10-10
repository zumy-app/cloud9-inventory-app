// Browse inventory: search + category filter + paged list.
// Read-only (View) shows a detail sheet; editable (Manage) jumps straight
// into the Update-count loop prefilled with the item.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/lang.dart';
import '../label_collections.dart';
import '../odoo_client.dart';
import '../print/label_model.dart';
import '../print/printer_service.dart';
import '../session_store.dart';
import '../widgets/feedback.dart';
import '../widgets/label_preview.dart';
import 'receive.dart';
import 'scan.dart';

/// Map a browsed product to a picker payload (category + size resolved
/// here; the collections tab never touches Odoo types).
PickedLabel mapProductToPicked(InventoryProduct p, String category) {
  final split = LabelModel.splitNameSize(p.name.trim());
  return (
    barcode: p.barcode,
    name: split.name,
    price: p.listPrice,
    size: split.size,
    defaultCode: p.defaultCode,
    category: category,
    variantId: p.variantId,
  );
}

/// Fetch every product matching a filter (paged, capped). Pure fetch —
/// callers decide confirm + where the payloads go.
Future<List<InventoryProduct>> fetchAllMatching(
  OdooClient client, {
  required String query,
  required int? posCategId,
  int page = 50,
  int cap = 1000,
}) async {
  final all = <InventoryProduct>[];
  var offset = 0;
  while (true) {
    final res = await client.searchProducts(
      query: query,
      posCategId: posCategId,
      limit: page,
      offset: offset,
    );
    all.addAll(res.rows);
    if (!res.more || all.length >= cap) break;
    offset += res.rows.length;
  }
  return all;
}

class BrowseScreen extends StatefulWidget {
  final OdooClient client;
  final String user;
  final bool editable;
  final String title;

  /// Labels-picker mode: always selecting, tap toggles, bottom bar pops
  /// a [PickResult] instead of writing the store. `existingKeys` (target
  /// collection line keys at open) drives "In collection" badges.
  final bool pickMode;
  final Set<String> existingKeys;
  const BrowseScreen({
    super.key,
    required this.client,
    required this.user,
    required this.editable,
    this.title = 'Browse inventory',
    this.pickMode = false,
    this.existingKeys = const {},
  });

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _search = TextEditingController();
  List<PosCategory> _cats = [];
  int? _catId; // null = all
  List<InventoryProduct> _rows = [];
  bool _busy = false;
  bool _more = false;
  int _offset = 0;
  String? _err;
  static const int _page = 50;
  bool _selecting = false;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    assert(!widget.pickMode || !widget.editable,
        'pickMode is exclusive with editable (no Receive push while picking)');
    if (widget.pickMode) _selecting = true;
    _loadCats();
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadCats() async {
    try {
      final cats = await widget.client.getPosCategories();
      if (!mounted) return;
      setState(() => _cats = cats);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _err = null;
      _offset = 0;
    });
    try {
      final res = await widget.client.searchProducts(
        query: _search.text,
        posCategId: _catId,
        limit: _page,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _rows = res.rows;
        _more = res.more;
        _offset = res.rows.length;
        // Prune selections that are no longer visible.
        final ids = res.rows.map((p) => p.variantId).toSet();
        _selected.removeWhere((id) => !ids.contains(id));
      });
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = _friendlyErr(e));
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _busy = true);
    try {
      final res = await widget.client.searchProducts(
        query: _search.text,
        posCategId: _catId,
        limit: _page,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _rows = [..._rows, ...res.rows];
        _more = res.more;
        _offset += res.rows.length;
      });
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = _friendlyErr(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _catName(int? id) {
    if (id == null) return '';
    final m = _cats.where((c) => c.id == id);
    return m.isEmpty ? '' : m.first.name;
  }

  /// Never leak the raw SESSION_EXPIRED token to staff. Auto-refresh in
  /// OdooClient already retried once — reaching here means stored creds
  /// are missing/stale, so a manual sign-in is required.
  String _friendlyErr(OdooException e) => e.message == 'SESSION_EXPIRED'
      ? 'Session expired — sign in again (Account tab → Sign out, then sign back in).'
      : e.message;

  void _toggleSelect(InventoryProduct p) {
    setState(() {
      if (_selected.contains(p.variantId)) {
        _selected.remove(p.variantId);
      } else {
        _selected.add(p.variantId);
      }
    });
  }

  Future<void> _addSelectedToActive() async {
    final byId = {for (final p in _rows) p.variantId: p};
    var n = 0;
    for (final id in _selected) {
      final p = byId[id];
      if (p == null) continue;
      LabelCollections.instance.addToActive(
        barcode: p.barcode,
        name: p.name,
        price: p.listPrice,
        defaultCode: p.defaultCode,
        category: _catName(p.posCategId),
        variantId: p.variantId,
      );
      n++;
    }
    if (!mounted) return;
    showOk(context, Lang.instance.f('browse_added_n', {'n': '$n'}));
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  /// Shared >50 confirm dialog for both add-all flows.
  Future<bool> _confirmAddAll(int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('browse_addall_title')),
        content: Text(
            Lang.instance.f('browse_addall_msg', {'n': '$count'})),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t('browse_cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t('browse_addall'))),
        ],
      ),
    );
    return ok == true;
  }

  /// Bulk add every product matching the current search + category filter.
  /// Paged fetch (cap 1000), confirm sheet when > 50, cancellable via
  /// back button; partial success reports `Added x of y`.
  Future<void> _addAllInFilter() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final all = await fetchAllMatching(
        widget.client,
        query: _search.text,
        posCategId: _catId,
      );
      if (!mounted) return;
      if (all.length > 50) {
        if (!await _confirmAddAll(all.length) || !mounted) {
          setState(() => _busy = false);
          return;
        }
      }
      for (final p in all) {
        LabelCollections.instance.addToActive(
          barcode: p.barcode,
          name: p.name,
          price: p.listPrice,
          defaultCode: p.defaultCode,
          category: _catName(p.posCategId),
          variantId: p.variantId,
        );
      }
      if (!mounted) return;
      showOk(context,
          Lang.instance.f('browse_added_n', {'n': '${all.length}'}));
      setState(() {
        _selected.clear();
        _selecting = false;
      });
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = _friendlyErr(e));
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pop the current selection as a picker result (pick mode only).
  void _popPick({required bool printNow}) {
    final byId = {for (final p in _rows) p.variantId: p};
    final items = <PickedLabel>[
      for (final id in _selected)
        if (byId[id] != null)
          mapProductToPicked(byId[id]!, _catName(byId[id]!.posCategId)),
    ];
    Navigator.of(context).pop((items: items, printNow: printNow));
  }

  /// Bottom bar for picker mode. Empty selection offers the whole
  /// filter; a selection offers Add vs Add & Print (ask each time).
  Widget _pickBar() {
    if (_selected.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.label),
                label: Text(t('browse_addall_filter')),
                onPressed: _busy ? null : _pickAllFlow,
              ),
              Text(
                t('browse_pick_hint'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
          ],
        ),
      );
    }
    final n = _selected.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _popPick(printNow: false),
                  child: Text(
                      Lang.instance.f('browse_add_n', {'n': '$n'})),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _busy ? null : () => _popPick(printNow: true),
                  child: Text(
                      Lang.instance.f('browse_addprint_n', {'n': '$n'})),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: _busy ? null : _pickAllFlow,
            child: Text(t('browse_addall_instead')),
          ),
        ],
      ),
    );
  }

  /// Pick-mode "add all": fetch everything matching the filter, confirm
  /// when large, then pop payloads (the opener writes to its pinned target).
  Future<void> _pickAllFlow() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final all = await fetchAllMatching(
        widget.client,
        query: _search.text,
        posCategId: _catId,
      );
      if (!mounted) return;
      if (all.length > 50) {
        if (!await _confirmAddAll(all.length) || !mounted) {
          setState(() => _busy = false);
          return;
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop((
        items: [
          for (final p in all) mapProductToPicked(p, _catName(p.posCategId))
        ],
        printNow: false,
      ));
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = _friendlyErr(e));
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onTap(InventoryProduct p) {
    if (widget.pickMode || _selecting) {
      _toggleSelect(p);
      return;
    }
    if (widget.editable) {
      final code = p.barcode.isNotEmpty ? p.barcode : p.defaultCode;
      if (code.isEmpty) {
        showErr(context, t('browse_nocode'));
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReceiveScreen(
          client: widget.client,
          user: widget.user,
          initialBarcode: code,
          initialMode: 'count',
        ),
      ));
    } else {
      _showDetail(p);
    }
  }

  /// Detail sheet. In picker mode the Print button is replaced by a
  /// Select toggle (nothing prints outside the pinned collection flow).
  Future<void> _showDetail(InventoryProduct p, {bool pick = false}) async {
    final expiry = await SessionStore.loadExpiry(p.variantId);
    if (!mounted) return;
    final alreadyPicked = _selected.contains(p.variantId);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(p.name,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
                Lang.instance.f('browse_onhand',
                    {'qty': p.qtyAvailable.toStringAsFixed(0)}),
                style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            Text(
                '${t('browse_barcode')} ${p.barcode.isEmpty ? '—' : p.barcode}'),
            Text(
                '${t('browse_sku')} ${p.defaultCode.isEmpty ? '—' : p.defaultCode}'),
            Text(
                '${t('browse_price')} \$${p.listPrice.toStringAsFixed(2)} • ${t('browse_cost')} \$${p.standardPrice.toStringAsFixed(2)}'),
            Text(
                '${t('browse_category')} ${_catName(p.posCategId).isEmpty ? '—' : _catName(p.posCategId)}'),
            Text('${t('browse_expires')} ${expiry ?? '—'}'),
            const SizedBox(height: 12),
            LabelPreview(
                model: LabelModel.fromProduct(p), compact: true),
            const SizedBox(height: 12),
            if (pick)
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  icon: Icon(alreadyPicked
                      ? Icons.check_circle
                      : Icons.add),
                  label: Text(alreadyPicked
                      ? t('browse_selected')
                      : t('browse_select_item')),
                  onPressed: () {
                    _toggleSelect(p);
                    Navigator.of(context).pop();
                  },
                ),
              )
            else
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  icon: const Icon(Icons.print),
                  label: Text(t('browse_print')),
                  onPressed: () async {
                    try {
                      await PrinterService.instance.printLabel(
                        LabelModel.fromProduct(p),
                      );
                      if (!mounted) return;
                      showOk(
                          context,
                          Lang.instance.f(
                              'browse_label_sent', {'name': p.name}));
                    } catch (e) {
                      if (!mounted) return;
                      showErr(context, '$e');
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _scan() async {
    HapticFeedback.lightImpact();
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (code != null && code.trim().isNotEmpty && mounted) {
      setState(() => _search.text = code.trim());
      await _refresh();
    }
  }

  /// No-match state: offer to create the item instead of dead-ending.
  /// Code-like queries seed the barcode; free text seeds the product name.
  Future<void> _addNew(String q) async {
    final codeLike =
        !q.contains(' ') && RegExp(r'^[0-9A-Za-z\-._]+$').hasMatch(q);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReceiveScreen(
        client: widget.client,
        user: widget.user,
        initialBarcode: codeLike ? q : '',
        initialName: codeLike ? '' : q,
        initialNoBarcode: !codeLike,
      ),
    ));
    if (mounted) await _refresh();
  }

  Widget _emptyState() {
    final q = _search.text.trim();
    if (q.isEmpty || !widget.editable) {
      return Center(child: Text(t('browse_empty')));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(Lang.instance.f('browse_nomatch', {'q': q}),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: Text(t('browse_add_new')),
              onPressed: () => _addNew(q),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode
            ? '${widget.title} • ${Lang.instance.q('batch_sel_one', 'batch_sel_other', _selected.length)}'
            : _selecting
                ? Lang.instance.q(
                    'batch_sel_one', 'batch_sel_other', _selected.length)
                : widget.title),
        actions: [
          if (widget.pickMode)
            IconButton(
              tooltip: t('browse_cancel'),
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            )
          else
            IconButton(
              tooltip: _selecting
                  ? t('browse_done_select')
                  : t('browse_select_labels'),
              icon: Icon(_selecting ? Icons.close : Icons.checklist),
              onPressed: () => setState(() {
                _selecting = !_selecting;
                _selected.clear();
              }),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: t('browse_search_hint'),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _refresh(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(t('browse_scan')),
                    onPressed: _busy ? null : _scan,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: DropdownButtonFormField<int?>(
                initialValue: _catId,
                decoration: InputDecoration(
                  labelText: t('browse_category_label'),
                  border: const OutlineInputBorder()),
                items: [
                  DropdownMenuItem<int?>(
                      value: null, child: Text(t('browse_all_cats'))),
                ..._cats.map((c) =>
                    DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
              ],
              onChanged: (v) {
                setState(() => _catId = v);
                _refresh();
              },
            ),
          ),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_err!,
                  style: const TextStyle(color: Colors.red)),
            ),
          if (widget.pickMode) _pickBar(),
          if (!widget.pickMode && _selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.label),
                        label: Text(_selected.isEmpty
                            ? t('browse_addall_filter')
                            : Lang.instance.f('browse_add_n_labels',
                                {'n': '${_selected.length}'})),
                      onPressed: _busy
                          ? null
                          : () => _selected.isEmpty
                              ? _addAllInFilter()
                              : _addSelectedToActive(),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _rows.isEmpty && !_busy
                ? _emptyState()
                : ListView.builder(
                    itemCount: _rows.length + (_more ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _rows.length) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: OutlinedButton(
                            onPressed: _busy ? null : _loadMore,
                            child: Text(t('browse_load_more')),
                          ),
                        );
                      }
                      final p = _rows[i];
                      final sel =
                          _selecting && _selected.contains(p.variantId);
                      // Badge parity with stored lines (base name, same key).
                      final inTarget = widget.pickMode &&
                          widget.existingKeys.contains(
                              LabelCollections.keyOf(
                            barcode: p.barcode,
                            defaultCode: p.defaultCode,
                            name: LabelModel.splitNameSize(p.name.trim()).name,
                          ));
                      return ListTile(
                        leading: _selecting
                            ? Checkbox(
                                value: sel,
                                onChanged: (_) => _toggleSelect(p),
                              )
                            : null,
                        selected: sel,
                        title: Text(p.name),
                        subtitle: Text(
                            '${p.barcode.isEmpty ? (p.defaultCode.isEmpty ? t('browse_no_code') : p.defaultCode) : p.barcode} • ${_catName(p.posCategId)}${inTarget ? ' • ${t('browse_in_collection')}' : ''}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.pickMode)
                              IconButton(
                                tooltip: t('browse_details'),
                                icon: const Icon(Icons.info_outline),
                                onPressed: _busy
                                    ? null
                                    : () =>
                                        _showDetail(p, pick: true),
                              ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(p.qtyAvailable.toStringAsFixed(0),
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold)),
                                Text(
                                    '\$${p.listPrice.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: Colors.grey)),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => _onTap(p),
                        onLongPress: () {
                          if (!_selecting) {
                            setState(() => _selecting = true);
                          }
                          _toggleSelect(p);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
