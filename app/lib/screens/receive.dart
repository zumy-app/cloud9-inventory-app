// Receive screen: scan -> lookup -> save (found) or create (not found).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../batch_store.dart';
import '../odoo_client.dart';
import '../session_store.dart';
import 'scan.dart';

class ReceiveScreen extends StatefulWidget {
  final OdooClient client;
  const ReceiveScreen({super.key, required this.client});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _barcode = TextEditingController();
  bool _busy = false;
  String? _err;

  InventoryProduct? _found;
  bool _duplicate = false;

  final _cost = TextEditingController();
  final _price = TextEditingController();
  final _qty = TextEditingController(text: '1');
  bool _addLabel = true;

  // new-product form
  final _newName = TextEditingController();
  final _newCost = TextEditingController();
  final _newPrice = TextEditingController();
  final _newQty = TextEditingController(text: '1');
  List<PosCategory> _cats = [];
  int? _catId;
  bool _catsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCats();
  }

  @override
  void dispose() {
    _barcode.dispose();
    _cost.dispose();
    _price.dispose();
    _qty.dispose();
    _newName.dispose();
    _newCost.dispose();
    _newPrice.dispose();
    _newQty.dispose();
    super.dispose();
  }

  Future<void> _loadCats() async {
    setState(() => _catsLoading = true);
    try {
      final cats = await widget.client.getPosCategories();
      final last = await SessionStore.loadLastPosCat();
      if (!mounted) return;
      setState(() {
        _cats = cats;
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

  Future<void> _lookup() async {
    final code = _barcode.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _err = null;
      _found = null;
    });
    try {
      final res = await widget.client.lookupProduct(code);
      if (!mounted) return;
      if (res == null) {
        setState(() {
          _newName.text = '';
          _newCost.text = '';
          _newPrice.text = '';
          _newQty.text = '1';
        });
      } else {
        _cost.text = res.product.standardPrice.toStringAsFixed(2);
        _price.text = res.product.listPrice.toStringAsFixed(2);
        _qty.text = '1';
        setState(() {
          _found = res.product;
          _duplicate = res.duplicate;
        });
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

  double _num(String s) => double.tryParse(s.trim()) ?? double.nan;

  Future<void> _saveFound() async {
    final p = _found;
    if (p == null || _busy) return;
    final cost = _num(_cost.text);
    final price = _num(_price.text);
    final qty = _num(_qty.text);
    if (cost.isNaN || price.isNaN || qty.isNaN || qty <= 0) {
      setState(() => _err = 'Enter valid cost, price and qty > 0.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.client.updatePrices(p, price, cost);
      await widget.client.addStock(p, qty);
      if (_addLabel) {
        BatchStore.instance.add(
            barcode: p.barcode.isNotEmpty ? p.barcode : _barcode.text.trim(),
            name: p.name,
            price: price);
      }
      if (_catId != null) {
        // Remember last used category even on save (cheap, keeps default fresh).
        await SessionStore.saveLastPosCat(_catId!);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${p.name} × $qty')));
      setState(() {
        _barcode.clear();
        _found = null;
      });
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
    final cost = _num(_newCost.text);
    final price = _num(_newPrice.text);
    final qty = _num(_newQty.text);
    if (name.isEmpty) {
      setState(() => _err = 'Name is required.');
      return;
    }
    if (_catId == null) {
      setState(() => _err = 'Pick a POS category.');
      return;
    }
    if (cost.isNaN || price.isNaN || qty.isNaN || qty < 0) {
      setState(() => _err = 'Enter valid cost, price and qty.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.client.createProduct(
        name: name,
        barcode: code,
        posCategId: _catId!,
        listPrice: price,
        standardPrice: cost,
        qty: qty,
      );
      await SessionStore.saveLastPosCat(_catId!);
      BatchStore.instance.add(barcode: code, name: name, price: price);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Created $name')));
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

  @override
  Widget build(BuildContext context) {
    final code = _barcode.text.trim();
    final showCreate = code.isNotEmpty && _found == null && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
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
          if (_found != null) _foundCard(_found!),
          if (showCreate && _found == null) _createCard(code),
        ],
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
                'Barcode: ${p.barcode.isNotEmpty ? p.barcode : '—'}  •  On-hand: ${p.qtyAvailable.toStringAsFixed(0)}'),
            if (_duplicate)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Warning: duplicate barcode — showing first match.',
                    style: TextStyle(color: Colors.orange)),
              ),
            const SizedBox(height: 12),
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
            TextField(
              controller: _qty,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Qty received', border: OutlineInputBorder()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Add to label batch'),
              value: _addLabel,
              onChanged: (v) => setState(() => _addLabel = v),
            ),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _saveFound,
                child: const Text('Save & next',
                    style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _createCard(String code) {
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
            _catsLoading
                ? const LinearProgressIndicator()
                : DropdownButtonFormField<int>(
                    initialValue: _catId,
                    decoration: const InputDecoration(
                        labelText: 'POS category *',
                        border: OutlineInputBorder()),
                    items: _cats
                        .map((c) => DropdownMenuItem(
                            value: c.id, child: Text(c.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _catId = v),
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
                        labelText: 'Cost', border: OutlineInputBorder()),
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
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _createNew,
                child:
                    const Text('Create', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
