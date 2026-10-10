// Add inventory: standalone new-product form with expiry capture.
// Expiry is kept per variant on-device (see SessionStore); Odoo
// lot-tracked expiry is a P1 follow-up.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audit_log.dart';
import '../label_collections.dart';
import '../category_map.dart';
import '../i18n/lang.dart';
import '../odoo_client.dart';
import '../print/label_model.dart';
import '../print/printer_service.dart';
import '../session_store.dart';
import '../widgets/category_picker.dart';
import '../widgets/feedback.dart';
import 'receive.dart';
import 'scan.dart';

class AddItemScreen extends StatefulWidget {
  final OdooClient client;
  final String user;
  const AddItemScreen({super.key, required this.client, required this.user});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _barcode = TextEditingController();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _cost = TextEditingController();
  final _price = TextEditingController();
  final _qty = TextEditingController(text: '0');
  bool _saleOk = true;
  bool _purchaseOk = true;
  DateTime? _expiry;

  List<PosCategory> _cats = [];
  List<PosCategory> _internalCats = [];
  int? _catId;
  List<int> _recentCats = [];
  bool _busy = false;
  bool _catsLoading = false;
  String? _err;
  bool _continuous = true;
  bool _noBarcode = false;
  InventoryProduct? _existing;
  LabelModel? _lastCreated;

  CategoryPair? get _pair {
    return CategoryMap.resolveForCreate(
      posId: _catId,
      posCats: _cats,
      internalCats: _internalCats,
    );
  }

  bool get _isExactPair {
    if (_catId == null) return false;
    final pos = _cats.where((c) => c.id == _catId);
    if (pos.isEmpty) return false;
    return CategoryMap.resolve(pos: pos.first, internalCats: _internalCats) !=
        null;
  }

  @override
  void initState() {
    super.initState();
    _loadCats();
    SessionStore.loadContinuous().then((v) {
      if (mounted) setState(() => _continuous = v);
    });
  }

