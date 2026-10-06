// Camera scanner screen: returns the first detected barcode via Navigator.pop.
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
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
  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim() ?? '';
      if (v.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  Future<void> _retry() async {
    try {
      await _controller.start();
    } catch (_) {
      // start() surfaces failures via errorBuilder; nothing to do here.
    }
  }

  Widget _errorFallback(
      BuildContext context, MobileScannerException error) {
    final denied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, size: 48),
            const SizedBox(height: 12),
            Text(
              denied
                  ? 'Camera permission denied — allow it in Settings, or go back and type the barcode.'
                  : 'Camera failed to start (${error.errorCode.message}). You can retry, or go back and type the barcode.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _retry,
              child: const Text('Retry camera'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan barcode'),
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
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: _errorFallback,
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Point at the barcode. Torch is top-right.'),
          ),
        ],
      ),
    );
  }
}
