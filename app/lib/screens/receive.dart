// Receive / Count screen: scan -> lookup -> save (found) or create (not found).
// Two modes: Receive + (additive) vs Count = (absolute). See docs/01-MVP.md.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audit_log.dart';
import '../batch_store.dart';
import '../category_map.dart';
import '../odoo_client.dart';
import '../price_guard.dart';
import '../session_store.dart';
import 'scan.dart';
import 'scan_sheet.dart';

class ReceiveScreen extends StatefulWidget {
  final OdooClient client;
  final String user;
  final String initialBarcode;
  final String initialMode; // 'receive' | 'count' | '' (= stored pref)
  const ReceiveScreen(
      {super.key,
      required this.client,
      this.user = '',
      this.initialBarcode = '',
      this.initialMode = ''});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _barcode = TextEditingController();
  bool _busy = false;
  String? _err;

  String _mode = 'receive'; // 'receive' | 'count'
  bool get _isCount => _mode == 'count';

  InventoryProduct? _found;
  List<InventoryProduct> _duplicates = [];

  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _cost = TextEditingController();
  final _price = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _reason = TextEditingController();
  bool _reasonRequired = false;
  bool _skuOverride = false;
  bool _showPriceAdjust = false;
  bool _addLabel = true;
  bool _quantBlocked = false;
  Future<void> Function()? _retrySave;
  bool _converting = false;
  DateTime? _expiry;
  String? _expiryOrig;

  bool _merging = false;
  int? _keeperId;
  bool _isQuantBlocked(String msg) =>
      msg.contains('Quants') || msg.contains('refuses stock');

  void _resetSaveState() {
    _quantBlocked = false;
    _retrySave = null;
    _reasonRequired = false;
    _skuOverride = false;
    _merging = false;
    _keeperId = null;
  }

  // new-product form
  final _newName = TextEditingController();
  final _newSku = TextEditingController();
  final _newCost = TextEditingController();
  final _newPrice = TextEditingController();
  final _newQty = TextEditingController(text: '1');
  bool _newSaleOk = true;
  bool _newPurchaseOk = true;
  List<PosCategory> _cats = [];
  List<PosCategory> _internalCats = [];
  int? _catId;
  bool _catsLoading = false;

