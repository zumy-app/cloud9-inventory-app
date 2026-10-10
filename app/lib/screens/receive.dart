// Receive / Count screen: scan -> lookup -> save (found) or create (not found).
// Two modes: Receive + (additive) vs Count = (absolute). See docs/01-MVP.md.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audit_log.dart';
import '../label_collections.dart';
import '../category_map.dart';
import '../i18n/lang.dart';
import '../odoo_client.dart';
import '../price_guard.dart';
import '../print/label_model.dart';
import '../print/printer_service.dart';
import '../session_store.dart';
import '../widgets/category_picker.dart';
import '../widgets/feedback.dart';
import 'scan.dart';
import 'scan_sheet.dart';

class ReceiveScreen extends StatefulWidget {
  final OdooClient client;
  final String user;
  final String initialBarcode;
  final String initialMode; // 'receive' | 'count' | '' (= stored pref)
  final String initialName; // prefill for the new-product form (Manage add)
  final bool initialNoBarcode; // free-text Manage add: no barcode scanned
  const ReceiveScreen(
      {super.key,
      required this.client,
      this.user = '',
      this.initialBarcode = '',
      this.initialMode = '',
      this.initialName = '',
      this.initialNoBarcode = false});

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
  bool _noBarcode = false;
  bool _quantBlocked = false;
  // Language-independent flag: a SKU collision is pending 'Use anyway'.
  // (Never match on translated error text.)
  bool _skuBlocked = false;
  Future<void> Function()? _retrySave;
  bool _converting = false;

  bool _isQuantBlocked(String msg) =>
      msg.contains('Quants') || msg.contains('refuses stock');

  void _resetSaveState() {
    _quantBlocked = false;
    _skuBlocked = false;
    _retrySave = null;
    _reasonRequired = false;
    _skuOverride = false;
  }

