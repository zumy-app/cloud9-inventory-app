// Continuous scan sheet: stays open, rapid qty capture.
// Receive: qty auto-saves on scan-away. Count: every write needs the
// before → after confirm first — no silent absolute writes.
// Every outcome ends in the result banner (success green, failure red);
// touched price/SKU/category text never auto-persists.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../audit_log.dart';
import '../odoo_client.dart';

class ScanSheet extends StatefulWidget {
  final OdooClient client;
  final String user;
  final String mode; // 'receive' | 'count'
  final List<PosCategory> posCats;
  final List<PosCategory> internalCats;

  const ScanSheet({
    super.key,
    required this.client,
    required this.user,
    required this.mode,
    this.posCats = const [],
    this.internalCats = const [],
  });

  @override
  State<ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<ScanSheet> {
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );
  final _manual = TextEditingController();
  final _qty = TextEditingController(text: '1');

  bool _torch = false;
  bool _busy = false;
  String? _err;
  int _scans = 0;
  String _lastCode = '';
  DateTime _lastTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Last save outcome, shown as a persistent banner so every workflow ends
  // with visible success/failure feedback (not just a beep + counter).
  String? _lastResult;
  bool _lastOk = true;

  void _say(String msg, {bool ok = true}) {
    if (!mounted) return;
    setState(() {
      _lastResult = msg;
      _lastOk = ok;
      _err = null;
    });
  }

  InventoryProduct? _pending;
  bool _textDirty = false;

  bool get _isCount => widget.mode == 'count';

  @override
  void dispose() {
    _controller.dispose();
    _manual.dispose();
    _qty.dispose();
    super.dispose();
  }

  void _beep() {
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  }

