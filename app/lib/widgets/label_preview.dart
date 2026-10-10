// On-screen mirror of the 2"x1" thermal labels (see lib/print/tspl.dart).
// Layout-faithful, not dot-faithful: same zones per [LabelModel.kind]
// (wireframes labels-wireframes/2_x_1_thermal_label_*), same helpers
// (Tspl.titleLines/normalizeCode/unitPriceText) so print and screen can
// never disagree on content. Digital-proof palette + bundled faces
// (BarlowCondensed/SpaceMono/SpaceGrotesk) per DESIGN.md dual-mode rule;
// the printer stays 1-bit. Used in the Labels tab, detail sheets, print
// confirm, and the print-job status rows.
library;

import 'package:barcode_widget/barcode_widget.dart' as bw;
import 'package:flutter/material.dart';

import '../i18n/lang.dart';
import '../print/label_model.dart';
import '../print/tspl.dart';

const _titleFace = 'BarlowCondensed';
const _monoFace = 'SpaceMono';

class LabelPreview extends StatelessWidget {
  final LabelModel model;
  final bool compact;
  const LabelPreview({super.key, required this.model, this.compact = false});

  @override
  Widget build(BuildContext context) {
    switch (model.kind) {
      case LabelKind.standard:
        return _StandardPreview(model: model, compact: compact);
      case LabelKind.promo:
        if (model.wasPrice == null) {
          return _StandardPreview(model: model, compact: compact);
        }
        return _PromoPreview(model: model, compact: compact);
      case LabelKind.rapidScan:
        return _RapidPreview(model: model, compact: compact);
      case LabelKind.kitchen:
        return _StandardPreview(model: model, compact: compact);
    }
  }
}

/// Type 01 standard retail (mirrors Tspl._composeStandard zone for zone).
class _StandardPreview extends StatelessWidget {
  final LabelModel model;
  final bool compact;
  const _StandardPreview({required this.model, required this.compact});