  @override
  void dispose() {
    _barcode.dispose();
    _name.dispose();
    _sku.dispose();
    _cost.dispose();
    _price.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _loadCats() async {
    setState(() => _catsLoading = true);
    try {
      final cats = await widget.client.getPosCategories();
      List<PosCategory> internal = [];
      try {
        internal = await widget.client.getProductCategories();
      } catch (_) {}
      final last = await SessionStore.loadLastPosCat();
      final recent = await SessionStore.loadRecentPosCats();
      if (!mounted) return;
      setState(() {
        _cats = cats;
        _internalCats = internal;
        _recentCats = recent;
        if (last != null && cats.any((c) => c.id == last)) {
          _catId = last;
        } else if (cats.isNotEmpty) {
          _catId = cats.first.id;
        }
      });
    } catch (_) {}
    finally {
      if (mounted) setState(() => _catsLoading = false);
    }
  }

  Future<void> _scan() async {
    HapticFeedback.lightImpact();
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    setState(() {
      _barcode.text = code.trim();
      _existing = null;
      _err = null;
    });
    // Route existing items to Update count instead of duplicating them.
    try {
      final rows = await widget.client.findVariants(code.trim());
      if (!mounted) return;
      if (rows.isNotEmpty) {
        setState(() => _existing = rows.first);
      }
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (_) {}
  }

  void _updateInstead() {
    final p = _existing;
    if (p == null) return;
    final code = p.barcode.isNotEmpty ? p.barcode : p.defaultCode;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReceiveScreen(
        client: widget.client,
        user: widget.user,
        initialBarcode: code,
        initialMode: 'count',
      ),
    ));
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (d != null && mounted) setState(() => _expiry = d);
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double _num(String s) => double.tryParse(s.trim()) ?? double.nan;

  void _fail(String inline, [String? toastDetail]) {
    setState(() => _err = inline);
    if (mounted) showErr(context, Lang.instance.f('toast_fail', {'detail': toastDetail ?? inline}));
  }

  Future<void> _create() async {
    final code = _noBarcode ? '' : _barcode.text.trim();
    final name = _name.text.trim();
    final sku = _sku.text.trim();
    final cost = _num(_cost.text);
    final price = _num(_price.text);
    final qty = _num(_qty.text);
    if (name.length < 2) {
      _fail(t('add_err_name'));
      return;
    }
    if (_noBarcode && sku.isEmpty) {
      _fail(t('add_sku_required'));
      return;
    }
    if (_catId == null || _pair == null) {
      _fail(t('add_err_cat'));
      return;
    }
    if (cost.isNaN || price.isNaN || qty.isNaN || cost < 0 || price < 0 || qty < 0) {
      _fail(t('add_err_nums'));
      return;
    }
    String reason = '';
    if (price < cost) {
      _fail(t('add_err_belowcost'));
      return;
    }
    if (sku.isNotEmpty) {
      final hits = await widget.client.findBySku(sku);
      if (hits.isNotEmpty && mounted) {
        _fail(Lang.instance.f('add_err_sku_inuse', {'name': hits.first.name}));
        return;
      }
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final pair = _pair!;
      // Barcode collision: route to the existing item instead of duping it.
      // Skipped for no-barcode items (empty code matches nothing).
      if (code.isNotEmpty) {
        final clash = await widget.client.findVariants(code);
        if (clash.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _existing = clash.first;
            _err = Lang.instance
                .f('add_err_barcode_inuse', {'name': clash.first.name});
          });
          return;
        }
      }
      final vid = await widget.client.createProduct(
        name: name,
        barcode: code,
        posCategId: pair.posId,
        categId: pair.internalId,
        listPrice: price,
        standardPrice: cost,
        qty: qty,
        sku: sku,
        saleOk: _saleOk,
        purchaseOk: _purchaseOk,
      );
      await SessionStore.saveLastPosCat(pair.posId);
      final recent = await SessionStore.loadRecentPosCats();
      if (!mounted) return;
      setState(() => _recentCats = recent);
      final exp = _expiry == null ? null : _ymd(_expiry!);
      if (exp != null) await SessionStore.saveExpiry(vid, exp);
      LabelCollections.instance.addToActive(
          barcode: code, name: name, price: price, defaultCode: sku);
      AuditLog.instance.add(AuditEntry(
        when: DateTime.now(),
        who: widget.user,
        mode: 'create',
        productId: vid,
        productName: name,
        field: 'create',
        oldValue: '—',
        newValue:
            'qty ${qty.toStringAsFixed(0)}, $name${exp == null ? '' : ', exp $exp'}',
        reason: reason,
      ));
      if (!mounted) return;
      final created = LabelModel(
          name: name, price: price, barcode: code, defaultCode: sku);
      // Success toast only — the old bottom-right Print action covered
      // the submit button, so printing now lives in the result card.
      showOk(context, Lang.instance.f('add_ok', {'name': name}));
      setState(() {
        _barcode.clear();
        _name.clear();
        _sku.clear();
        _expiry = null;
        _existing = null;
        _lastCreated = created;
      });
      if (_continuous && mounted) await _scan();
    } on OdooException catch (e) {
      if (mounted) _fail(e.message, e.message);
    } catch (e) {
      if (mounted) _fail(e.toString(), e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printLast() async {
    final created = _lastCreated;
    if (created == null || _busy || !mounted) return;
    try {
      await PrinterService.instance.printLabel(created);
      if (mounted) {
        showOk(context,
            Lang.instance.f('add_print_sent', {'name': created.name}));
      }
    } catch (e) {
      if (mounted) showErr(context, '$e');
    }
  }

  /// Inline result card for the last saved item: Print lives here now
  /// (the old bottom-right snackbar action covered the submit button).
  Widget _resultCard() {
    final created = _lastCreated!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t('add_added_title'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _lastCreated = null),
              ),
            ],
          ),
          Text(created.name),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.print),
            label: Text(t('add_print')),
            onPressed: _busy ? null : _printLast,
          ),
        ],
      ),
    );
  }

  /// One-tap chips for recently used categories (stale Odoo IDs filtered).
  Widget _recentChips() {
    final byId = <int, PosCategory>{for (final c in _cats) c.id: c};
    final recents = [
      for (final id in _recentCats)
        if (byId.containsKey(id)) byId[id]!
    ];
    if (recents.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final c in recents)
            ChoiceChip(
              label: Text(c.name),
              selected: c.id == _catId,
              onSelected: (_) => setState(() => _catId = c.id),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pair = _pair;
    return Scaffold(
      appBar: AppBar(title: Text(t('add_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              icon: const Icon(Icons.qr_code_scanner, size: 28),
              label: Text(t('add_scan'), style: const TextStyle(fontSize: 20)),
              onPressed: _busy ? null : _scan,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _barcode,
            enabled: !_busy && !_noBarcode,
            decoration: InputDecoration(
                labelText: t('add_barcode'),
                border: const OutlineInputBorder()),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t('add_nobarcode')),
            subtitle: Text(t('add_nobarcode_hint')),
            value: _noBarcode,
            onChanged: _busy
                ? null
                : (v) => setState(() {
                      _noBarcode = v ?? false;
                      if (_noBarcode) _barcode.clear();
                      _existing = null;
                      _err = null;
                    }),
          ),
          if (_lastCreated != null) _resultCard(),
          if (_existing != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      Lang.instance.f('add_dup_msg', {
                        'name': _existing!.name,
                        'qty': _existing!.qtyAvailable.toStringAsFixed(0)
                      }),
                      style:
                          const TextStyle(fontWeight: FontWeight.bold)),
                  Text(t('add_dup_sub')),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : _updateInstead,
                    child: Text(t('add_update_instead')),
                  ),
                ],
              ),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t('add_continuous')),
            subtitle: Text(t('add_continuous_sub')),
            value: _continuous,
            onChanged: (v) {
              setState(() => _continuous = v);
              SessionStore.saveContinuous(v);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: InputDecoration(
                labelText: t('add_name'), border: const OutlineInputBorder()),
            // Refresh keyword ranking in the picker as the name is typed.
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _sku,
            decoration: InputDecoration(
                labelText: t('add_sku'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          _recentChips(),
          _catsLoading
              ? const LinearProgressIndicator()
              : CategoryPickerField(
                  categories: _cats,
                  selectedId: _catId,
                  productName: _name.text,
                  onSelected: (id) => setState(() => _catId = id),
                ),
          if (_catId != null && pair == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(t('add_cats_loading'),
                  style: const TextStyle(color: Colors.grey)),
            ),
          if (pair != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  _isExactPair
                      ? 'Maps to: ${pair.internalName} + POS ${pair.posName}'
                      : 'Maps to: ${pair.internalName} (fallback) + POS ${pair.posName}',
                  style: const TextStyle(color: Colors.grey)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: t('add_cost'),
                      border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: t('add_price'),
                      border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: t('add_qty'),
                      border: const OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(_expiry == null
                ? t('add_expiry')
                : 'Expires: ${_ymd(_expiry!)}'),
            onPressed: _busy ? null : _pickExpiry,
          ),
          if (_expiry != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _expiry = null),
                child: Text(t('add_expiry_clear')),
              ),
            ),
          ExpansionTile(
            title: Text(t('add_details')),
            tilePadding: EdgeInsets.zero,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('add_sellable')),
                value: _saleOk,
                onChanged: (v) => setState(() => _saleOk = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('add_purchasable')),
                value: _purchaseOk,
                onChanged: (v) => setState(() => _purchaseOk = v),
              ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(label: Text(t('add_stocktracked'))),
                ),
            ],
          ),
          if (_err != null) ...[
            const SizedBox(height: 8),
            Text(_err!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _create,
              child: Text(t('add_submit'),
                  style: const TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}
