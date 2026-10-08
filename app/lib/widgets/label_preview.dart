// On-screen mirror of the 2"x1" thermal label (see lib/print/tspl.dart).
// Layout-faithful, not dot-faithful: same vertical order
// (logo / name+size + BIG price / big barcode) and same truncation rules,
// rendered with Flutter text + barcode_widget bars. Used in the Labels tab,
// detail sheets, print confirm, and the print-job status rows.
library;

import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:flutter/material.dart';

import '../print/label_model.dart';
import '../print/tspl.dart';

class LabelPreview extends StatelessWidget {
  final LabelModel model;
  final bool compact;
  const LabelPreview({super.key, required this.model, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final code = model.code;
    final sym = Tspl.symbologyFor(code);
    return AspectRatio(
      aspectRatio: 2 / 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(compact ? 4 : 8),
        ),
        padding: EdgeInsets.all(compact ? 6 : 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo row (mirrors TSPL BITMAP top-center; blank gap on failure).
            SizedBox(
              height: compact ? 14 : 24,
              child: Center(
                child: Image.asset(
                  'assets/logo.png',
                  height: compact ? 14 : 24,
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, err, stack) => Text(
                    'CLOUD 9 MARKET',
                    style: TextStyle(
                      fontSize: compact ? 8 : 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 2 : 4),
            // Name + size (left) + BIG price (right).
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    model.displayName,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 11 : 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  model.priceText,
                  style: TextStyle(
                    fontSize: compact ? 16 : 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 2 : 4),
            // Big barcode zone.
            Expanded(
              child: code.isEmpty
                  ? const Center(
                      child: Text(
                        'NO BARCODE',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: bw.BarcodeWidget(
                            barcode: sym == 'EAN13'
                                ? bw.Barcode.ean13()
                                : bw.Barcode.code128(),
                            data: code,
                            drawText: false,
                            errorBuilder: (ctx, err) => const Center(
                                child: Text('BARCODE ERROR',
                                    style: TextStyle(fontSize: 10))),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          code,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: compact ? 9 : 11,
                              letterSpacing: 2),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full preview bottom sheet: large preview + label facts.
/// Optional [sizeField] hook is wired by the collections UI; when null
/// the size row is read-only.
Future<void> showLabelPreviewSheet(
  BuildContext context,
  LabelModel model, {
  ValueChanged<String>? onSizeChanged,
  String? initialSize,
}) {
  final sizeCtrl = TextEditingController(text: initialSize ?? model.size);
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabelPreview(model: model),
          const SizedBox(height: 12),
          Text(model.displayName,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(
              '${model.code.isEmpty ? 'NO BARCODE' : model.code}  •  ${model.priceText}'),
          if (onSizeChanged != null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: sizeCtrl,
              decoration: const InputDecoration(
                labelText: 'Size (e.g. 12 oz, 1 pk)',
                border: OutlineInputBorder(),
              ),
              onSubmitted: onSizeChanged,
            ),
          ] else if (model.size.isNotEmpty)
            Text('Size: ${model.size}',
                style: const TextStyle(color: Colors.grey)),
        ],
      ),
    ),
  );
}