  Future<void> _onCode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty || _busy) return;
    final now = DateTime.now();
    if (code == _lastCode &&
        now.difference(_lastTime).inMilliseconds < 700) {
      return; // same-code lockout
    }
    _lastCode = code;
    _lastTime = now;
    if (_pending != null && code == _pending!.barcode) {
      await _quickPlusOne();
      return;
    }
    if (_pending != null) {
      final ok = await _ensurePendingSaved();
      if (!ok) return;
    }
    await _load(code);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim() ?? '';
      if (v.isNotEmpty) {
        _onCode(v);
        return;
      }
    }
  }

  Future<void> _retryCamera() async {
    try {
      await _controller.start();
    } catch (_) {
      // Failures surface via errorBuilder; nothing to do here.
    }
  }

  Widget _errorFallback(BuildContext context, MobileScannerException error) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, size: 40),
            const SizedBox(height: 8),
            Text(
              denied
                  ? 'Camera permission denied — allow it in Settings, or type the barcode below.'
                  : 'Camera failed to start (${error.errorCode.message}). Retry, or type the barcode below.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _retryCamera,
              child: const Text('Retry camera'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _load(String code) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final rows = await widget.client.findVariants(code);
      if (!mounted) return;
      if (rows.isEmpty) {
        setState(() => _err = 'Not in Odoo: $code — create it in single mode.');
        return;
      }
      if (rows.length > 1) {
        setState(() =>
            _err = 'Duplicate barcode — pick the variant in single mode.');
        return;
      }
      setState(() {
        _pending = rows.first;
        _qty.text = '1';
        _textDirty = false;
      });
      _beep();
      setState(() => _scans++);
    } on OdooException catch (e) {
      if (mounted) {
        setState(() => _err =
            e.message == 'SESSION_EXPIRED' ? 'Session expired — sign in again.' : e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Rescan of the same barcode: qty++ and auto-save immediately
  /// (receive: +1; count: not auto-saved — qty field increments for confirm).
  Future<void> _quickPlusOne() async {
    final p = _pending;
    if (p == null || _busy) return;
    if (_isCount) {
      final q = (double.tryParse(_qty.text.trim()) ?? 0) + 1;
      setState(() => _qty.text = q.toStringAsFixed(0));
      _beep();
      return;
    }
    setState(() => _busy = true);
    try {
      final after = await widget.client.addStock(p, 1);
      _audit(p, 'qty', p.qtyAvailable.toStringAsFixed(0),
          after.toStringAsFixed(0), 'quick +1');
      _beep();
      if (!mounted) return;
      setState(() {
        _scans++;
        _pending = null;
        _qty.text = '1';
      });
      _say('Saved ${p.name} +1 → ${after.toStringAsFixed(0)}');
    } on OdooException catch (e) {
      _say(e.message, ok: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Before → after confirm for continuous counts (same rule as single
  /// mode). Factored out so no BuildContext crosses an async gap.
  Future<bool> _confirmCount(InventoryProduct p, double qty) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm count'),
        content: Text(
            '${p.name}\n${p.qtyAvailable.toStringAsFixed(0)} → ${qty.toStringAsFixed(0)}'),
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
    return ok == true;
  }

  /// Save pending qty (qty only — never text fields) before moving on.
  /// Count mode always shows the before → after confirm first (same rule as
  /// single mode) — no silent absolute writes. Every outcome ends in the
  /// result banner. Returns false when blocked/cancelled: the caller must
  /// stay on the pending item.
  Future<bool> _ensurePendingSaved() async {
    final p = _pending;
    if (p == null) return true;
    if (_textDirty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Unsaved edits'),
          content: Text('${p.name} has unconfirmed price/detail edits.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop('discard'),
                child: const Text('Discard')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop('single'),
                child: const Text('Edit in single mode')),
          ],
        ),
      );
      if (choice == null) return false;
      if (choice == 'single') {
        if (mounted) Navigator.of(context).pop();
        return false;
      }
      if (mounted) setState(() => _textDirty = false);
    }
    final qty = double.tryParse(_qty.text.trim()) ?? double.nan;
    // Count is absolute (0 allowed, like single mode); receive adds (≥ 1).
    final minQty = _isCount ? 0.0 : 1.0;
    if (qty.isNaN || qty < minQty) {
      _say(_isCount
          ? 'Pending ${p.name} has invalid qty — enter 0 or more.'
          : 'Pending ${p.name} has invalid qty — fix or clear it.');
      return false;
    }
    if (_isCount) {
      final confirmed = await _confirmCount(p, qty);
      if (!confirmed || !mounted) return false;
    }
    setState(() => _busy = true);
    try {
      final before = p.qtyAvailable;
      final after = _isCount
          ? await widget.client.setStock(p, qty)
          : await widget.client.addStock(p, qty);
      _audit(p, 'qty', before.toStringAsFixed(0), after.toStringAsFixed(0),
          'continuous');
      _beep();
      if (!mounted) return false;
      setState(() {
        _scans++;
        _pending = null;
        _qty.text = '1';
        _textDirty = false;
      });
      _say(_isCount
          ? 'Counted ${p.name}: ${before.toStringAsFixed(0)} → ${after.toStringAsFixed(0)}'
          : 'Saved ${p.name} +${qty.toStringAsFixed(0)} → ${after.toStringAsFixed(0)}');
      return true;
    } on OdooException catch (e) {
      _say(
          e.message == 'SESSION_EXPIRED'
              ? 'Session expired — sign in again.'
              : e.message,
          ok: false);
      return false;
    } catch (e) {
      _say(e.toString(), ok: false);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _audit(InventoryProduct p, String field, String oldV, String newV,
      String note) {
    AuditLog.instance.add(AuditEntry(
      when: DateTime.now(),
      who: widget.user,
      mode: _isCount ? 'count' : 'receive',
      productId: p.variantId,
      productName: p.name,
      field: field,
      oldValue: oldV,
      newValue: newV,
      reason: note,
    ));
  }

  /// Leaving with a pending item ends the workflow with an explicit
  /// choice — save (with the count confirm when in count mode), discard,
  /// or stay. Nothing is silently dropped.
  Future<void> _exit() async {
    final p = _pending;
    if (p != null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Leave continuous?'),
          content: Text('${p.name} has an unsaved qty.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop('stay'),
                child: const Text('Stay')),
            TextButton(
                onPressed: () => Navigator.of(context).pop('discard'),
                child: const Text('Discard')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop('save'),
                child: const Text('Save & exit')),
          ],
        ),
      );
      if (choice == null || choice == 'stay' || !mounted) return;
      if (choice == 'save') {
        final ok = await _ensurePendingSaved();
        if (!ok) return;
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = _pending;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Exit',
          icon: const Icon(Icons.close),
          onPressed: _exit,
        ),
        title: Text(
            '${_isCount ? 'Count' : 'Receive'} continuous ($_scans)'),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              await _controller.toggleTorch();
              setState(() => _torch = !_torch);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 220,
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: _errorFallback,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manual,
                    decoration: const InputDecoration(
                        labelText: 'Type barcode + Go',
                        border: OutlineInputBorder()),
                    textInputAction: TextInputAction.go,
                    onSubmitted: (v) {
                      _manual.clear();
                      _onCode(v);
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_err!,
                  style: const TextStyle(color: Colors.red)),
            ),
          if (_lastResult != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Card(
                color: _lastOk
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Icon(
                        _lastOk
                            ? Icons.check_circle
                            : Icons.error,
                        color: _lastOk ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_lastResult!)),
                    ],
                  ),
                ),
              ),
            ),
          if (p != null)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(p.name,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          Text(
                              'On-hand: ${p.qtyAvailable.toStringAsFixed(0)} • \$${p.listPrice.toStringAsFixed(2)}'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove),
                                onPressed: () {
                                  final q =
                                      (double.tryParse(_qty.text.trim()) ??
                                              1) -
                                          1;
                                  setState(() => _qty.text =
                                      (q < 1 ? 1 : q).toStringAsFixed(0));
                                },
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _qty,
                                  textAlign: TextAlign.center,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(),
                                  decoration: InputDecoration(
                                      labelText: _isCount
                                          ? 'Counted'
                                          : 'Qty',
                                      border: const OutlineInputBorder()),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () {
                                  final q =
                                      (double.tryParse(_qty.text.trim()) ??
                                              0) +
                                          1;
                                  setState(() => _qty.text =
                                      q.toStringAsFixed(0));
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: _busy ? null : _quickPlusOne,
                                  child: Text(_isCount ? '+1' : '+1 save'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _ensurePendingSaved(),
                                  child: Text(_isCount
                                      ? 'Set count'
                                      : 'Save qty'),
                                ),
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () {
                                setState(() => _textDirty = true);
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Price/detail edits: use single mode')));
                              },
                              child: const Text(
                                  'Edit price/details (single mode)'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            const Expanded(
              child: Center(
                  child: Text('Point at a barcode — beep means captured.',
                      textAlign: TextAlign.center)),
            ),
        ],
      ),
    );
  }
}
