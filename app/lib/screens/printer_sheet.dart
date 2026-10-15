// Label-printer management sheet (docs/07 Phase 2): radio + permission
// states, bonded-device picker, test ticket, darkness, forget.
//
// Only one app can hold a Classic SPP socket at a time — the sheet says
// so up front (Labelife contention is the common dead end).
library;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../i18n/lang.dart';
import '../print/printer_service.dart';
import '../print/spp_transport.dart';

/// Short device tag for chips and rows ('AA:BB:CC:C0:75' -> '···C0:75').
String shortMac(String mac) {
  final parts = mac.split(':').where((p) => p.isNotEmpty).toList();
  if (parts.length < 2) return mac;
  return '···${parts[parts.length - 2]}:${parts.last}';
}

Future<void> showPrinterSheet(BuildContext context) =>
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: SingleChildScrollView(child: _PrinterSheet()),
      ),
    );

class _PrinterSheet extends StatefulWidget {
  const _PrinterSheet();

  @override
  State<_PrinterSheet> createState() => _PrinterSheetState();
}

class _PrinterSheetState extends State<_PrinterSheet>
    with WidgetsBindingObserver {
  final _probe = SppTransport();
  bool _loading = true;
  bool _perm = false;
  bool _permLocked = false;
  bool _btOff = false;
  List<({String name, String mac})> _bonded = [];
  String? _err;
  String? _ok;
  String? _testing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the BT-enable dialog or App settings: re-read reality.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final st = await Permission.bluetoothConnect.status;
      if (!mounted) return;
      if (!st.isGranted) {
        setState(() {
          _loading = false;
          _perm = false;
          _permLocked = st.isPermanentlyDenied;
        });
        return;
      }
      try {
        final bonded = await _probe.bonded();
        if (!mounted) return;
        setState(() {
          _perm = true;
          _permLocked = false;
          _btOff = false;
          _bonded = bonded;
          _loading = false;
        });
      } on PrinterException catch (e) {
        if (!mounted) return;
        if (e.failure == PrinterFailure.bluetoothOff) {
          setState(() {
            _perm = true;
            _btOff = true;
            _loading = false;
          });
        } else {
          setState(() {
            _err = printerUserMessage(e);
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _requestPerm() async {
    final st = await Permission.bluetoothConnect.request();
    if (!mounted) return;
    if (st.isPermanentlyDenied) {
      await openAppSettings();
    }
    await _refresh();
  }

  Future<void> _enableBt() async {
    try {
      await const AndroidIntent(
        action: 'android.bluetooth.adapter.action.REQUEST_ENABLE',
      ).launch();
    } catch (_) {
      // No BT-enable activity (or test env): resume-refresh covers it.
    }
    await Future.delayed(const Duration(seconds: 1));
    await _refresh();
  }

  Future<void> _select(String name, String mac) async {
    setState(() {
      _testing = mac;
      _err = null;
      _ok = null;
    });
    try {
      final svc = PrinterService.instance;
      await svc.savePrinter(mac);
      await svc.printTicket(name, shortMac(mac));
      if (mounted) setState(() => _ok = t('ptr_test_ok'));
    } catch (e) {
      if (mounted) setState(() => _err = printerUserMessage(e));
    } finally {
      if (mounted) setState(() => _testing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PrinterService.instance,
      builder: (context, _) {
        final svc = PrinterService.instance;
        final saved = svc.address ?? '';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t('ptr_sheet_title'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Text(
                  saved.isEmpty
                      ? t('ptr_none')
                      : '${t('ptr_ready')} ${shortMac(saved)}',
                  style: TextStyle(
                      color: saved.isEmpty
                          ? Colors.grey.shade700
                          : Colors.green.shade800,
                      fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade700),
              ),
              child: Text(t('ptr_hint_labelife'),
                  style: const TextStyle(fontSize: 13)),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_err != null) ...[
              Text(_err!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _refresh,
                child: Text(t('ptr_refresh')),
              ),
            ] else if (!_perm) ...[
              Text(t('ptr_perm_msg')),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _requestPerm,
                child: Text(_permLocked
                    ? t('ptr_perm_settings')
                    : t('ptr_perm_allow')),
              ),
            ] else if (_btOff) ...[
              Text(t('ptr_bt_off_msg')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _enableBt,
                      child: Text(t('ptr_enable_bt')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _refresh,
                      child: Text(t('ptr_refresh')),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(t('ptr_choose'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (_bonded.isEmpty)
                Text(t('ptr_no_bonded'),
                    style: const TextStyle(color: Colors.grey))
              else
                for (final b in _bonded)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(b.name,
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(shortMac(b.mac)),
                    trailing: _testing == b.mac
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2))
                        : (b.mac == saved
                            ? const Icon(Icons.check_circle,
                                color: Colors.green)
                            : const Icon(Icons.print)),
                    onTap: _testing != null
                        ? null
                        : () => _select(b.name, b.mac),
                  ),
              if (_testing != null) ...[
                const SizedBox(height: 4),
                Text(t('ptr_testing'),
                    style: const TextStyle(color: Colors.grey)),
              ],
              if (_ok != null) ...[
                const SizedBox(height: 4),
                Text(_ok!,
                    style: TextStyle(color: Colors.green.shade800)),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(t('ptr_darkness'),
                      style:
                          const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () => svc.saveDarkness(svc.darkness - 1),
                  ),
                  Text('${svc.darkness}',
                      style: const TextStyle(fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => svc.saveDarkness(svc.darkness + 1),
                  ),
                ],
              ),
              if (saved.isNotEmpty)
                OutlinedButton(
                  onPressed: () async {
                    await svc.forgetPrinter();
                    if (mounted) setState(() {});
                  },
                  child: Text(t('ptr_forget')),
                ),
            ],
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }
}
