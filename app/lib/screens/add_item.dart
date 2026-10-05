// Add inventory: standalone new-product form with expiry capture.
// Expiry is kept per variant on-device (see SessionStore); Odoo
// lot-tracked expiry is a P1 follow-up.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audit_log.dart';
import '../batch_store.dart';
import '../category_map.dart';
import '../odoo_client.dart';
import '../session_store.dart';
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
  bool _busy = false;
  bool _catsLoading = false;
  String? _err;

  CategoryPair? get _pair {
    if (_catId == null) return null;
    final pos = _cats.where((c) => c.id == _catId);
    if (pos.isEmpty) return null;
    return CategoryMap.resolve(pos: pos.first, internalCats: _internalCats);
  }

  @override
  void initState() {
    super.initState();
    _loadCats();
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
      if (!mounted) return;
      setState(() {
        _cats = cats;
        _internalCats = internal;
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
    if (code != null && code.trim().isNotEmpty) {
      setState(() => _barcode.text = code.trim());
    }
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

  Future<void> _create() async {
    final code = _barcode.text.trim();
    final name = _name.text.trim();
    final sku = _sku.text.trim();
    final cost = _num(_cost.text);
    final price = _num(_price.text);
    final qty = _num(_qty.text);
    if (name.length < 2) {
      setState(() => _err = 'Name is required (≥ 2 chars).');
      return;
    }
    if (_catId == null || _pair == null) {
      setState(() => _err = 'Pick a mapped category (Unmapped — pick again).');
      return;
    }
    if (cost.isNaN || price.isNaN || qty.isNaN || cost < 0 || price < 0 || qty < 0) {
      setState(() => _err = 'Enter valid cost, price and qty (≥ 0).');
      return;
    }
    String reason = '';
    if (price < cost) {
      setState(() => _err = 'Below cost — new items must be priced at or above cost.');
      return;
    }
    if (sku.isNotEmpty) {
      final hits = await widget.client.findBySku(sku);
      if (hits.isNotEmpty && mounted) {
        setState(() => _err = 'SKU in use by ${hits.first.name}.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final pair = _pair!;
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
      final exp = _expiry == null ? null : _ymd(_expiry!);
      if (exp != null) await SessionStore.saveExpiry(vid, exp);
      BatchStore.instance.add(
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
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $name (0 → $qty)')));
      setState(() {
        _barcode.clear();
        _name.clear();
        _sku.clear();
        _expiry = null;
      });
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _catLabel() {
    if (_catId == null) return '';
    final pos = _cats.where((c) => c.id == _catId);
    return pos.isEmpty ? '' : pos.first.name;
  }

  @override
  Widget build(BuildContext context) {
    final pair = _pair;
    return Scaffold(
      appBar: AppBar(title: const Text('Add inventory')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              icon: const Icon(Icons.qr_code_scanner, size: 28),
              label: const Text('Scan barcode', style: TextStyle(fontSize: 20)),
              onPressed: _busy ? null : _scan,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _barcode,
            decoration: const InputDecoration(
                labelText: 'Barcode (or type it)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Name *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _sku,
            decoration: const InputDecoration(
                labelText: 'SKU', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          _catsLoading
              ? const LinearProgressIndicator()
              : Autocomplete<PosCategory>(
                  displayStringForOption: (c) => c.name,
                  optionsBuilder: (t) => CategoryMap.filter(_cats, t.text),
                  onSelected: (c) => setState(() => _catId = c.id),
                  fieldViewBuilder: (ctx, ctl, focus, onSubmit) {
                    if (ctl.text.isEmpty && _catId != null) {
                      ctl.text = _catLabel();
                    }
                    return TextField(
                      controller: ctl,
                      focusNode: focus,
                      decoration: const InputDecoration(
                          labelText: 'Category * (type to filter)',
                          border: OutlineInputBorder()),
                      onChanged: (_) {
                        final m = _cats.where((c) =>
                            c.name.toLowerCase() ==
                            ctl.text.trim().toLowerCase());
                        setState(
                            () => _catId = m.isEmpty ? null : m.first.id);
                      },
                    );
                  },
                ),
          if (_catId != null && pair == null)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Unmapped — pick again.',
                  style: TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Cost', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Price', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Qty', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(_expiry == null
                ? 'Expiry date (optional)'
                : 'Expires: ${_ymd(_expiry!)}'),
            onPressed: _busy ? null : _pickExpiry,
          ),
          if (_expiry != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _expiry = null),
                child: const Text('Clear date'),
              ),
            ),
          ExpansionTile(
            title: const Text('Details'),
            tilePadding: EdgeInsets.zero,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sellable in POS'),
                value: _saleOk,
                onChanged: (v) => setState(() => _saleOk = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Purchasable'),
                value: _purchaseOk,
                onChanged: (v) => setState(() => _purchaseOk = v),
              ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(label: Text('Stock tracked')),
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
              child: const Text('Add to inventory',
                  style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}