  CategoryPair? get _pair {
    if (_catId == null) return null;
    final pos = _cats.where((c) => c.id == _catId);
    if (pos.isEmpty) return null;
    return CategoryMap.resolve(pos: pos.first, internalCats: _internalCats);
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadCats();
    if (widget.initialBarcode.trim().isNotEmpty) {
      _barcode.text = widget.initialBarcode.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup());
    }
  }

  Future<void> _loadPrefs() async {
    if (widget.initialMode == 'receive' || widget.initialMode == 'count') {
      setState(() {
        _mode = widget.initialMode;
        if (_isCount) _qty.text = '';
      });
      return;
    }
    final m = await SessionStore.loadInvMode();
    if (!mounted) return;
    setState(() {
      _mode = m == 'count' ? 'count' : 'receive';
      if (_isCount && _qty.text == '1') _qty.text = '';
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
    _reason.dispose();
    _newName.dispose();
    _newSku.dispose();
    _newCost.dispose();
    _newPrice.dispose();
    _newQty.dispose();
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
    } catch (_) {
      // Categories load lazily on create; lookup still works.
    } finally {
      if (mounted) setState(() => _catsLoading = false);
    }
  }

  Future<void> _scan() async {
    HapticFeedback.lightImpact();
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (code != null && code.trim().isNotEmpty) {
      _barcode.text = code.trim();
      await _lookup();
    }
  }

  Future<void> _openContinuous() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScanSheet(
          client: widget.client,
          user: widget.user,
          mode: _mode,
          posCats: _cats,
          internalCats: _internalCats,
        ),
      ),
    );
  }

  Future<void> _lookup() async {
    final code = _barcode.text.trim();
    if (code.isEmpty || _busy) return;
    _resetSaveState();
    setState(() {
      _busy = true;
      _err = null;
      _found = null;
      _duplicates = [];
    });
    try {
      final rows = await widget.client.findVariants(code);
      if (!mounted) return;
      if (rows.isEmpty) {
        setState(() {
          _newName.text = '';
          _newSku.text = code.length <= 32 ? code : '';
          _newCost.text = '';
          _newPrice.text = '';
          _newQty.text = '1';
        });
      } else if (rows.length > 1) {
        setState(() => _duplicates = rows);
      } else {
        _fillFound(rows.first);
      }
    } on OdooException catch (e) {
      if (!mounted) return;
      if (e.message == 'SESSION_EXPIRED') {
        setState(() => _err = 'Session expired — sign in again (Account tab).');
      } else {
        setState(() => _err = e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillFound(InventoryProduct p) {
    _name.text = p.name;
    _sku.text = p.defaultCode;
    _cost.text = p.standardPrice.toStringAsFixed(2);
    _price.text = p.listPrice.toStringAsFixed(2);
    _qty.text = _isCount ? '' : '1';
    _reason.clear();
    _expiry = null;
    _expiryOrig = null;
    // Preselect the product's own POS category when known.
    if (p.posCategId != null &&
        _cats.any((c) => c.id == p.posCategId)) {
      _catId = p.posCategId;
    }
    _resetSaveState();
    setState(() {
      _found = p;
      _duplicates = [];
      _showPriceAdjust = false;
    });
    SessionStore.loadExpiry(p.variantId).then((e) {
      if (!mounted || _found?.variantId != p.variantId) return;
      if (e != null && e.trim().isNotEmpty) {
        setState(() {
          _expiry = DateTime.tryParse(e.trim());
          _expiryOrig = e.trim();
        });
      }
    });
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickFoundExpiry() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (d != null && mounted) setState(() => _expiry = d);
  }

  double _num(String s) => double.tryParse(s.trim()) ?? double.nan;

  void _audit(String mode, InventoryProduct p, String field, String oldV,
      String newV, String reason) {
    AuditLog.instance.add(AuditEntry(
      when: DateTime.now(),
      who: widget.user,
      mode: mode,
      productId: p.variantId,
      productName: p.name,
      field: field,
      oldValue: oldV,
      newValue: newV,
      reason: reason,
    ));
  }

  String _catLabel() {
    if (_catId == null) return '';
    final pos = _cats.where((c) => c.id == _catId);
    return pos.isEmpty ? '' : pos.first.name;
  }

  /// Shared validation + price-guard for the found card.
  /// Returns null when blocked (sets _err).
  ({double cost, double price, String reason})? _checkPrices(
      InventoryProduct p) {
    final cost = _num(_cost.text);
    final price = _num(_price.text);
    if (cost.isNaN || price.isNaN || cost < 0 || price < 0) {
      setState(() => _err = 'Enter valid cost and price (≥ 0).');
      return null;
    }
    final need = PriceGuard.needsReason(
        newPrice: price, cost: cost, oldPrice: p.listPrice);
    final reason = _reason.text.trim();
    if (need && reason.isEmpty) {
      setState(() {
        _reasonRequired = true;
        _err = PriceGuard.describe(
            newPrice: price, cost: cost, oldPrice: p.listPrice);
      });
      return null;
    }
    return (cost: cost, price: price, reason: reason);
  }

  Future<bool> _checkSku(InventoryProduct p) async {
    final s = _sku.text.trim();
    if (s == p.defaultCode) return true;
    if (s.isEmpty) return true;
    final hits = await widget.client.findBySku(s);
    final clash =
        hits.where((h) => h.variantId != p.variantId).toList(growable: false);
    if (clash.isNotEmpty && !_skuOverride) {
      if (!mounted) return false;
      setState(() =>
          _err = 'SKU in use by ${clash.first.name} — change it or tap Use anyway.');
      return false;
    }
    return true;
  }

  Future<void> _applyNameSkuPrices(
      InventoryProduct p, double cost, double price, String reason) async {
    final oldName = p.name;
    final oldSku = p.defaultCode;
    final oldCost = p.standardPrice;
    final oldPrice = p.listPrice;
    await widget.client.updateName(p, _name.text);
    await widget.client.updateSku(p, _sku.text);
    await widget.client.updatePrices(p, price, cost);
    if (_name.text.trim().isNotEmpty && _name.text.trim() != oldName) {
      _audit('receive', p, 'name', oldName, _name.text.trim(), reason);
    }
    if (_sku.text.trim() != oldSku) {
      _audit('receive', p, 'sku', oldSku, _sku.text.trim(), reason);
    }
    if ((price - oldPrice).abs() > 0.0001) {
      _audit('receive', p, 'list_price', oldPrice.toStringAsFixed(2),
          price.toStringAsFixed(2), reason);
    }
    if ((cost - oldCost).abs() > 0.0001) {
      _audit('receive', p, 'standard_price', oldCost.toStringAsFixed(2),
          cost.toStringAsFixed(2), reason);
    }
    final pair = _pair;
    if (pair != null && p.posCategId != pair.posId) {
      await widget.client.updateCategory(p, pair.internalId, pair.posId);
      await SessionStore.saveLastPosCat(pair.posId);
      _audit('receive', p, 'category', _catNameOf(p.posCategId),
          pair.posName, reason);
    }
    if (_expiry != null) {
      final ymd = _ymd(_expiry!);
      if (ymd != _expiryOrig) {
        await SessionStore.saveExpiry(p.variantId, ymd);
        _audit('receive', p, 'expiry', _expiryOrig ?? '—', ymd, reason);
        _expiryOrig = ymd;
      }
    }
  }

  String _catNameOf(int? id) {
    if (id == null) return '—';
    final m = _cats.where((c) => c.id == id);
    return m.isEmpty ? '—' : m.first.name;
  }

  void _afterSave(String toast) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast)));
    _resetSaveState();
    setState(() {
      _barcode.clear();
      _found = null;
    });
  }

  /// Stock-write half of Add stock, rerunnable after an in-app convert.
  Future<void> _finishAddStock(
      InventoryProduct p, double qty, double price) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final after = await widget.client.addStock(p, qty);
      _audit('receive', p, 'qty', p.qtyAvailable.toStringAsFixed(0),
          after.toStringAsFixed(0), '');
      if (_addLabel) {
        BatchStore.instance.add(
          barcode: p.barcode.isNotEmpty ? p.barcode : _barcode.text.trim(),
          name: _name.text.trim().isNotEmpty ? _name.text.trim() : p.name,
          price: price,
          defaultCode: _sku.text.trim(),
          category: _catLabel(),
        );
      }
      if (_catId != null) {
        await SessionStore.saveLastPosCat(_catId!);
      }
      _afterSave('Saved ${p.name} +$qty → $after');
    } on OdooException catch (e) {
      if (!mounted) return;
      if (_isQuantBlocked(e.message)) {
        setState(() {
          _err = e.message;
          _quantBlocked = true;
          _retrySave = () => _finishAddStock(p, qty, price);
        });
        return;
      }
      setState(() => _err = e.message);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Stock-write half of Set count, rerunnable after an in-app convert.
  Future<void> _finishSetCount(
      InventoryProduct p, double counted, double price) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final after = await widget.client.setStock(p, counted);
      _audit('count', p, 'qty', p.qtyAvailable.toStringAsFixed(0),
          after.toStringAsFixed(0), '');
      if (_addLabel) {
        BatchStore.instance.add(
          barcode: p.barcode.isNotEmpty ? p.barcode : _barcode.text.trim(),
          name: p.name,
          price: price,
          defaultCode: p.defaultCode,
          category: _catLabel(),
        );
      }
      _afterSave('Counted ${p.name}: → $after');
    } on OdooException catch (e) {
      if (!mounted) return;
      if (_isQuantBlocked(e.message)) {
        setState(() {
          _err = e.message;
          _quantBlocked = true;
          _retrySave = () => _finishSetCount(p, counted, price);
        });
        return;
      }
      setState(() => _err = e.message);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One-tap recovery: flip the template to Storable, then rerun the
  /// pending save (or just confirm when nothing is pending).
  Future<void> _convertAndRetry() async {
    final p = _found;
    if (p == null || _converting) return;
    final retry = _retrySave;
    setState(() {
      _converting = true;
      _err = null;
    });
    try {
      await widget.client.setStorable(p);
      _audit('receive', p, 'is_storable', 'false', 'true', 'in-app convert');
      if (!mounted) return;
      setState(() {
        _found = p.asStorable();
        _quantBlocked = false;
      });
      if (retry != null) {
        setState(() => _retrySave = null);
        await retry();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${p.name} is now Storable — save again.')));
      }
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  /// Receive + : single Update button (details + optional stock add).
  Future<void> _updateItem() async {
    final p = _found;
    if (p == null || _busy) return;
    if (_name.text.trim().length < 2 && _name.text.trim() != p.name) {
      setState(() => _err = 'Name must be at least 2 characters.');
      return;
    }
    final qtyRaw = _qty.text.trim();
    final qty = qtyRaw.isEmpty ? 0.0 : _num(qtyRaw);
    if (qty.isNaN || qty < 0) {
      setState(
          () => _err = 'Enter qty to add (≥ 0), or leave empty for details only.');
      return;
    }
    final checked = _checkPrices(p);
    if (checked == null) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      if (!await _checkSku(p)) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await _applyNameSkuPrices(p, checked.cost, checked.price, checked.reason);
      if (qty > 0) {
        if (mounted) setState(() => _busy = false);
        await _finishAddStock(p, qty, checked.price);
      } else {
        _afterSave('Updated ${p.name} (no stock change)');
      }
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Count = : Set count button with mandatory before → after confirm.
  /// Blank qty + Adjust price = prices-only fix (no stock write).
  Future<void> _setCount() async {
    final p = _found;
    if (p == null || _busy) return;
    if (_qty.text.trim().isEmpty && !_showPriceAdjust) {
      setState(() => _err = 'Enter the counted qty (no default in Count mode).');
      return;
    }
    if (_qty.text.trim().isEmpty) {
      final checked = _checkPrices(p);
      if (checked == null) return;
      setState(() {
        _busy = true;
        _err = null;
      });
      try {
        if (!await _checkSku(p)) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        await _applyNameSkuPrices(
            p, checked.cost, checked.price, checked.reason);
        _afterSave('Prices updated for ${p.name} (no count change)');
      } on OdooException catch (e) {
        if (mounted) setState(() => _err = e.message);
      } catch (e) {
        if (mounted) setState(() => _err = e.toString());
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final counted = _num(_qty.text);
    if (counted.isNaN || counted < 0) {
      setState(() => _err = 'Enter counted qty (≥ 0).');
      return;
    }
    double cost = p.standardPrice;
    double price = p.listPrice;
    String reason = '';
    if (_showPriceAdjust) {
      final checked = _checkPrices(p);
      if (checked == null) return;
      cost = checked.cost;
      price = checked.price;
      reason = checked.reason;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm count'),
        content: Text(
            '${p.name}\n${p.qtyAvailable.toStringAsFixed(0)} → ${counted.toStringAsFixed(0)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      if (_showPriceAdjust) {
        if (!await _checkSku(p)) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        await _applyNameSkuPrices(p, cost, price, reason);
      }
      if (mounted) setState(() => _busy = false);
      await _finishSetCount(p, counted, price);
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createNew() async {
    final code = _barcode.text.trim();
    final name = _newName.text.trim();
    final sku = _newSku.text.trim();
    final cost =
        _newCost.text.trim().isEmpty ? 0.0 : _num(_newCost.text);
    final price = _num(_newPrice.text);
    final qty = _num(_newQty.text);
    if (name.length < 2) {
      setState(() => _err = 'Name is required (≥ 2 chars).');
      return;
    }
    if (_catId == null) {
      setState(() => _err = 'Pick a category.');
      return;
    }
    final pair = _pair;
    if (pair == null) {
      setState(() => _err = 'Unmapped — pick again.');
      return;
    }
    if (cost.isNaN || price.isNaN || qty.isNaN || cost < 0 || price < 0 || qty < 0) {
      setState(() => _err = 'Enter valid price and qty (≥ 0). Cost is optional.');
      return;
    }
    String reason = '';
    if (PriceGuard.needsReason(newPrice: price, cost: cost, oldPrice: 0)) {
      if (price < cost) {
        final r = await _askReason(
            PriceGuard.describe(newPrice: price, cost: cost, oldPrice: 0));
        if (r == null) return;
        reason = r;
      }
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
      final vid = await widget.client.createProduct(
        name: name,
        barcode: code,
        posCategId: pair.posId,
        categId: pair.internalId,
        listPrice: price,
        standardPrice: cost,
        qty: qty,
        sku: sku,
        saleOk: _newSaleOk,
        purchaseOk: _newPurchaseOk,
      );
      await SessionStore.saveLastPosCat(pair.posId);
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
        newValue: 'qty ${qty.toStringAsFixed(0)}, $name',
        reason: reason,
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Created $name (0 → $qty)')));
      setState(() {
        _barcode.clear();
        _newName.clear();
      });
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason(String why) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reason required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(why),
            const SizedBox(height: 8),
            TextField(
                controller: c,
                decoration: const InputDecoration(
                    labelText: 'Reason', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(c.text.trim()),
              child: const Text('Continue')),
        ],
      ),
    );
    if (r == null || r.isEmpty) {
      if (mounted) setState(() => _err = why);
      return null;
    }
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final code = _barcode.text.trim();
    final showCreate = code.isNotEmpty && _found == null && _duplicates.isEmpty && !_busy;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isCount ? 'Update count' : 'Receive delivery'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              icon: const Icon(Icons.qr_code_scanner, size: 28),
              label: const Text('Scan', style: TextStyle(fontSize: 20)),
              onPressed: _busy ? null : _scan,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.burst_mode),
              label: const Text('Rapid scan — stays open',
                  style: TextStyle(fontSize: 16)),
              onPressed: _busy ? null : _openContinuous,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _barcode,
                  decoration: const InputDecoration(
                    labelText: 'Barcode (or type + Go)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _lookup(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: _busy ? null : _lookup,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Go'),
                ),
              ),
            ],
          ),
          if (_err != null) ...[
            const SizedBox(height: 8),
            Text(_err!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 12),
          if (_duplicates.length > 1) _duplicateCard(),
          if (_found != null) _foundCard(_found!),
          if (showCreate && _found == null) _createCard(code),
        ],
      ),
    );
  }

  Widget _convertBanner(InventoryProduct p) {
    final kind = p.type == 'service' ? 'Service' : 'Consumable';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('No stock tracking ($kind)',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const Text(
              'Odoo cannot hold stock for this type. Convert it to Storable to save quantities here.'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed:
                (_busy || _converting) ? null : _convertAndRetry,
            child: Text(_converting
                ? 'Converting…'
                : (_retrySave != null
                    ? 'Convert to Storable & retry'
                    : 'Convert to Storable')),
          ),
        ],
      ),
    );
  }

  Widget _keeperTile(InventoryProduct d) {
    return RadioListTile<int>(
      value: d.variantId,
      title: Text(d.name),
      subtitle: Text(
          'SKU: ${d.defaultCode.isEmpty ? '—' : d.defaultCode} • On-hand: ${d.qtyAvailable.toStringAsFixed(0)}'),
    );
  }

  Widget _duplicateCard() {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Duplicate barcode — pick the right item',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(_merging
                ? 'Choose the record to keep. Stock is summed into it; the others are archived (reversible, never deleted).'
                : 'Saving is blocked until you choose. Stock must land on the right variant.'),
            const SizedBox(height: 8),
            if (_merging)
              RadioGroup<int>(
                groupValue: _keeperId,
                onChanged: (v) => setState(() => _keeperId = v),
                child: Column(
                  children: _duplicates.map(_keeperTile).toList(),
                ),
              )
            else
              ..._duplicates.map((d) => ListTile(
                    title: Text(d.name),
                    subtitle: Text(
                        'SKU: ${d.defaultCode.isEmpty ? '—' : d.defaultCode} • On-hand: ${d.qtyAvailable.toStringAsFixed(0)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _fillFound(d),
                  )),
            const SizedBox(height: 8),
            if (!_merging)
              OutlinedButton.icon(
                icon: const Icon(Icons.merge),
                label: const Text('Merge duplicates…'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _merging = true;
                          _keeperId = _duplicates.first.variantId;
                        }),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _merging = false;
                                _keeperId = null;
                              }),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          (_busy || _keeperId == null) ? null : _mergeDuplicates,
                      child: const Text('Merge'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Merge duplicate variants: sum stock into the keeper, archive the rest.
  Future<void> _mergeDuplicates() async {
    final keeperId = _keeperId;
    if (keeperId == null || _busy) return;
    final keeper = _duplicates.firstWhere((d) => d.variantId == keeperId);
    final others =
        _duplicates.where((d) => d.variantId != keeperId).toList();
    final total = _duplicates.fold<double>(
        0, (a, d) => a + d.qtyAvailable);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm merge'),
        content: Text(
            'Keep: ${keeper.name}\nStock: ${keeper.qtyAvailable.toStringAsFixed(0)} → ${total.toStringAsFixed(0)}\nArchive ${others.length} duplicate(s). Nothing is deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Merge')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      if (!keeper.tracksStock) {
        await widget.client.setStorable(keeper);
      }
      await widget.client.setStock(keeper.asStorable(), total);
      _audit('receive', keeper, 'qty',
          keeper.qtyAvailable.toStringAsFixed(0), total.toStringAsFixed(0),
          'merge ${others.length} duplicate(s)');
      for (final o in others) {
        await widget.client.archiveVariant(o);
        _audit('receive', o, 'active', 'true', 'false',
            'merged into ${keeper.name}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Merged ${others.length} into ${keeper.name} (qty → ${total.toStringAsFixed(0)})')));
      setState(() {
        _barcode.clear();
        _duplicates = [];
        _found = null;
      });
      _resetSaveState();
      if (mounted) setState(() {});
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _foundCard(InventoryProduct p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(p.name,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                'Barcode: ${p.barcode.isNotEmpty ? p.barcode : '—'}  •  On-hand: ${p.qtyAvailable.toStringAsFixed(0)}'),
            if (!p.tracksStock || _quantBlocked) ...[
              const SizedBox(height: 8),
              _convertBanner(p),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Name', border: OutlineInputBorder()),
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
                    optionsBuilder: (t) =>
                        CategoryMap.filter(_cats, t.text),
                    onSelected: (c) => setState(() => _catId = c.id),
                    fieldViewBuilder: (ctx, ctl, focus, onSubmit) {
                      if (ctl.text.isEmpty && _catId != null) {
                        ctl.text = _catLabel();
                      }
                      return TextField(
                        controller: ctl,
                        focusNode: focus,
                        decoration: const InputDecoration(
                            labelText: 'Category (type to filter)',
                            border: OutlineInputBorder()),
                        onChanged: (_) {
                          final m = _cats.where((c) =>
                              c.name.toLowerCase() ==
                              ctl.text.trim().toLowerCase());
                          setState(() =>
                              _catId = m.isEmpty ? null : m.first.id);
                        },
                      );
                    },
                  ),
            if (_catId != null && _pair == null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Unmapped — pick again.',
                    style: TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(_expiry == null
                  ? 'Expiry date (optional)'
                  : 'Expires: ${_ymd(_expiry!)}'),
              onPressed: _busy ? null : _pickFoundExpiry,
            ),
            if (_expiry != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _expiry = null),
                  child: const Text('Clear date'),
                ),
              ),
            const SizedBox(height: 8),
            if (!_isCount || _showPriceAdjust) ...[
              TextField(
                controller: _cost,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Purchase price (cost)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Sale price', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
            ],
            if (_isCount && !_showPriceAdjust)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _showPriceAdjust = true),
                  child: const Text('Adjust price'),
                ),
              ),
            TextField(
              controller: _qty,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: _isCount ? 'Counted qty' : 'Qty to add',
                  helperText: _isCount
                      ? 'Leave empty for prices only'
                      : 'Leave empty for details only',
                  border: const OutlineInputBorder()),
            ),
            if (_reasonRequired) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(
                    labelText: 'Reason (required)',
                    border: OutlineInputBorder()),
              ),
            ],
            if (_err != null &&
                _err!.startsWith('SKU in use')) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _skuOverride = true;
                    _err = null;
                  }),
                  child: const Text('Use anyway'),
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Add to label batch'),
              value: _addLabel,
              onChanged: (v) => setState(() => _addLabel = v),
            ),
            if (!_isCount)
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _updateItem,
                  child: const Text('Update',
                      style: TextStyle(fontSize: 18)),
                ),
              ),
            if (_isCount)
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _setCount,
                  child: const Text('Set count',
                      style: TextStyle(fontSize: 18)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _createCard(String code) {
    final pair = _pair;
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Not in Odoo — new product',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Barcode: $code'),
            const SizedBox(height: 12),
            TextField(
              controller: _newName,
              decoration: const InputDecoration(
                  labelText: 'Name *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _newSku,
              decoration: const InputDecoration(
                  labelText: 'SKU', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            _catsLoading
                ? const LinearProgressIndicator()
                : Autocomplete<PosCategory>(
                    displayStringForOption: (c) => c.name,
                    optionsBuilder: (t) =>
                        CategoryMap.filter(_cats, t.text),
                    onSelected: (c) => setState(() => _catId = c.id),
                    fieldViewBuilder:
                        (ctx, ctl, focus, onSubmit) {
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
                          setState(() =>
                              _catId = m.isEmpty ? null : m.first.id);
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
            if (pair != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Maps to: ${pair.internalName} + POS ${pair.posName}',
                    style: const TextStyle(color: Colors.grey)),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newCost,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Cost (optional)',
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _newPrice,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Price', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _newQty,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Qty', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text('Details'),
              tilePadding: EdgeInsets.zero,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sellable in POS'),
                  value: _newSaleOk,
                  onChanged: (v) => setState(() => _newSaleOk = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Purchasable'),
                  value: _newPurchaseOk,
                  onChanged: (v) => setState(() => _newPurchaseOk = v),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(label: Text('Stock tracked')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _createNew,
                child:
                    const Text('Create & next', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
