// Waste / loss screen: scan -> lookup -> log scrap (never quant overwrite).
// Disposition date (disposedAt, server-validated) is the tax date.
// Explicit confirm per line; no auto-save on scan-away.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../audit_log.dart';
import '../i18n/lang.dart';
import '../odoo_client.dart';
import '../waste_store.dart';
import '../widgets/feedback.dart';
import 'scan.dart';

class WasteScreen extends StatefulWidget {
  final OdooClient client;
  final String user;
  const WasteScreen({super.key, required this.client, this.user = ''});

  @override
  State<WasteScreen> createState() => _WasteScreenState();
}

class _WasteScreenState extends State<WasteScreen> {
  final _barcode = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _note = TextEditingController();
  final _supplier = TextEditingController();
  final _manager = TextEditingController();
  final _cost = TextEditingController();
  final _price = TextEditingController();
  final _historySearch = TextEditingController();
  final _countFix = TextEditingController();

  bool _busy = false;
  String? _err;
  InventoryProduct? _found;
  List<StockLot> _lots = [];
  int? _lotId;
  WasteReason? _reason;
  WasteDisposition? _disposition;
  String _expiry = ''; // '' = none chosen yet; 'NO-DATE' = illegible
  bool _showHistory = false;
  bool _fixingPrice = false;
  bool _fixingCount = false;
  String? _overReason; // preset override chip, combined with _note
  String _historyFilter = 'all'; // all | pending | validated | voided | draft
  String? _lastResult; // success banner after a scrap posts
  List<ScrapHistoryLine> _serverHistory = [];
  bool _serverLoading = false;

  @override
  void initState() {
    super.initState();
    WasteStore.instance.addListener(_refresh);
    WasteStore.instance.load();
    _loadServerHistory();
  }

  @override
  void dispose() {
    WasteStore.instance.removeListener(_refresh);
    _barcode.dispose();
    _qty.dispose();
    _note.dispose();
    _supplier.dispose();
    _manager.dispose();
    _cost.dispose();
    _price.dispose();
    _historySearch.dispose();
    _countFix.dispose();
    super.dispose();
  }

