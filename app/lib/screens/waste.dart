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

  bool _busy = false;
  String? _err;
  InventoryProduct? _found;
  List<StockLot> _lots = [];
  int? _lotId;
  WasteReason? _reason;
  WasteDisposition? _disposition;
  String _expiry = ''; // '' = none chosen yet; 'NO-DATE' = illegible
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    WasteStore.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    WasteStore.instance.removeListener(_refresh);
    _barcode.dispose();
    _qty.dispose();
    _note.dispose();
    _supplier.dispose();
    _manager.dispose();
    super.dispose();
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
    });
    try {
      final hit = await widget.client.lookupProduct(code);
      if (!mounted) return;
      if (hit == null) {
        setState(() => _err = t('waste_err_notfound'));
        return;
      }
      setState(() => _found = hit.product);
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
    final over = q > p.qtyAvailable;
    if (over && _note.text.trim().isEmpty) {
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
      note: _note.text.trim(),
      supplierInvoice: _supplier.text.trim(),
      unitValue: p.standardPrice, // estimate until scrap read-back freezes it
      retailEach: p.listPrice,
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
      setState(() {
        _found = null;
        _barcode.clear();
        _qty.text = '1';
        _note.clear();
        _supplier.clear();
        _reason = null;
        _disposition = null;
        _expiry = '';
        _lotId = null;
      });
      showOk(context, t('waste_ok'));
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
              '${t('waste_total')} ${(_qtyVal * p.standardPrice).toStringAsFixed(2)}',
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
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
        ),
        Expanded(
          child: ListView.builder(
            itemCount: store.lines.length,
            itemBuilder: (c, i) {
              final l = store.lines[i];
              return Card(
                child: ListTile(
                  title: Text('${l.name} × ${l.qty.toStringAsFixed(0)}'),
                  subtitle: Text(
                      '${wasteReasonLabel(l.reason)} • ${wasteDispositionLabel(l.disposition)} • \$${l.totalValue.toStringAsFixed(2)}\n${l.status.name}${l.quarantined ? ' • QUARANTINED' : ''}${l.scrapId == null ? ' • DRAFT' : ' • scrap ${l.scrapId}'}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      final m = _manager.text.trim();
                      if (m.isEmpty) {
                        setState(() => _err = t('waste_err_manager'));
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
                          value: 'void', child: Text(t('waste_void'))),
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