  // new-product form
  final _newName = TextEditingController();
  String _nameSeed = ''; // one-shot prefill from Manage (consumed on use)
  final _newSku = TextEditingController();
  final _newCost = TextEditingController();
  final _newPrice = TextEditingController();
  final _newQty = TextEditingController(text: '1');
  bool _newSaleOk = true;
  bool _newPurchaseOk = true;
  List<PosCategory> _cats = [];
  List<PosCategory> _internalCats = [];
  int? _catId;
  List<int> _recentCats = [];
  bool _catsLoading = false;

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
    _nameSeed = widget.initialName.trim();
    _noBarcode = widget.initialNoBarcode;
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
        final seed = _nameSeed;
        _nameSeed = '';
        setState(() {
          _newName.text = seed;
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
        setState(() => _err = t('recv_session'));
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
    _resetSaveState();
    setState(() {
      _found = p;
      _duplicates = [];
      _showPriceAdjust = false;
    });
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

  /// Shared validation + price-guard for the found card.
  /// Returns null when blocked (sets _err).
  ({double cost, double price, String reason})? _checkPrices(
      InventoryProduct p) {
    final cost = _num(_cost.text);
    final price = _num(_price.text);
    if (cost.isNaN || price.isNaN || cost < 0 || price < 0) {
      setState(() => _err = t('recv_err_costprice'));
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
      setState(() {
        _err = Lang.instance
            .f('recv_err_sku', {'name': clash.first.name});
        _skuBlocked = true;
      });
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
  }

  void _afterSave(String toast) {
    if (!mounted) return;
    showOk(context, toast);
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
        LabelCollections.instance.addToActive(
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
      _afterSave(Lang.instance.f('recv_saved',
          {'name': p.name, 'qty': '$qty', 'after': '$after'}));
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
      showErr(context,
          Lang.instance.f('toast_fail', {'detail': e.message}));
    } catch (e) {
      if (mounted) {
        setState(() => _err = e.toString());
        showErr(context,
            Lang.instance.f('toast_fail', {'detail': e.toString()}));
      }
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
        LabelCollections.instance.addToActive(
          barcode: p.barcode.isNotEmpty ? p.barcode : _barcode.text.trim(),
          name: p.name,
          price: price,
          defaultCode: p.defaultCode,
          category: _catLabel(),
        );
      }
      _afterSave(Lang.instance.f(
          'recv_counted', {'name': p.name, 'after': '$after'}));
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
      showErr(context,
          Lang.instance.f('toast_fail', {'detail': e.message}));
    } catch (e) {
      if (mounted) {
        setState(() => _err = e.toString());
        showErr(context,
            Lang.instance.f('toast_fail', {'detail': e.toString()}));
      }
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
        showOk(context,
            Lang.instance.f('recv_storable', {'name': p.name}));
      }
    } on OdooException catch (e) {
      if (mounted) {
        setState(() => _err = e.message);
        showErr(context,
            Lang.instance.f('toast_fail', {'detail': e.message}));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _err = e.toString());
        showErr(context,
            Lang.instance.f('toast_fail', {'detail': e.toString()}));
      }
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  /// Archive with a mandatory name confirm: deactivates the template in
  /// Odoo (reversible via the Archived filter). Used for duplicates / bad
  /// items, e.g. a product created on the wrong barcode.
  Future<void> _confirmArchive(InventoryProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('recv_archive_title')),
        content: Text(Lang.instance.f('recv_archive_msg', {
          'name': p.name,
          'code': p.barcode.isEmpty ? '—' : p.barcode
        })),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t('recv_cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t('recv_archive_btn'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.client.archiveProduct(p);
      _audit('archive', p, 'active', 'true', 'false', 'in-app cleanup');
      if (_duplicates.any((d) => d.variantId == p.variantId)) {
        setState(() =>
            _duplicates.removeWhere((d) => d.variantId == p.variantId));
      }
      if (_found?.variantId == p.variantId) {
        _afterSave(
            Lang.instance.f('recv_archived', {'name': p.name}));
      } else if (mounted) {
        showOk(context,
            Lang.instance.f('recv_archived', {'name': p.name}));
        setState(() => _busy = false);
      }
    } on OdooException catch (e) {
      if (mounted) {
        setState(() => _err = e.message);
        showErr(context,
            Lang.instance.f('toast_fail', {'detail': e.message}));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _err = e.toString());
        showErr(context,
            Lang.instance.f('toast_fail', {'detail': e.toString()}));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Receive + : single Update button (details + optional stock add).
  Future<void> _updateItem() async {
    final p = _found;
    if (p == null || _busy) return;
    if (_name.text.trim().length < 2 && _name.text.trim() != p.name) {
      setState(() => _err = t('recv_err_name2'));
      return;
    }
    final qtyRaw = _qty.text.trim();
    final qty = qtyRaw.isEmpty ? 0.0 : _num(qtyRaw);
    if (qty.isNaN || qty < 0) {
      setState(() => _err = t('recv_err_qty_add'));
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
        _afterSave(
            Lang.instance.f('recv_updated', {'name': p.name}));
      }
    } on OdooException catch (e) {
      if (mounted) {
        setState(() => _err = e.message);
        showErr(context,
            Lang.instance.f('toast_fail', {'detail': e.message}));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _err = e.toString());
        showErr(context,
            Lang.instance.f('toast_fail', {'detail': e.toString()}));
      }
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
      setState(() => _err = t('recv_err_count_blank'));
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
        _afterSave(Lang.instance
            .f('recv_prices_updated', {'name': p.name}));
      } on OdooException catch (e) {
        if (mounted) {
          setState(() => _err = e.message);
          showErr(context,
              Lang.instance.f('toast_fail', {'detail': e.message}));
        }
      } catch (e) {
        if (mounted) {
          setState(() => _err = e.toString());
          showErr(context,
              Lang.instance.f('toast_fail', {'detail': e.toString()}));
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final counted = _num(_qty.text);
    if (counted.isNaN || counted < 0) {
      setState(() => _err = t('recv_err_counted'));
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
        title: Text(t('recv_confirm_count')),
        content: Text(
            '${p.name}\n${p.qtyAvailable.toStringAsFixed(0)} → ${counted.toStringAsFixed(0)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t('recv_cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t('recv_confirm'))),
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
      if (mounted) {
        setState(() => _err = e.message);
        showErr(context,
            Lang.instance.f('toast_fail', {'detail': e.message}));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _err = e.toString());
        showErr(context,
            Lang.instance.f('toast_fail', {'detail': e.toString()}));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createNew() async {
    final code = _noBarcode ? '' : _barcode.text.trim();
    final name = _newName.text.trim();
    final sku = _newSku.text.trim();
    final cost = _num(_newCost.text);
    final price = _num(_newPrice.text);
    final qty = _num(_newQty.text);
    if (name.length < 2) {
      setState(() => _err = t('recv_err_new_name'));
      return;
    }
    if (_noBarcode && sku.isEmpty) {
      setState(() => _err = t('add_sku_required'));
      return;
    }
    if (_catId == null) {
      setState(() => _err = t('recv_err_pickcat'));
      return;
    }
    final pair = _pair;
    if (pair == null) {
      setState(() => _err = t('recv_err_cats'));
      return;
    }
    if (cost.isNaN || price.isNaN || qty.isNaN || cost < 0 || price < 0 || qty < 0) {
      setState(() => _err = t('recv_err_nums'));
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
        setState(() => _err = Lang.instance
            .f('recv_err_sku_new', {'name': hits.first.name}));
        return;
      }
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      // Barcode collision: never create a second product on a used barcode
      // (matches barcode OR SKU, same as lookup). Open it instead.
      final clash = await widget.client.findVariants(code);
      if (clash.isNotEmpty) {
        if (!mounted) return;
        if (clash.length == 1) {
          _fillFound(clash.first);
        } else {
          setState(() => _duplicates = clash);
        }
        if (mounted) {
          setState(() => _err = Lang.instance.f(
              'recv_barcode_inuse', {'name': clash.first.name}));
        }
        return;
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
        saleOk: _newSaleOk,
        purchaseOk: _newPurchaseOk,
      );
      await SessionStore.saveLastPosCat(pair.posId);
      final recent = await SessionStore.loadRecentPosCats();
      if (!mounted) return;
      setState(() => _recentCats = recent);
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
        newValue: 'qty ${qty.toStringAsFixed(0)}, $name',
        reason: reason,
      ));
      if (!mounted) return;
      showOk(context, Lang.instance
          .f('recv_created', {'name': name, 'qty': '$qty'}));
      setState(() {
        _barcode.clear();
        _newName.clear();
      });
    } on OdooException catch (e) {
      if (mounted) {
        setState(() => _err = e.message);
        showErr(context,
            Lang.instance.f('toast_fail', {'detail': e.message}));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _err = e.toString());
        showErr(context,
            Lang.instance.f('toast_fail', {'detail': e.toString()}));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Print one label for the current card via the paired printer.
  /// Unconfigured transport surfaces as a pairing prompt, never a crash.
  Future<void> _printLabel(InventoryProduct p) async {
    try {
      final price = _num(_price.text);
      await PrinterService.instance.printLabel(
        LabelModel.fromProduct(p,
            priceOverride: price.isNaN ? null : price),
      );
      if (mounted) {
        showOk(context,
            Lang.instance.f('recv_label_sent', {'name': p.name}));
      }
    } catch (e) {
      if (mounted) showErr(context, '$e');
    }
  }

  Future<String?> _askReason(String why) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('recv_reason_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(why),
            const SizedBox(height: 8),
            TextField(
                controller: c,
                decoration: InputDecoration(
                    labelText: t('recv_reason_label'),
                    border: const OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('recv_cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(c.text.trim()),
              child: Text(t('recv_continue'))),
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
        title: Text(_isCount ? t('recv_update_title') : t('recv_receive_title')),
        actions: [
          IconButton(
            tooltip: t('recv_rapid'),
            icon: const Icon(Icons.burst_mode),
            onPressed: _busy ? null : _openContinuous,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              icon: const Icon(Icons.qr_code_scanner, size: 28),
              label: Text(t('recv_scan'), style: const TextStyle(fontSize: 20)),
              onPressed: _busy ? null : _scan,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _barcode,
                  decoration: InputDecoration(
                    labelText: t('recv_barcode_hint'),
                    border: const OutlineInputBorder(),
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
                      : Text(t('recv_go')),
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
          Text(Lang.instance.f('recv_convert_title', {'kind': kind}),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(t('recv_convert_sub')),
          const SizedBox(height: 8),
          FilledButton(
            onPressed:
                (_busy || _converting) ? null : _convertAndRetry,
            child: Text(_converting
                ? t('recv_converting')
                : (_retrySave != null
                    ? t('recv_convert_retry')
                    : t('recv_convert_btn'))),
          ),
        ],
      ),
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
            Text(t('recv_dup_title'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(t('recv_dup_sub')),
            const SizedBox(height: 8),
            ..._duplicates.map((d) => ListTile(
                  title: Text(d.name),
                      subtitle: Text(
                      '${t('browse_sku')} ${d.defaultCode.isEmpty ? '—' : d.defaultCode} • ${Lang.instance.f('browse_onhand', {'qty': d.qtyAvailable.toStringAsFixed(0)})}'),
                    trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: Lang.instance
                            .f('recv_archive_tip', {'name': d.name}),
                        icon: const Icon(Icons.archive_outlined,
                            color: Colors.red),
                        onPressed:
                            _busy ? null : () => _confirmArchive(d),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => _fillFound(d),
                )),
          ],
        ),
      ),
    );
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
                '${t('browse_barcode')} ${p.barcode.isNotEmpty ? p.barcode : '—'}  •  ${Lang.instance.f('browse_onhand', {'qty': p.qtyAvailable.toStringAsFixed(0)})}'),
            if (!p.tracksStock || _quantBlocked) ...[
              const SizedBox(height: 8),
              _convertBanner(p),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                  labelText: t('recv_name'),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _sku,
              decoration: InputDecoration(
                  labelText: t('recv_sku'),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            if (!_isCount || _showPriceAdjust) ...[
              TextField(
                controller: _cost,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: t('recv_cost'),
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: t('recv_price'),
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
            ],
            if (_isCount && !_showPriceAdjust)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _showPriceAdjust = true),
                  child: Text(t('recv_adjust_price')),
                ),
              ),
            TextField(
              controller: _qty,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText:
                      _isCount ? t('recv_qty_count') : t('recv_qty_add'),
                  helperText: _isCount
                      ? t('recv_qty_help_count')
                      : t('recv_qty_help_receive'),
                  border: const OutlineInputBorder()),
            ),
            if (_reasonRequired) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _reason,
                decoration: InputDecoration(
                    labelText: t('recv_reason_req'),
                    border: const OutlineInputBorder()),
              ),
            ],
            if (_skuBlocked) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _skuOverride = true;
                    _skuBlocked = false;
                    _err = null;
                  }),
                  child: Text(t('recv_use_anyway')),
                ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('recv_add_label')),
              value: _addLabel,
              onChanged: (v) => setState(() => _addLabel = v),
            ),
            if (!_isCount)
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _updateItem,
                  child: Text(t('recv_update'),
                      style: const TextStyle(fontSize: 18)),
                ),
              ),
            if (_isCount)
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _setCount,
                  child: Text(t('recv_setcount'),
                      style: const TextStyle(fontSize: 18)),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.print),
                label: Text(t('recv_print'),
                    style: const TextStyle(fontSize: 16)),
                onPressed: _busy ? null : () => _printLabel(p),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.archive_outlined,
                    color: Colors.red, size: 18),
                label: Text(t('recv_archive'),
                    style: const TextStyle(color: Colors.red)),
                onPressed: _busy ? null : () => _confirmArchive(p),
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
            Text(t('recv_new_title'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(Lang.instance.f('recv_new_barcode',
                {'code': code.isEmpty ? '—' : code})),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(t('add_nobarcode')),
              subtitle: Text(t('add_nobarcode_hint')),
              value: _noBarcode,
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                        _noBarcode = v ?? false;
                        _err = null;
                      }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newName,
              decoration: InputDecoration(
                  labelText: t('recv_new_name'),
                  border: const OutlineInputBorder()),
              // Refresh keyword ranking in the picker as the name is typed.
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _newSku,
              decoration: InputDecoration(
                  labelText: t('recv_sku'),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            _recentChips(),
            _catsLoading
                ? const LinearProgressIndicator()
                : CategoryPickerField(
                    categories: _cats,
                    selectedId: _catId,
                    productName: _newName.text,
                    onSelected: (id) => setState(() => _catId = id),
                  ),
            if (_catId != null && pair == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t('recv_cats_loading'),
                    style: const TextStyle(color: Colors.grey)),
              ),
            if (pair != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    _isExactPair
                        ? Lang.instance.f('recv_maps_to', {
                            'a': pair.internalName,
                            'b': pair.posName
                          })
                        : Lang.instance.f('recv_maps_to_fb', {
                            'a': pair.internalName,
                            'b': pair.posName
                          }),
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
                    decoration: InputDecoration(
                        labelText: t('add_cost'),
                        border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _newPrice,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                        labelText: t('add_price'),
                        border: const OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _newQty,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                        labelText: t('add_qty'),
                        border: const OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text(t('add_details')),
              tilePadding: EdgeInsets.zero,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('add_sellable')),
                  value: _newSaleOk,
                  onChanged: (v) => setState(() => _newSaleOk = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('add_purchasable')),
                  value: _newPurchaseOk,
                  onChanged: (v) => setState(() => _newPurchaseOk = v),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(label: Text(t('add_stocktracked'))),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _createNew,
                child: Text(t('recv_create'),
                    style: const TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