  @override
  Widget build(BuildContext context) {
    final norm = Tspl.normalizeCode(model.code);
    final title = Tspl.titleLines(model.displayName).join('\n');
    final parts = Tspl.splitPrice(model.price);
    final unit = Tspl.unitPriceText(model.price, model.size);
    final subBits = [
      if (model.size.trim().isNotEmpty) model.size.trim().toUpperCase(),
      if (model.category.trim().isNotEmpty)
        model.category.trim().toUpperCase(),
    ];
    final double micro = compact ? 7 : 9;
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
            // Header: enlarged oval left, metadata micro right.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  'assets/logo.png',
                  height: compact ? 16 : 28,
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, err, stack) => Text(
                    'CLOUD 9 MARKET',
                    style: TextStyle(
                      fontFamily: _titleFace,
                      fontSize: compact ? 8 : 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (model.category.trim().isNotEmpty)
                      Text(
                        model.category.trim().toUpperCase(),
                        style: TextStyle(
                            fontFamily: _monoFace, fontSize: micro),
                      ),
                    if (model.defaultCode.trim().isNotEmpty)
                      Text(
                        'SKU: ${model.defaultCode.trim().toUpperCase()}',
                        style: TextStyle(
                            fontFamily: _monoFace, fontSize: micro),
                      ),
                  ],
                ),
              ],
            ),
            Divider(height: compact ? 6 : 10, thickness: 1),
            // Title block: full-width uppercase, never truncated mid-word.
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: _titleFace,
                fontSize: compact ? 11 : 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subBits.isNotEmpty)
              Text(
                subBits.join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: _monoFace,
                    fontSize: micro,
                    color: Colors.grey.shade800),
              ),
            Divider(height: compact ? 6 : 10, thickness: 1),
            // Lower split: barcode bay | price hero.
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: norm.digits.isEmpty
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
                                  barcode: norm.symbology == 'UPCA'
                                      ? bw.Barcode.upcA()
                                      : norm.symbology == 'EAN13'
                                          ? bw.Barcode.ean13()
                                          : bw.Barcode.code128(),
                                  data: norm.digits,
                                  drawText: false,
                                  errorBuilder: (ctx, err) =>
                                      const Center(
                                          child: Text('BARCODE ERROR',
                                              style: TextStyle(
                                                  fontSize: 10))),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                norm.digits,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontFamily: _monoFace,
                                    fontSize: micro,
                                    letterSpacing: 2),
                              ),
                              if (unit != null)
                                Container(
                                  margin:
                                      const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                      border: Border.all(width: 1)),
                                  child: Text(
                                    'UNIT PRICE  $unit',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontFamily: _monoFace,
                                        fontSize: micro,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const VerticalDivider(width: 12, thickness: 1),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Three-part hero lockup: $ + huge int + raised cents.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment:
                              CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '\$',
                              style: TextStyle(
                                fontFamily: _titleFace,
                                fontSize: compact ? 12 : 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              parts.intPart,
                              style: TextStyle(
                                fontFamily: _titleFace,
                                fontSize: compact ? 30 : 44,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                              ),
                            ),
                            Text(
                              parts.cents,
                              style: TextStyle(
                                fontFamily: _titleFace,
                                fontSize: compact ? 12 : 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 1),
                          decoration: BoxDecoration(
                              border: Border.all(width: 1)),
                          child: Text(
                            'RETAIL',
                            style: TextStyle(
                                fontFamily: _monoFace,
                                fontSize: micro,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
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

/// Type 03 rapid scan (mirrors Tspl._composeRapidScan): knockout LOC
/// band, big title + mini price, pack strip, maxi barcode bay.
class _RapidPreview extends StatelessWidget {
  final LabelModel model;
  final bool compact;
  const _RapidPreview({required this.model, required this.compact});

  @override
  Widget build(BuildContext context) {
    final norm = Tspl.normalizeCode(model.code);
    final parts = Tspl.splitPrice(model.price);
    final title = Tspl.titleLines(model.displayName, maxChars: 30).join('\n');
    final double micro = compact ? 7 : 9;
    final metaBits = [
      if (model.defaultCode.trim().isNotEmpty)
        'SKU: ${model.defaultCode.trim().toUpperCase()}',
      if (model.size.trim().isNotEmpty)
        'PACK: ${model.size.trim().toUpperCase()}',
    ];
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
            // Knockout LOC band (preview renders true white-on-black).
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      (model.category.trim().isNotEmpty
                              ? 'LOC: ${model.category.trim()}'
                              : 'LOC: CLOUD 9 MARKET')
                          .toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: _titleFace,
                        fontSize: compact ? 9 : 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Image.asset(
                    'assets/logo.png',
                    height: compact ? 12 : 18,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, stack) => const SizedBox(),
                  ),
                ],
              ),
            ),
            SizedBox(height: compact ? 2 : 4),
            // Title + mini price sharing the rows.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: _titleFace,
                          fontSize: compact ? 13 : 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        metaBits.isEmpty
                            ? 'CLOUD 9 MARKET'
                            : metaBits.join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: _monoFace, fontSize: micro),
                      ),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('\$',
                        style: TextStyle(
                            fontFamily: _titleFace,
                            fontSize: compact ? 10 : 14,
                            fontWeight: FontWeight.w800)),
                    Text(parts.intPart,
                        style: TextStyle(
                            fontFamily: _titleFace,
                            fontSize: compact ? 22 : 32,
                            fontWeight: FontWeight.w800,
                            height: 1.0)),
                    Text(parts.cents,
                        style: TextStyle(
                            fontFamily: _titleFace,
                            fontSize: compact ? 10 : 14,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
            // Pack strip + maxi barcode bay.
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              child: Text(
                'SCAN • C9 RAPID',
                style: TextStyle(
                    color: Colors.white,
                    fontFamily: _monoFace,
                    fontSize: micro,
                    fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: compact ? 2 : 3),
            Expanded(
              child: norm.digits.isEmpty
                  ? const Center(child: Text('NO BARCODE'))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: bw.BarcodeWidget(
                            barcode: norm.symbology == 'UPCA'
                                ? bw.Barcode.upcA()
                                : norm.symbology == 'EAN13'
                                    ? bw.Barcode.ean13()
                                    : bw.Barcode.code128(),
                            data: norm.digits,
                            drawText: false,
                            errorBuilder: (ctx, err) => const Center(
                                child: Text('BARCODE ERROR',
                                    style: TextStyle(fontSize: 10))),
                          ),
                        ),
                        Text(
                          norm.digits,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontFamily: _monoFace,
                              fontSize: micro,
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

/// Type 02 promo (mirrors Tspl._composePromo): knockout banner, WAS
/// strike, NOW hero, member band. Preview renders true white-on-black
/// (the printer uses REVERSE with bordered fallback).
class _PromoPreview extends StatelessWidget {
  final LabelModel model;
  final bool compact;
  const _PromoPreview({required this.model, required this.compact});

  @override
  Widget build(BuildContext context) {
    final norm = Tspl.normalizeCode(model.code);
    final parts = Tspl.splitPrice(model.price);
    final was = model.wasPrice ?? model.price;
    final title = Tspl.titleLines(model.displayName, maxChars: 24).join('\n');
    final unit = Tspl.unitPriceText(model.price, model.size);
    final double micro = compact ? 7 : 9;
    final chipT = (model.saveText.trim().isNotEmpty
            ? model.saveText.trim()
            : 'SALE')
        .toUpperCase();
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
            // Knockout banner.
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 3),
              child: Row(
                children: [
                  Image.asset(
                    'assets/logo.png',
                    height: compact ? 10 : 14,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, err, stack) => const SizedBox(),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'SPECIAL VALUE',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: _titleFace,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.white)),
                    child: Text(
                      chipT,
                      style: TextStyle(
                          color: Colors.white,
                          fontFamily: _monoFace,
                          fontSize: micro,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: compact ? 2 : 3),
            // Title + ENDS chip.
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: _titleFace,
                      fontSize: compact ? 11 : 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (model.promoEnds.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration:
                        BoxDecoration(border: Border.all(width: 1)),
                    child: Text(
                      'ENDS: ${model.promoEnds.trim().toUpperCase()}',
                      style: TextStyle(
                          fontFamily: _monoFace, fontSize: micro),
                    ),
                  ),
              ],
            ),
            // WAS row: unit cell left, struck WAS right.
            Row(
              children: [
                if (unit != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration:
                        BoxDecoration(border: Border.all(width: 1)),
                    child: Text(
                      unit,
                      style: TextStyle(
                          fontFamily: _monoFace,
                          fontSize: micro,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                const Spacer(),
                Text(
                  'WAS \$${was.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontFamily: _titleFace,
                    fontSize: compact ? 11 : 15,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 2 : 3),
            // Lower split: barcode bay | NOW hero.
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: norm.digits.isEmpty
                        ? const Center(child: Text('NO BARCODE'))
                        : Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: bw.BarcodeWidget(
                                  barcode: norm.symbology == 'UPCA'
                                      ? bw.Barcode.upcA()
                                      : norm.symbology == 'EAN13'
                                          ? bw.Barcode.ean13()
                                          : bw.Barcode.code128(),
                                  data: norm.digits,
                                  drawText: false,
                                  errorBuilder: (ctx, err) =>
                                      const Center(
                                          child: Text('BARCODE ERROR',
                                              style: TextStyle(
                                                  fontSize: 10))),
                                ),
                              ),
                              Text(
                                norm.digits,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontFamily: _monoFace,
                                    fontSize: micro,
                                    letterSpacing: 2),
                              ),
                              if (model.defaultCode.trim().isNotEmpty)
                                Text(
                                  'PLU: ${model.defaultCode.trim().toUpperCase()}',
                                  style: TextStyle(
                                      fontFamily: _monoFace,
                                      fontSize: micro),
                                ),
                            ],
                          ),
                  ),
                  const VerticalDivider(width: 12, thickness: 1),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('NOW',
                            style: TextStyle(
                                fontFamily: _monoFace,
                                fontSize: micro,
                                fontWeight: FontWeight.bold)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment:
                              CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('\$',
                                style: TextStyle(
                                    fontFamily: _titleFace,
                                    fontSize: compact ? 12 : 18,
                                    fontWeight: FontWeight.w800)),
                            Text(parts.intPart,
                                style: TextStyle(
                                    fontFamily: _titleFace,
                                    fontSize: compact ? 30 : 44,
                                    fontWeight: FontWeight.w800,
                                    height: 1.0)),
                            Text(parts.cents,
                                style: TextStyle(
                                    fontFamily: _titleFace,
                                    fontSize: compact ? 12 : 18,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              border: Border.all(width: 1)),
                          child: Text(
                            'REWARDS MEMBER',
                            style: TextStyle(
                                fontFamily: _monoFace,
                                fontSize: micro,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
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
/// the size row is read-only. The promo section (Type 02) appears when
/// any promo callback is provided.
Future<void> showLabelPreviewSheet(
  BuildContext context,
  LabelModel model, {
  ValueChanged<String>? onSizeChanged,
  String? initialSize,
  ({double wasPrice, String promoEnds, String saveText})? initialPromo,
  ValueChanged<({double wasPrice, String promoEnds, String saveText})>?
      onPromoChanged,
  VoidCallback? onPromoCleared,
}) {
  final sizeCtrl = TextEditingController(text: initialSize ?? model.size);
  final wasCtrl = TextEditingController(
      text: initialPromo != null
          ? initialPromo.wasPrice.toStringAsFixed(2)
          : '');
  final endsCtrl =
      TextEditingController(text: initialPromo?.promoEnds ?? '');
  final saveCtrl =
      TextEditingController(text: initialPromo?.saveText ?? '');
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabelPreview(model: model),
            const SizedBox(height: 12),
            Text(model.displayName,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
                '${model.code.isEmpty ? 'NO BARCODE' : model.code}  •  ${model.priceText}'),
            if (onSizeChanged != null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: sizeCtrl,
                decoration: InputDecoration(
                  labelText: t('sheet_size'),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: onSizeChanged,
              ),
            ] else if (model.size.isNotEmpty)
              Text(
                  Lang.instance.f('sheet_size_val', {'size': model.size}),
                  style: const TextStyle(color: Colors.grey)),
            if (onPromoChanged != null) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  model.kind == LabelKind.promo
                      ? t('sheet_promo_on')
                      : t('sheet_promo'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                children: [
                  TextField(
                    controller: wasCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: t('sheet_was'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: endsCtrl,
                    decoration: InputDecoration(
                      labelText: t('sheet_ends'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: saveCtrl,
                    decoration: InputDecoration(
                      labelText: t('sheet_save'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final was =
                                double.tryParse(wasCtrl.text.trim());
                            if (was == null || was <= 0) return;
                            onPromoChanged((
                              wasPrice: was,
                              promoEnds: endsCtrl.text.trim(),
                              saveText: saveCtrl.text.trim(),
                            ));
                          },
                          child: Text(t('sheet_apply')),
                        ),
                      ),
                      if (onPromoCleared != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onPromoCleared,
                            child: Text(t('sheet_remove')),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