  Future<void> _loadServerHistory() async {
    setState(() => _serverLoading = true);
    try {
      final rows = await widget.client.fetchScrapHistory(limit: 100);
      if (mounted) setState(() => _serverHistory = rows);
    } catch (_) {
      // Server history is a cross-check; local log remains authoritative.
    } finally {
      if (mounted) setState(() => _serverLoading = false);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _scan() async {
    final v = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (v != null && v.trim().isNotEmpty && mounted) {
      _barcode.text = v.trim();
      await _lookup();
    }
  }

  Future<void> _lookup() async {
    final code = _barcode.text.trim();
    if (code.isEmpty) {
      setState(() => _err = t('waste_err_scan'));
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
      _found = null;
      _lots = [];
      _lotId = null;
      _lastResult = null;
    });
    try {
      final hit = await widget.client.lookupProduct(code);
      if (!mounted) return;
      if (hit == null) {
        setState(() => _err = t('waste_err_notfound'));
        return;
      }
      setState(() {
        _found = hit.product;
        _cost.text = hit.product.standardPrice.toStringAsFixed(2);
        _price.text = hit.product.listPrice.toStringAsFixed(2);
        _fixingPrice = false;
        _overReason = null;
      });
      try {
        final lots = await widget.client.findLots(hit.product.variantId);
        if (mounted) setState(() => _lots = lots);
      } catch (_) {
        // Lot tracking optional; ignore.
      }
    } on OdooException catch (e) {
      if (!mounted) return;
      setState(() => _err = e.message == 'SESSION_EXPIRED'
          ? t('waste_err_session')
          : e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double get _qtyVal => double.tryParse(_qty.text.trim()) ?? 0;

  static const _overPresets = [
    'Missed delivery — never counted in',
    'Case vs each — unit mismatch',
    'Prior waste never logged',
    'Package size changed',
    'Odoo data error',
  ];

  String get _combinedNote {
    final over = _overReason?.trim() ?? '';
    final free = _note.text.trim();
    if (over.isEmpty) return free;
    if (free.isEmpty) return over;
    return '$over — $free';
  }

  double get _effCost {
    final p = _found;
    final typed = double.tryParse(_cost.text.trim());
    if (typed != null && typed > 0) return typed;
    return p?.standardPrice ?? 0;
  }

  double get _effTotal => WasteLine.liveTotal(_qtyVal, _effCost);

  Future<void> _fixZeroPrice(InventoryProduct p) async {
    final cost = double.tryParse(_cost.text.trim());
    final price = double.tryParse(_price.text.trim());
    if (cost == null || cost <= 0 || price == null || price < 0) {
      setState(() => _err = t('waste_err_nums_pos'));
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.client.updatePrices(p, price, cost);
      // Verify the write landed: re-read and compare. Odoo can accept the
      // RPC yet still show stale values (rights, validation, read lag), and
      // the old code toasted success regardless. Never claim a save we
      // cannot prove.
      final fresh = await widget.client.lookupProduct(
          p.barcode.isNotEmpty ? p.barcode : p.defaultCode);
      if (!mounted) return;
      final fp = fresh?.product;
      if (fp == null) {
        setState(() => _err = t('waste_err_verify'));
        return;
      }
      const tol = 0.0001;
      if ((fp.standardPrice - cost).abs() > tol ||
          (fp.listPrice - price).abs() > tol) {
        setState(() {
          _found = fp;
          _err = t('waste_err_verify');
        });
        return;
      }
      setState(() {
        _found = fp;
        _cost.text = fp.standardPrice.toStringAsFixed(2);
        _price.text = fp.listPrice.toStringAsFixed(2);
        _fixingPrice = false;
      });
      showOk(context, t('waste_price_fixed'));
    } on OdooException catch (e) {
      if (!mounted) return;
      setState(() => _err = e.message == 'SESSION_EXPIRED'
          ? t('waste_err_session')
          : OdooException.friendly(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// In-place on-hand correction: no navigation away from the waste form.
  /// Writes the absolute count via setStock, then verifies by re-reading.
  Future<void> _fixCountInPlace(InventoryProduct p) async {
    final target = double.tryParse(_countFix.text.trim());
    if (target == null || target < 0) {
      setState(() => _err = t('waste_err_nums'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('waste_count_title')),
        content: Text(Lang.instance.f('waste_count_body', {
          'name': p.name,
          'before': p.qtyAvailable.toStringAsFixed(0),
          'after': target.toStringAsFixed(0),
        })),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('waste_cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('waste_count_go'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.client.setStock(p, target);
      final code = p.barcode.isNotEmpty ? p.barcode : p.defaultCode;
      final fresh = await widget.client.lookupProduct(code);
      if (!mounted) return;
      final fp = fresh?.product;
      if (fp == null) {
        setState(() => _err = t('waste_err_verify'));
        return;
      }
      if ((fp.qtyAvailable - target).abs() > 0.001) {
        setState(() {
          _found = fp;
          _err = t('waste_err_verify');
        });
        return;
      }
      setState(() {
        _found = fp;
        _fixingCount = false;
        _overReason = null;
      });
      AuditLog.instance.add(AuditEntry(
        when: DateTime.now(),
        who: widget.user,
        mode: 'count',
        productId: p.variantId,
        productName: p.name,
        field: 'count-fix (waste)',
        oldValue: p.qtyAvailable.toStringAsFixed(0),
        newValue: target.toStringAsFixed(0),
        reason: _combinedNote.isEmpty ? 'waste over-scrap fix' : _combinedNote,
      ));
      showOk(context, t('waste_count_fixed'));
    } on OdooException catch (e) {
      if (!mounted) return;
      setState(() => _err = e.message == 'SESSION_EXPIRED'
          ? t('waste_err_session')
          : OdooException.friendly(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resetForm() {
    setState(() {
      _found = null;
      _barcode.clear();
      _qty.text = '1';
      _note.clear();
      _supplier.clear();
      _cost.clear();
      _price.clear();
      _countFix.clear();
      _reason = null;
      _disposition = null;
      _expiry = '';
      _lotId = null;
      _lots = [];
      _overReason = null;
      _fixingPrice = false;
      _fixingCount = false;
      _err = null;
    });
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year, now.month + 1, 0),
    );
    if (d != null && mounted) {
      setState(() => _expiry =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _logLoss() async {
    final p = _found;
    if (p == null) {
      setState(() => _err = t('waste_err_scan'));
      return;
    }
    final q = _qtyVal;
    if (q <= 0) {
      setState(() => _err = t('waste_err_qty'));
      return;
    }
    if (_reason == null || _disposition == null) {
      setState(() => _err = t('waste_err_reason'));
      return;
    }
    if (_expiry.isEmpty) {
      setState(() => _err = t('waste_err_expiry'));
      return;
    }
    // Zero cost is almost always a data mistake — fix first so the
    // frozen scrap value is defensible.
    if (p.standardPrice <= 0 && _effCost <= 0) {
      setState(() {
        _fixingPrice = true;
        _err = t('waste_err_zero_price');
      });
      return;
    }
    final over = q > p.qtyAvailable;
    if (over && _combinedNote.isEmpty) {
      setState(() => _err = t('waste_err_over_note'));
      return;
    }
    // Distinct destructive confirm: before -> after, never silent.
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('waste_confirm_title')),
        content: Text(Lang.instance.f('waste_confirm_body', {
          'name': p.name,
          'before': p.qtyAvailable.toStringAsFixed(0),
          'after': (p.qtyAvailable - q).toStringAsFixed(0),
          'qty': q.toStringAsFixed(0),
        })),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('waste_cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: Text(t('waste_confirm_go'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final id = 'w-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final effPrice =
        double.tryParse(_price.text.trim()) ?? p.listPrice;
    final line = WasteLine(
      id: id,
      variantId: p.variantId,
      tmplId: p.tmplId,
      name: p.name,
      barcode: p.barcode,
      sku: p.defaultCode,
      qty: q,
      reason: _reason!,
      disposition: _disposition!,
      packageExpiry: _expiry == 'NO-DATE' ? '' : _expiry,
      note: _combinedNote,
      supplierInvoice: _supplier.text.trim(),
      unitValue: _effCost, // estimate until scrap read-back freezes it
      retailEach: effPrice,
      status: WasteStatus.draft,
      discoveredAt: DateTime.now().toUtc(),
      staff: widget.user,
      quarantined: over,
    );
    WasteStore.instance.add(line);
    try {
      final res = await widget.client.createScrap(
        product: p,
        qty: q,
        lotId: _lotId,
        origin: 'WASTE:${wasteReasonLabel(_reason!)}/${wasteDispositionLabel(_disposition!)}',
      );
      WasteStore.instance.markPosted(id,
          scrapId: res.scrapId, unitValue: res.unitValue);
      AuditLog.instance.add(AuditEntry(
        when: DateTime.now(),
        who: widget.user,
        mode: 'waste',
        productId: p.variantId,
        productName: p.name,
        field: 'waste',
        oldValue: p.qtyAvailable.toStringAsFixed(0),
        newValue: (p.qtyAvailable - q).toStringAsFixed(0),
        reason:
            '${wasteReasonLabel(_reason!)} / ${wasteDispositionLabel(_disposition!)} scrap=${res.scrapId}',
      ));
      if (!mounted) return;
      final banner = Lang.instance.f('waste_ok_detail', {
        'name': p.name,
        'qty': q.toStringAsFixed(0),
        'total': (q * res.unitValue).toStringAsFixed(2),
        'scrap': '${res.scrapId}',
      });
      _resetForm();
      setState(() => _lastResult = banner);
      // Leave the log view: show confirmation with a jump to history so
      // the user sees the line actually landed (fixes "stuck" feeling).
      final goHistory = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(t('waste_done_title')),
          content: Text(banner),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(t('waste_again'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(t('waste_view_history'))),
          ],
        ),
      );
      if (mounted && goHistory == true) setState(() => _showHistory = true);
    } on OdooException catch (e) {
      // Offline / scrap unavailable: keep draft with discoveredAt so the
      // CPA can see what was backfilled vs server-validated.
      if (!mounted) return;
      setState(() => _err = e.message == 'SESSION_EXPIRED'
          ? t('waste_err_session')
          : '${t('waste_draft_kept')}: ${OdooException.friendly(e.message)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareCsv() async {
    final lines = WasteStore.instance.toLinesCsv();
    final summary = WasteStore.instance.toSummaryCsv();
    await SharePlus.instance.share(ShareParams(
        text:
            'CLOUD9 WASTE LINES\n$lines\nCLOUD9 WASTE SUMMARY\n$summary',
        subject: 'cloud9-waste-export'));
  }

  @override
  Widget build(BuildContext context) {
    final store = WasteStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('waste_title')),
        backgroundColor: const Color(0xFF7A1B1B),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () => setState(() => _showHistory = !_showHistory),
            child: Text(_showHistory ? t('waste_tab_log') : t('waste_tab_history'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _showHistory ? _history(store) : _form(store),
    );
  }

  Widget _form(WasteStore store) {
    final p = _found;
    final over = p != null && _qtyVal > p.qtyAvailable;
    final zeroCost = p != null && p.standardPrice <= 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFDECEA),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(t('waste_banner'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(t('waste_tab_log'))),
            ButtonSegment(value: true, label: Text(t('waste_tab_history'))),
          ],
          selected: {_showHistory},
          onSelectionChanged: (s) => setState(() => _showHistory = s.first),
        ),
        const SizedBox(height: 12),
        if (_lastResult != null)
          Card(
            color: const Color(0xFFE8F5E9),
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(_lastResult!),
              trailing: TextButton(
                onPressed: () => setState(() => _showHistory = true),
                child: Text(t('waste_view_history')),
              ),
            ),
          ),
        if (_lastResult != null) const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _barcode,
                decoration: InputDecoration(labelText: t('waste_barcode')),
                onSubmitted: (_) => _lookup(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _scan, child: Text(t('waste_scan'))),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: _busy ? null : _lookup, child: Text(t('waste_go'))),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_err != null) ...[
          const SizedBox(height: 8),
          Text(_err!, style: const TextStyle(color: Colors.red)),
        ],
        if (p != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: Text(p.name),
              subtitle: Text(
                  '${p.barcode} • SKU ${p.defaultCode}\n${t('waste_onhand')} ${p.qtyAvailable.toStringAsFixed(0)} • \$${p.standardPrice.toStringAsFixed(2)}'),
            ),
          ),
          if (zeroCost || _fixingPrice) ...[
            Card(
              color: const Color(0xFFFFF8E1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('waste_zero_warn'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _cost,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                labelText: t('waste_cost_fix')),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _price,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                labelText: t('waste_price_fix')),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: _busy ? null : () => _fixZeroPrice(p),
                      child: Text(t('waste_fix_price')),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (over) ...[
            Card(
              color: const Color(0xFFFDECEA),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        Lang.instance.f('waste_over_warn', {
                          'onhand': p.qtyAvailable.toStringAsFixed(0),
                          'qty': _qtyVal.toStringAsFixed(0),
                        }),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(t('waste_over_hint')),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _overPresets
                          .map((r) => ChoiceChip(
                                label: Text(r, style: const TextStyle(fontSize: 12)),
                                selected: _overReason == r,
                                onSelected: (_) =>
                                    setState(() => _overReason = r),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _countFix,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                labelText: t('waste_correct_onhand')),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _busy ? null : () => _fixCountInPlace(p),
                          child: Text(t('waste_fix_count')),
                        ),
                      ],
                    ),
                    if (_fixingCount)
                      Text(t('waste_count_hint'),
                          style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ],
          if (_lots.isNotEmpty) ...[
            DropdownButtonFormField<int>(
              initialValue: _lotId,
              decoration: InputDecoration(labelText: t('waste_lot')),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                for (final l in _lots)
                  DropdownMenuItem(
                      value: l.id,
                      child: Text(l.expirationDate.isEmpty
                          ? l.name
                          : '${l.name} • ${l.expirationDate}')),
              ],
              onChanged: (v) => setState(() => _lotId = v),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                  onPressed: () {
                    final v = (_qtyVal - 1).clamp(1, 9999);
                    _qty.text = v.toStringAsFixed(0);
                    setState(() {});
                  },
                  icon: const Icon(Icons.remove_circle_outline, size: 36)),
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: InputDecoration(labelText: t('waste_qty')),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                  onPressed: () {
                    final v = (_qtyVal + 1).clamp(1, 9999);
                    _qty.text = v.toStringAsFixed(0);
                    setState(() {});
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 36)),
            ],
          ),
          const SizedBox(height: 8),
          Text(t('waste_reason'), style: const TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 8,
            children: WasteReason.values
                .map((r) => ChoiceChip(
                      label: Text(wasteReasonLabel(r)),
                      selected: _reason == r,
                      onSelected: (_) => setState(() => _reason = r),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Text(t('waste_disposition'), style: const TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 8,
            children: WasteDisposition.values
                .map((d) => ChoiceChip(
                      label: Text(wasteDispositionLabel(d)),
                      selected: _disposition == d,
                      onSelected: (_) => setState(() => _disposition = d),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: Text(_expiry.isEmpty
                      ? t('waste_expiry_none')
                      : _expiry == 'NO-DATE'
                          ? t('waste_expiry_nodate')
                          : '${t('waste_expiry')}: $_expiry')),
              TextButton(onPressed: _pickExpiry, child: Text(t('waste_pick'))),
              TextButton(
                  onPressed: () => setState(() => _expiry = 'NO-DATE'),
                  child: Text(t('waste_expiry_nodate'))),
            ],
          ),
          ExpansionTile(
            title: Text(t('waste_details')),
            children: [
              TextField(
                  controller: _note,
                  decoration: InputDecoration(labelText: t('waste_note'))),
              TextField(
                  controller: _supplier,
                  decoration:
                      InputDecoration(labelText: t('waste_supplier'))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
              '${t('waste_total')} ${_effTotal.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _busy ? null : _logLoss,
              child: Text(t('waste_submit')),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            title: Text(t('waste_summary_title')),
            subtitle: Text(Lang.instance.f('waste_summary_body', {
              'net': store.netDeductible.toStringAsFixed(2),
              'n': '${store.lines.length}',
            })),
            trailing: IconButton(
              icon: const Icon(Icons.share),
              onPressed: _shareCsv,
            ),
          ),
        ),
      ],
    );
  }

  Widget _history(WasteStore store) {
    final q = _historySearch.text.trim().toLowerCase();
    final filtered = store.lines.where((l) {
      if (_historyFilter == 'pending' &&
          !(l.status == WasteStatus.posted || l.status == WasteStatus.draft)) {
        return false;
      }
      if (_historyFilter == 'validated' && l.status != WasteStatus.validated) {
        return false;
      }
      if (_historyFilter == 'voided' && l.status != WasteStatus.voided) {
        return false;
      }
      if (_historyFilter == 'draft' && l.status != WasteStatus.draft) {
        return false;
      }
      if (q.isEmpty) return true;
      return l.name.toLowerCase().contains(q) ||
          l.barcode.toLowerCase().contains(q) ||
          l.sku.toLowerCase().contains(q);
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(t('waste_tab_log'))),
                  ButtonSegment(
                      value: true, label: Text(t('waste_tab_history'))),
                ],
                selected: {_showHistory},
                onSelectionChanged: (s) =>
                    setState(() => _showHistory = s.first),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: Text(t('waste_summary_title')),
                  subtitle: Text(Lang.instance.f('waste_summary_body', {
                    'net': store.netDeductible.toStringAsFixed(2),
                    'n': '${store.lines.length}',
                  })),
                  trailing: IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: _shareCsv,
                  ),
                ),
              ),
              TextField(
                controller: _historySearch,
                decoration:
                    InputDecoration(labelText: t('waste_history_search')),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in ['all', 'pending', 'validated', 'voided', 'draft'])
                    ChoiceChip(
                      label: Text(t('waste_filter_$f')),
                      selected: _historyFilter == f,
                      onSelected: (_) =>
                          setState(() => _historyFilter = f),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manager,
                      decoration:
                          InputDecoration(labelText: t('waste_manager')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                      onPressed: _shareCsv, child: Text(t('waste_export'))),
                ],
              ),
              Card(
                color: const Color(0xFFF3F4F6),
                child: ListTile(
                  title: Text(t('waste_server_title')),
                  subtitle: Text(_serverLoading
                      ? t('waste_server_loading')
                      : Lang.instance.f('waste_server_body', {
                          'n': '${_serverHistory.length}'
                        })),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loadServerHistory,
                  ),
                ),
              ),
              for (final s in _serverHistory.take(5))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_done_outlined),
                    title:
                        Text('${s.productName} × ${s.qty.toStringAsFixed(0)}'),
                    subtitle: Text(
                        'scrap ${s.id} • ${s.state} • ${s.dateDone}\n${s.origin}'),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text(t('waste_history_empty')))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (c, i) {
                    final l = filtered[i];
                    final ref = l.disposedAt ?? l.discoveredAt;
                    return Card(
                      child: ListTile(
                        title:
                            Text('${l.name} × ${l.qty.toStringAsFixed(0)}'),
                        subtitle: Text(
                            '${wasteReasonLabel(l.reason)} • ${wasteDispositionLabel(l.disposition)} • \$${l.totalValue.toStringAsFixed(2)}\n'
                            '${WasteStore.monthKey(ref)} • ${l.status.name}${l.quarantined ? ' • QUARANTINED' : ''}${l.scrapId == null ? ' • DRAFT' : ' • scrap ${l.scrapId}'}\n'
                            '${l.packageExpiry.isEmpty ? t('waste_expiry_nodate') : l.packageExpiry}${l.note.isEmpty ? '' : ' • ${l.note}'}'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            final m = _manager.text.trim();
                            if (m.isEmpty) {
                              setState(
                                  () => _err = t('waste_err_manager'));
                              showErr(context, t('waste_err_manager'));
                              return;
                            }
                            if (v == 'validate') {
                              if (l.staff.isNotEmpty && l.staff == m) {
                                showErr(context, t('waste_err_self'));
                                return;
                              }
                              final ok =
                                  store.validate(l.id, manager: m);
                              if (ok) {
                                showOk(context, t('waste_validated'));
                              } else {
                                showErr(context, t('waste_blocked'));
                              }
                            } else if (v == 'void') {
                              final ok = store.voidLine(l.id,
                                  manager: m, reason: 'manager void');
                              if (ok) {
                                showOk(context, t('waste_voided'));
                              } else {
                                showErr(context, t('waste_blocked'));
                              }
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                                value: 'validate',
                                child: Text(t('waste_validate'))),
                            PopupMenuItem(
                                value: 'void',
                                child: Text(t('waste_void'))),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
