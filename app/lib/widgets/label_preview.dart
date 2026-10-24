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
/// Wireframe: labels-wireframes/type01-mockup.html (406x203 canvas).
/// Titles are two-tier (Tspl.titleFit: full size to 30 chars, smaller cut
/// to 44) so the line only ellipsizes when nothing fits — preview and
/// print share the tiers and never disagree on content.
/// Compact (list thumbnails) keeps zone parity but hides detail rows
/// (slot, store code, subtitle, unit cell, EACH, GS1 band) that cannot
/// fit below ~100px tall; the 140px job-row box grows to 180px.
class _StandardPreview extends StatelessWidget {
  final LabelModel model;
  final bool compact;
  const _StandardPreview({required this.model, required this.compact});

  @override
  Widget build(BuildContext context) {
    final norm = Tspl.normalizeCode(model.code);
    // Two-tier title (Tspl.titleFit): full size to 30 chars, a smaller
    // cut to 44 — the line only ellipsizes when nothing fits.
    final spec = Tspl.titleFit(model.displayName);
    final title = spec.lines.join('\n');
    final parts = Tspl.splitPrice(model.price);
    final unit = Tspl.unitPriceText(model.price, model.size);
    final shelf = Tspl.shelfLine(model.shelfLoc, model.category);
    final slots = Tspl.slotLines(model.slot);
    final code = Tspl.storeCode(model.category);
    final verify = Tspl.verifyText(model.verifyDate);
    final subBits = [
      if (model.size.trim().isNotEmpty) model.size.trim().toUpperCase(),
      if (model.allergens.trim().isNotEmpty)
        model.allergens.trim().toUpperCase(),
    ];
    final showSub = !compact && (subBits.isNotEmpty || model.taxable);
    final dept = model.dept.trim().isNotEmpty
        ? 'DEPT ${model.dept.trim().toUpperCase()}'
        : '';
    // Detail rows that only fit at full scale.
    final fullOnly = !compact;

    final double pad = compact ? 5 : 10;
    final double micro = compact ? 7 : 9;
    final double titleSize = spec.font == '2'
        ? (compact ? 12 : 18)
        : (compact ? 9 : 13);
    final double heroInt = compact ? 22 : 64;
    final double heroSmall = compact ? 10 : 26;
    final double logoH = compact ? 22 : 44;
    return AspectRatio(
      aspectRatio: 2 / 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black, width: 2),
        ),
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A. Header: logo + slot codes | shelf + VERIF knockout + code.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/cloud_9_kitchen_market_logo.png',
                  height: logoH,
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, err, stack) => Text(
                    'CLOUD 9 MARKET',
                    style: TextStyle(
                      fontFamily: _titleFace,
                      fontSize: micro,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                if (slots.isNotEmpty && fullOnly) ...[
                  const SizedBox(width: 6),
                  Container(width: 1, height: 22, color: Colors.black),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < slots.length; i++)
                        Text(
                          slots[i],
                          style: TextStyle(
                              fontFamily: _monoFace,
                              fontSize: i == 0 ? 8 : 7,
                              fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ],
                const Spacer(),
                if (shelf.isNotEmpty || fullOnly)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (shelf.isNotEmpty)
                        Text(
                          shelf,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: _monoFace,
                              fontSize: micro,
                              fontWeight: FontWeight.bold),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            color: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            child: Text(
                              verify,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: _monoFace,
                                  fontSize: micro - 1,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (code.isNotEmpty && fullOnly) ...[
                            const SizedBox(width: 4),
                            Text(
                              code,
                              style: TextStyle(
                                  fontFamily: _monoFace,
                                  fontSize: micro - 1,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
              ],
            ),
            Divider(height: compact ? 6 : 10, thickness: 2, color: Colors.black),
            // B. Title block: single uppercase line + subtitle/TAXABLE row.
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: _titleFace,
                fontSize: titleSize,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (showSub)
              Row(
                children: [
                  if (subBits.isNotEmpty)
                    Expanded(
                      child: Text(
                        subBits.join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: _titleFace,
                            fontSize: 8,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  if (model.taxable)
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 0),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        border: Border.all(color: Colors.black),
                      ),
                      child: Text(
                        'TAXABLE',
                        style: TextStyle(
                            fontFamily: _monoFace,
                            fontSize: micro - 2,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            Divider(height: compact ? 5 : 8, thickness: 1, color: Colors.black),
            // C+D. Lower split: barcode bay | price hero.
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 48,
                    child: norm.digits.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'ADD BARCODE',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1),
                                ),
                                if (model.defaultCode.trim().isNotEmpty)
                                  Text(
                                    'SKU: ${model.defaultCode.trim().toUpperCase()}',
                                    style: TextStyle(
                                        fontFamily: _monoFace,
                                        fontSize: micro,
                                        color: Colors.grey.shade800),
                                  ),
                              ],
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
                                maxLines: 1,
                                style: TextStyle(
                                    fontFamily: _monoFace,
                                    fontSize: micro,
                                    letterSpacing: 2),
                              ),
                              if (unit != null && fullOnly)
                                Container(
                                  margin:
                                      const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  color: Colors.black,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'UNIT PRICE:',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontFamily: _monoFace,
                                            fontSize: micro - 2,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        unit,
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontFamily: _monoFace,
                                            fontSize: micro,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
                  VerticalDivider(
                      width: compact ? 8 : 12,
                      thickness: 2,
                      color: Colors.black),
                  Expanded(
                    flex: 52,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.only(bottom: 2),
                          decoration: const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color: Colors.black, width: 1)),
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              // Scale-down guard: the badge must never push
                              // past narrow thumbnail columns.
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    color: Colors.black,
                                    padding: EdgeInsets.symmetric(
                                        horizontal: compact ? 4 : 6,
                                        vertical: 1),
                                    child: Text(
                                      'EVERYDAY RETAIL',
                                      maxLines: 1,
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontFamily: _titleFace,
                                          fontSize:
                                              compact ? micro - 1 : micro,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing:
                                              compact ? 0 : 1),
                                    ),
                                  ),
                                ),
                              ),
                              if (dept.isNotEmpty && fullOnly)
                                Text(
                                  dept,
                                  style: TextStyle(
                                      fontFamily: _monoFace,
                                      fontSize: micro - 1,
                                      fontWeight: FontWeight.bold),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          // Scale-down guard: any price (e.g. 3-digit)
                          // fits narrow thumbnail columns.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '\$',
                                  style: TextStyle(
                                    fontFamily: _titleFace,
                                    fontSize: heroSmall,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  parts.intPart,
                                  style: TextStyle(
                                    fontFamily: _titleFace,
                                    fontSize: heroInt,
                                    fontWeight: FontWeight.w900,
                                    height: 1.0,
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      parts.cents,
                                      style: TextStyle(
                                        fontFamily: _titleFace,
                                        fontSize: heroSmall,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    if (model.eachText
                                            .trim()
                                            .isNotEmpty &&
                                        fullOnly)
                                      Text(
                                        model.eachText.trim().toUpperCase(),
                                        style: TextStyle(
                                            fontFamily: _monoFace,
                                            fontSize: micro - 2,
                                            fontWeight: FontWeight.bold),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (fullOnly)
                          Container(
                            color: Colors.black,
                            padding:
                                const EdgeInsets.symmetric(vertical: 1),
                            child: Text(
                              'GS1 COMPLIANT SHELF EDGE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: _monoFace,
                                  fontSize: micro - 2,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1),
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
                    'assets/cloud_9_kitchen_market_logo.png',
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
                    'assets/cloud_9_kitchen_market_logo.png',
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
  ({String shelfLoc, String verifyDate, String slot, String dept,
          String allergens, bool taxable, String eachText})? initialShelf,
  ValueChanged<({String shelfLoc, String verifyDate, String slot, String dept,
          String allergens, bool taxable, String eachText})>? onShelfChanged,
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
  final shelf = initialShelf ??
      (
        shelfLoc: model.shelfLoc,
        verifyDate: model.verifyDate,
        slot: model.slot,
        dept: model.dept,
        allergens: model.allergens,
        taxable: model.taxable,
        eachText: model.eachText,
      );
  final locCtrl = TextEditingController(text: shelf.shelfLoc);
  final verCtrl = TextEditingController(text: shelf.verifyDate);
  final slotCtrl = TextEditingController(text: shelf.slot);
  final deptCtrl = TextEditingController(text: shelf.dept);
  final algCtrl = TextEditingController(text: shelf.allergens);
  final eachCtrl = TextEditingController(text: shelf.eachText);
  var taxable = shelf.taxable;
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
            if (onShelfChanged != null &&
                model.kind == LabelKind.standard) ...[
              const SizedBox(height: 8),
              StatefulBuilder(
                builder: (ctx, setTileState) => ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    t('sheet_shelf'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  children: [
                    TextField(
                      controller: locCtrl,
                      decoration: InputDecoration(
                        labelText: t('sheet_shelf_loc'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: verCtrl,
                      decoration: InputDecoration(
                        labelText: t('sheet_shelf_verify'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: slotCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: t('sheet_shelf_slot'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: deptCtrl,
                      decoration: InputDecoration(
                        labelText: t('sheet_shelf_dept'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: algCtrl,
                      decoration: InputDecoration(
                        labelText: t('sheet_shelf_allergens'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: eachCtrl,
                      decoration: InputDecoration(
                        labelText: t('sheet_shelf_each'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t('sheet_shelf_taxable')),
                      value: taxable,
                      onChanged: (v) =>
                          setTileState(() => taxable = v ?? false),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          onShelfChanged((
                            shelfLoc: locCtrl.text.trim(),
                            verifyDate: verCtrl.text.trim(),
                            slot: slotCtrl.text.trim(),
                            dept: deptCtrl.text.trim(),
                            allergens: algCtrl.text.trim(),
                            taxable: taxable,
                            eachText: eachCtrl.text.trim(),
                          ));
                        },
                        child: Text(t('sheet_shelf_apply')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
