// Native POS checkout: scan/search -> cart -> tender -> paid receipt.
// Cashier-first: huge touch targets, one-thumb flow, no WebView login.
// Server totals (pos.order read-back) are authoritative on the receipt.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/lang.dart';
import '../odoo_client.dart';
import '../widgets/feedback.dart';
import 'scan.dart';

class _CartItem {
  final PosProduct product;
  double qty;
  _CartItem({required this.product}) : qty = 1;
  double get lineTotal => PosCart.lineTotal(product.listPrice, qty);
}

class PosCheckoutScreen extends StatefulWidget {
  final OdooClient client;
  final String user;
  const PosCheckoutScreen({super.key, required this.client, this.user = ''});

  @override
  State<PosCheckoutScreen> createState() => _PosCheckoutScreenState();
}

class _PosCheckoutScreenState extends State<PosCheckoutScreen> {
  final _search = TextEditingController();
  final _tender = TextEditingController();

  bool _busy = false;
  String? _err;
  List<PosShop> _shops = [];
  int? _shopId;
  PosSession? _session;
  bool _sessionLoading = true;
  List<PosProduct> _results = [];
  bool _searching = false;
  final List<_CartItem> _cart = [];
  Map<int, PosTax> _taxes = {};
  List<PosPayMethod> _methods = [];
  int? _methodId;
  PosReceipt? _receipt;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _search.dispose();
    _tender.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _sessionLoading = true;
      _err = null;
    });
    try {
      final shops = await widget.client.posConfigs();
      if (!mounted) return;
      setState(() {
        _shops = shops;
        _shopId = shops.isEmpty ? null : shops.first.id;
      });
      if (_shopId != null) await _loadSession();
      try {
        final methods = await widget.client.posPaymentMethods();
        if (mounted && methods.isNotEmpty) {
          setState(() {
            _methods = methods;
            _methodId = methods
                .firstWhere((m) => m.isCash,
                    orElse: () => methods.first)
                .id;
          });
        }
      } catch (_) {}
    } on OdooException catch (e) {
      if (!mounted) return;
      setState(() => _err = _friendly(e.message));
    } finally {
      if (mounted) setState(() => _sessionLoading = false);
    }
  }

  String _friendly(String m) {
    if (m.startsWith('POS_UNAVAILABLE')) return t('pos_err_unavailable');
    if (m == 'SESSION_EXPIRED') return t('waste_err_session');
    return OdooException.friendly(m);
  }

  Future<void> _loadSession() async {
    final sid = _shopId;
    if (sid == null) return;
    setState(() => _sessionLoading = true);
    try {
      final s = await widget.client.openPosSession(sid);
      if (mounted) setState(() => _session = s);
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = _friendly(e.message));
    } finally {
      if (mounted) setState(() => _sessionLoading = false);
    }
  }

  Future<void> _scan() async {
    final v = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (v != null && v.trim().isNotEmpty && mounted) {
      _search.text = v.trim();
      await _searchNow();
    }
  }

  Future<void> _searchNow() async {
    final q = _search.text.trim();
    setState(() {
      _searching = true;
      _err = null;
    });
    try {
      final rows = await widget.client.posProducts(q);
      if (!mounted) return;
      setState(() => _results = rows);
      await _ensureTaxes(rows.expand((p) => p.taxIds).toSet().toList());
      // Exact barcode hit goes straight in the cart (scanner flow).
      final exact =
          rows.where((p) => p.barcode.toLowerCase() == q.toLowerCase());
      if (exact.isNotEmpty) _addToCart(exact.first);
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = _friendly(e.message));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _ensureTaxes(List<int> ids) async {
    final missing = ids.toSet().difference(_taxes.keys.toSet()).toList();
    if (missing.isEmpty) return;
    try {
      final got = await widget.client.posTaxes(missing);
      if (mounted) setState(() => _taxes = {..._taxes, ...got});
    } catch (_) {}
  }

  void _addToCart(PosProduct p) {
    setState(() {
      final i = _cart.indexWhere((c) => c.product.id == p.id);
      if (i >= 0) {
        _cart[i].qty += 1;
      } else {
        _cart.add(_CartItem(product: p));
      }
      _tender.text = _totals.total.toStringAsFixed(2);
    });
  }

  ({double subtotal, double tax, double total}) get _totals =>
      PosCart.totals(
          _cart
              .map((c) => (
                    price: c.product.listPrice,
                    qty: c.qty,
                    taxIds: c.product.taxIds
                  ))
              .toList(),
          _taxes);

  double get _tenderVal => double.tryParse(_tender.text.trim()) ?? 0;

  Future<void> _charge() async {
    final s = _session;
    if (s == null) {
      setState(() => _err = t('pos_err_nosession'));
      return;
    }
    if (_cart.isEmpty) {
      setState(() => _err = t('pos_err_empty'));
      return;
    }
    final mid = _methodId;
    if (mid == null) {
      setState(() => _err = t('pos_err_nomethod'));
      return;
    }
    final total = _totals.total;
    final tendered = _tenderVal;
    if (tendered < total - 0.005) {
      setState(() => _err = t('pos_err_short'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('pos_confirm_title')),
        content: Text(Lang.instance.f('pos_confirm_body', {
          'total': total.toStringAsFixed(2),
          'tendered': tendered.toStringAsFixed(2),
          'change': (tendered - total).toStringAsFixed(2),
        })),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('waste_cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('pos_charge_go'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final receipt = await widget.client.posCheckout(
        sessionId: s.id,
        lines: _cart
            .map((c) => PosCartLine(
                productId: c.product.id,
                qty: c.qty,
                priceUnit: c.product.listPrice,
                taxIds: c.product.taxIds))
            .toList(),
        tenders: [PosTender(methodId: mid, amount: tendered)],
      );
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _cart.clear();
        _tender.clear();
      });
      showOk(context, t('pos_paid_ok'));
    } on OdooException catch (e) {
      if (!mounted) return;
      setState(() => _err = _friendly(e.message));
      showErr(context, _friendly(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _totals;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('pos_title')),
        backgroundColor: const Color(0xFFF26522),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _registerBar(),
          if (_err != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: const Color(0xFFFDECEA),
              child: Text(_err!,
                  style: const TextStyle(color: Colors.red)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration:
                        InputDecoration(labelText: t('pos_search')),
                    onSubmitted: (_) => _searchNow(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _scan, child: Text(t('waste_scan'))),
                const SizedBox(width: 8),
                FilledButton.tonal(
                    onPressed: _searching ? null : _searchNow,
                    child: Text(t('waste_go'))),
              ],
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          if (_results.isNotEmpty)
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                itemCount: _results.length,
                itemBuilder: (c, i) {
                  final p = _results[i];
                  return Card(
                    child: InkWell(
                      onTap: () => _addToCart(p),
                      child: Container(
                        width: 170,
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text('\$${p.listPrice.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: _cart.isEmpty
                ? Center(child: Text(t('pos_empty_cart')))
                : ListView.builder(
                    itemCount: _cart.length,
                    itemBuilder: (c, i) {
                      final item = _cart[i];
                      return Card(
                        child: ListTile(
                          title: Text(item.product.name),
                          subtitle: Text(
                              '\$${item.product.listPrice.toStringAsFixed(2)} × ${item.qty.toStringAsFixed(0)} = \$${item.lineTotal.toStringAsFixed(2)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                  icon: const Icon(
                                      Icons.remove_circle_outline,
                                      size: 32),
                                  onPressed: () => setState(() {
                                        item.qty -= 1;
                                        if (item.qty <= 0) {
                                          _cart.removeAt(i);
                                        }
                                        _tender.text = _totals.total
                                            .toStringAsFixed(2);
                                      })),
                              Text(item.qty.toStringAsFixed(0),
                                  style: const TextStyle(fontSize: 18)),
                              IconButton(
                                  icon: const Icon(Icons.add_circle_outline,
                                      size: 32),
                                  onPressed: () => setState(() {
                                        item.qty += 1;
                                        _tender.text = _totals.total
                                            .toStringAsFixed(2);
                                      })),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          _totalsBar(totals),
        ],
      ),
    );
  }

  Widget _registerBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: _shops.isEmpty
                ? Text(t('pos_no_register'))
                : DropdownButtonFormField<int>(
                    initialValue: _shopId,
                    decoration:
                        InputDecoration(labelText: t('pos_register')),
                    items: _shops
                        .map((s) => DropdownMenuItem(
                            value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _shopId = v;
                        _session = null;
                      });
                      _loadSession();
                    },
                  ),
          ),
          const SizedBox(width: 8),
          if (_sessionLoading)
            const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (_session != null)
            Chip(
              avatar: const Icon(Icons.store,
                  size: 18, color: Colors.green),
              label: Text(_session!.name,
                  style: const TextStyle(fontSize: 12)),
            )
          else
            Chip(
              avatar:
                  const Icon(Icons.store_outlined, size: 18, color: Colors.red),
              label: Text(t('pos_closed'),
                  style: const TextStyle(fontSize: 12)),
            ),
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _loadSession),
        ],
      ),
    );
  }

  Widget _totalsBar(({double subtotal, double tax, double total}) totals) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black12)],
      ),
      child: Column(
        children: [
          if (_receipt != null)
            Card(
              color: const Color(0xFFE8F5E9),
              child: ListTile(
                leading: const Icon(Icons.check_circle,
                    color: Colors.green, size: 32),
                title: Text(_receipt!.reference),
                subtitle: Text(Lang.instance.f('pos_receipt_body', {
                  'total': _receipt!.total.toStringAsFixed(2),
                  'tendered': _receipt!.tendered.toStringAsFixed(2),
                  'change': _receipt!.change.toStringAsFixed(2),
                })),
                trailing: TextButton(
                  onPressed: () => setState(() => _receipt = null),
                  child: Text(t('pos_new_sale')),
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t('pos_subtotal')),
              Text('\$${totals.subtotal.toStringAsFixed(2)}'),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t('pos_tax')),
              Text('\$${totals.tax.toStringAsFixed(2)}'),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t('pos_total'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              Text('\$${totals.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _methods
                .map((m) => ChoiceChip(
                      label: Text(m.name),
                      selected: _methodId == m.id,
                      onSelected: (_) =>
                          setState(() => _methodId = m.id),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tender,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                  ],
                  decoration:
                      InputDecoration(labelText: t('pos_tendered')),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                  onPressed: () => setState(() => _tender.text =
                      totals.total.toStringAsFixed(2)),
                  child: Text(t('pos_exact'))),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700),
              onPressed: (_busy ||
                      _cart.isEmpty ||
                      _session == null ||
                      _tenderVal < totals.total - 0.005)
                  ? null
                  : _charge,
              child: Text(
                  '${t('pos_charge')} \$${totals.total.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 20)),
            ),
          ),
        ],
      ),
    );
  }
}
