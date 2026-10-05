// Browse inventory: search + category filter + paged list.
// Read-only (View) shows a detail sheet; editable (Manage) jumps straight
// into the Update-count loop prefilled with the item.
library;

import 'package:flutter/material.dart';

import '../odoo_client.dart';
import '../session_store.dart';
import 'receive.dart';

class BrowseScreen extends StatefulWidget {
  final OdooClient client;
  final String user;
  final bool editable;
  final String title;
  const BrowseScreen({
    super.key,
    required this.client,
    required this.user,
    required this.editable,
    this.title = 'Browse inventory',
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

  @override
  void initState() {
    super.initState();
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
      });
    } on OdooException catch (e) {
      if (mounted) setState(() => _err = e.message);
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
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _catName(int? id) {
    if (id == null) return '';
    final m = _cats.where((c) => c.id == id);
    return m.isEmpty ? '' : m.first.name;
  }

  void _onTap(InventoryProduct p) {
    if (widget.editable) {
      final code = p.barcode.isNotEmpty ? p.barcode : p.defaultCode;
      if (code.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No barcode/SKU — open Update count and type the name lookup there.')));
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

  Future<void> _showDetail(InventoryProduct p) async {
    final expiry = await SessionStore.loadExpiry(p.variantId);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(p.name,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('On hand: ${p.qtyAvailable.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            Text('Barcode: ${p.barcode.isEmpty ? '—' : p.barcode}'),
            Text('SKU: ${p.defaultCode.isEmpty ? '—' : p.defaultCode}'),
            Text(
                'Price: \$${p.listPrice.toStringAsFixed(2)} • Cost: \$${p.standardPrice.toStringAsFixed(2)}'),
            Text(
                'Category: ${_catName(p.posCategId).isEmpty ? '—' : _catName(p.posCategId)}'),
            Text('Expires: ${expiry ?? '—'}'),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Search name, barcode, or SKU',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _refresh(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: DropdownButtonFormField<int?>(
              initialValue: _catId,
              decoration: const InputDecoration(
                  labelText: 'Category', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('All categories')),
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
          Expanded(
            child: _rows.isEmpty && !_busy
                ? const Center(child: Text('No items found.'))
                : ListView.builder(
                    itemCount: _rows.length + (_more ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _rows.length) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: OutlinedButton(
                            onPressed: _busy ? null : _loadMore,
                            child: const Text('Load more'),
                          ),
                        );
                      }
                      final p = _rows[i];
                      return ListTile(
                        title: Text(p.name),
                        subtitle: Text(
                            '${p.barcode.isEmpty ? (p.defaultCode.isEmpty ? 'no code' : p.defaultCode) : p.barcode} • ${_catName(p.posCategId)}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(p.qtyAvailable.toStringAsFixed(0),
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            Text(
                                '\$${p.listPrice.toStringAsFixed(2)}',
                                style:
                                    const TextStyle(color: Colors.grey)),
                          ],
                        ),
                        onTap: () => _onTap(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
