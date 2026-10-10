// TSPL composer for 2"x1" labels (Phomemo PM-241-BT target).
// Pure Dart, no plugins: output is verified by golden tests
// (test/tspl_test.dart) and byte-checked on hardware in Phase D.
//
// Wireframe templates (labels-wireframes/2_x_1_thermal_label_*):
// dispatch in [compose] on [LabelModel.kind]. Canvas 406x203 @203dpi
// with 12-dot margins (~382 content); the composer targets 384 usable.
// Zones never shift when optional content (logo/promo) is absent.
//
// Font metrics below are TSC bitmap defaults; hardware calibration
// (Phase D font-grid print) confirms them before coordinates lock.
library;

import 'dart:convert';

import 'label_model.dart';

class Tspl {
  /// Printable width in dots at 203dpi for 48mm stock.
  static const int widthDots = 384;

  /// Printable height in dots at 203dpi for 25mm stock.
  static const int heightDots = 200;

  /// Content margins (wireframe quiet/margin rule).
  static const int marginDots = 10;

  /// Logo raster caps (enlarged aspect-fit ovals for header slots).
  static const int maxLogoWidthDots = 320;
  static const int maxLogoHeightDots = 32;

  /// Pick a printer-native symbology. Kept for preview callers;
  /// delegates to [normalizeCode] (UPC-A aware, Mod10).
  static String symbologyFor(String code) =>
      normalizeCode(code).symbology;

  /// UPC-A check digit for an 11-digit base (Mod10, GS1 US).
  static String upcCheckDigit(String eleven) {
    var odd = 0;
    var even = 0;
    for (var i = 0; i < 11; i++) {
      final d = eleven.codeUnitAt(i) - 48;
      if (i.isEven) {
        odd += d;
      } else {
        even += d;
      }
    }
    return ((10 - ((odd * 3 + even) % 10)) % 10).toString();
  }

  /// Normalize a scannable code: strip separators, complete 11-digit
  /// UPC-A with its check digit, declare UPCA/EAN13/128.
  /// Fixes "digits print, no bars": the printer needs exact digit
  /// counts per symbology; anything else falls back to Code 128.
  static ({String digits, String symbology}) normalizeCode(String raw) {
    final stripped = raw.trim().replaceAll(RegExp(r'[\s\-]'), '');
    if (RegExp(r'^\d{11}$').hasMatch(stripped)) {
      return (digits: '$stripped${upcCheckDigit(stripped)}', symbology: 'UPCA');
    }
    if (RegExp(r'^\d{12}$').hasMatch(stripped)) {
      return (digits: stripped, symbology: 'UPCA');
    }
    if (RegExp(r'^\d{13}$').hasMatch(stripped)) {
      return (digits: stripped, symbology: 'EAN13');
    }
    return (digits: raw.trim(), symbology: '128');
  }

  static String _q(String s) => s.replaceAll('"', "'").replaceAll('\n', ' ');

  /// Internal bitmap font metrics at 1x (right-alignment + centering).
  /// TSC defaults; confirmed by the Phase D calibration print.
  /// Font "5" is the price hero; "3" its $/cents; "2" titles; "1" micro.
  static const int _font1CharDots = 8;
  static const int _font2CharDots = 12;
  static const int _font3CharDots = 16;
  static const int _font4CharDots = 24;
  static const int _font5CharDots = 32;

  /// Rough barcode width estimate in dots for centering (narrow=2).
  static int barcodeWidthFor(String code, String sym) {
    if (sym == 'UPCA') return 190;
    if (sym == 'EAN13') return 200;
    return (code.length * 13 + 40).clamp(80, 340);
  }

  /// Split a price into hero int part + cents (cents keeps the dot).
  static ({String intPart, String cents}) splitPrice(double price) {
    final s = price.toStringAsFixed(2);
    final i = s.indexOf('.');
    return (intPart: s.substring(0, i), cents: s.substring(i));
  }

  /// Uppercased title lines: word-wrap to [maxLines] of [maxChars],
  /// ellipsis past that. Shared with the preview so print and screen
  /// can never disagree (wireframes: uppercase condensed titles).
  static List<String> titleLines(
    String displayName, {
    int maxChars = 28,
    int maxLines = 2,
  }) {
    final words = displayName
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final lines = <String>[];
    var cur = '';
    for (final w in words) {
      if (cur.isEmpty) {
        cur = w;
      } else if ((cur.length + 1 + w.length) <= maxChars) {
        cur = '$cur $w';
      } else {
        lines.add(cur);
        cur = w;
        if (lines.length == maxLines) {
          cur = '';
          break;
        }
      }
    }
    if (cur.isNotEmpty && lines.length < maxLines) lines.add(cur);
    if (lines.isEmpty) return [''];
    // Overflow: single brutal word or still more words -> ellipsis.
    var joined = lines.join(' ');
    final flat = displayName.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (flat.length > joined.length) {
      var last = lines.last;
      while (last.length >= maxChars - 1 && last.isNotEmpty) {
        last = last.substring(0, last.length - 1);
      }
      lines[lines.length - 1] = '$last…';
    }
    return lines;
  }

  /// Unit-price micro text ("$0.90 / OZ") from price + parsed size qty.
  /// Null when the size carries no usable qty (cell omitted, no gap).
  static String? unitPriceText(double price, String size) {
    final m = RegExp(
      r'(\d+(?:\.\d+)?)\s*(fl\s*oz|oz|lb|lbs|g|kg|ml|l|gal|qt|pt|ct|pk|pack|packs|bunch|ea|pcs)\s*$',
      caseSensitive: false,
    ).firstMatch(size.trim());
    if (m == null) return null;
    final qty = double.tryParse(m.group(1)!);
    if (qty == null || qty <= 0) return null;
    final unit = m
        .group(2)!
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    return '\$${(price / qty).toStringAsFixed(2)} / $unit';
  }

  /// Center-crop a 1-bit raster to [dstW] (keeps oval centers for
  /// narrow header slots). Pure; tested.
  static ({List<int> mono, int width, int height}) cropCenter(
    List<int> mono,
    int srcW,
    int dstW,
  ) {
    final rows = mono.length ~/ srcW;
    if (dstW >= srcW || rows <= 0) {
      return (mono: mono, width: srcW, height: rows);
    }
    final x0 = (srcW - dstW) ~/ 2;
    final out = <int>[];
    for (var r = 0; r < rows; r++) {
      out.addAll(mono.sublist(r * srcW + x0, r * srcW + x0 + dstW));
    }
    return (mono: out, width: dstW, height: rows);
  }

  /// Pack 1-bit row-major pixels MSB-first (shared with band composers).
  static String packHex(List<int> mono, int width) {
    final packed = <int>[];
    final rows = mono.length ~/ width;
    for (var r = 0; r < rows; r++) {
      var acc = 0;
      var bits = 0;
      for (var c = 0; c < width; c++) {
        acc = (acc << 1) | (mono[r * width + c] != 0 ? 1 : 0);
        bits++;
        if (bits == 8) {
          packed.add(acc);
          acc = 0;
          bits = 0;
        }
      }
      if (bits > 0) packed.add(acc << (8 - bits));
    }
    return packed
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
  }

  static void _bitmap(
    StringBuffer sb,
    List<int> mono,
    int width,
    int x,
    int y,
  ) {
    final rows = mono.length ~/ width;
    final widthBytes = (width + 7) ~/ 8;
    sb.writeln('BITMAP $x,$y,$widthBytes,$rows,1,${packHex(mono, width)}');
  }

  /// Compose one label, dispatching on [LabelModel.kind].
  /// Promo with null wasPrice renders as standard (defensive).
  static String compose(
    LabelModel m, {
    int density = 8,
    List<int>? logoMono,
    int logoWidth = 0,
  }) {
    switch (m.kind) {
      case LabelKind.standard:
        return _composeStandard(m,
            density: density, logoMono: logoMono, logoWidth: logoWidth);
      case LabelKind.promo:
        if (m.wasPrice == null) {
          return _composeStandard(m,
              density: density, logoMono: logoMono, logoWidth: logoWidth);
        }
        return _composePromo(m,
            density: density, logoMono: logoMono, logoWidth: logoWidth);
      case LabelKind.rapidScan:
        return _composeRapidScan(m,
            density: density, logoMono: logoMono, logoWidth: logoWidth);
      case LabelKind.kitchen:
        return _composeKitchen(m,
            density: density, logoMono: logoMono, logoWidth: logoWidth);
    }
  }

  static String _header(
    int density,
    List<int>? logoMono,
    int logoWidth,
  ) {
    final sb = StringBuffer();
    sb.writeln('SIZE 48 mm,25 mm');
    sb.writeln('GAP 3 mm,0');
    sb.writeln('DENSITY $density');
    sb.writeln('DIRECTION 1');
    sb.writeln('CLS');
    return sb.toString();
  }

  /// Type 01 standard retail (wireframe ..._standard_retail_everyday):
  /// logo header + title block + split barcode/price-hero lower zone.
  static String _composeStandard(
    LabelModel m, {
    int density = 8,
    List<int>? logoMono,
    int logoWidth = 0,
  }) {
    final sb = StringBuffer(_header(density, logoMono, logoWidth));
    const left = marginDots;
    const right = widthDots - marginDots;
    var y = 2;

    // Header: enlarged oval left (~150px crop), metadata right.
    if (logoMono != null && logoWidth > 0) {
      final crop = cropCenter(logoMono, logoWidth, 150);
      _bitmap(sb, crop.mono, crop.width, left, y);
    }
    final cat = _q(m.category.trim().toUpperCase());
    if (cat.isNotEmpty) {
      final cx = right - cat.length * _font1CharDots;
      sb.writeln('TEXT $cx,$y,"1",0,1,1,"$cat"');
    }
    final sku =
        _q((m.defaultCode.trim().isNotEmpty ? 'SKU: ${m.defaultCode.trim()}' : '')
            .toUpperCase());
    if (sku.isNotEmpty) {
      final sx = right - sku.length * _font1CharDots;
      sb.writeln('TEXT $sx,${y + 12},"1",0,1,1,"$sku"');
    }
    y += 30;
    sb.writeln('BAR $left,$y,${right - left},1');
    y += 5;

    // Title block: full-width uppercase, up to 2 wrapped lines + micro.
    final title = titleLines(m.displayName, maxChars: 28);
    for (final line in title) {
      sb.writeln('TEXT $left,$y,"2",0,1,1,"${_q(line)}"');
      y += 21;
    }
    final subBits = [
      if (m.size.trim().isNotEmpty) m.size.trim().toUpperCase(),
      if (m.category.trim().isNotEmpty) m.category.trim().toUpperCase(),
    ];
    if (subBits.isNotEmpty) {
      sb.writeln('TEXT $left,$y,"1",0,1,1,"${_q(subBits.join(' • '))}"');
      y += 13;
    }
    sb.writeln('BAR $left,$y,${right - left},1');
    y += 5;

    // Lower split: barcode bay | price hero. Fixed block y..y+92 so
    // two-line titles (worst case y=97) end at 189, inside 200 dots.
    const splitX = 230;
    const blockH = 92;
    sb.writeln('BAR $splitX,$y,1,$blockH');
    final norm = normalizeCode(m.code);
    if (norm.digits.isNotEmpty) {
      var narrow = 2;
      var est = barcodeWidthFor(norm.digits, norm.symbology);
      if (est > 210) {
        narrow = 1;
        est = (est / 2).ceil();
      }
      final bayCx = (left + splitX) ~/ 2;
      final bx = (bayCx - est ~/ 2).clamp(left, widthDots);
      const barcodeH = 56;
      final by = (y + 2).clamp(0, heightDots - barcodeH - 4);
      sb.writeln(
          'BARCODE $bx,$by,"${norm.symbology}",$barcodeH,0,0,$narrow,$narrow,"${_q(norm.digits)}"');
      final digits = _q(norm.digits);
      final dx = (bayCx - digits.length * _font1CharDots ~/ 2)
          .clamp(left, widthDots);
      sb.writeln('TEXT $dx,${by + barcodeH + 2},"1",0,1,1,"$digits"');
      final unit = unitPriceText(m.price, m.size);
      if (unit != null) {
        final uw = unit.length * _font1CharDots + 16;
        final ux = (bayCx - uw ~/ 2).clamp(left, widthDots);
        final uy = by + barcodeH + 16;
        sb.writeln('BOX $ux,$uy,$uw,13,1');
        sb.writeln(
            'TEXT ${ux + 8},${uy + 2},"1",0,1,1,"${_q(unit)}"');
      }
    } else {
      sb.writeln('TEXT $left,${y + 30},"2",0,1,1,"NO BARCODE"');
    }

    // Price hero (three-part lockup, right column centered).
    final parts = splitPrice(m.price);
    final intFont = parts.intPart.length > 2 ? '4' : '5';
    final intW = parts.intPart.length *
        (intFont == '5' ? _font5CharDots : _font4CharDots);
    final totalW = _font3CharDots + intW + parts.cents.length * _font3CharDots;
    final colCx = (splitX + right) ~/ 2;
    final px = (colCx - totalW ~/ 2).clamp(splitX + 2, widthDots);
    final py = y + 8;
    sb.writeln('TEXT $px,${py + 10},"3",0,1,1,"\$"');
    sb.writeln(
        'TEXT ${px + _font3CharDots},$py,"$intFont",0,1,1,"${parts.intPart}"');
    sb.writeln(
        'TEXT ${px + _font3CharDots + intW},${py + 12},"3",0,1,1,"${parts.cents}"');
    const chip = 'RETAIL';
    final chipW = chip.length * _font1CharDots + 16;
    final chipX = (colCx - chipW ~/ 2).clamp(splitX + 2, widthDots);
    sb.writeln('BOX $chipX,${py + 58},$chipW,13,1');
    sb.writeln('TEXT ${chipX + 8},${py + 60},"1",0,1,1,"$chip"');

    sb.writeln('PRINT ${m.copies < 1 ? 1 : m.copies}');
    return sb.toString();
  }

  /// Type 03 rapid scan (wireframe ..._inventory_rapid_scan):
  /// knockout LOC band + big title + pack strip + maxi barcode bay.
  /// Inverted bands print black-on-white when firmware ignores REVERSE
  /// (graceful, still readable) — the Phase D print decides the toggle.
  static String _composeRapidScan(
    LabelModel m, {
    int density = 8,
    List<int>? logoMono,
    int logoWidth = 0,
  }) {
    final sb = StringBuffer(_header(density, logoMono, logoWidth));
    const left = marginDots;
    const right = widthDots - marginDots;

    // LOC band: black text + mini logo on white, then inverted.
    final loc = _q((m.category.trim().isNotEmpty
            ? 'LOC: ${m.category.trim()}'
            : 'LOC: CLOUD 9 MARKET')
        .toUpperCase());
    sb.writeln('TEXT $left,6,"2",0,1,1,"$loc"');
    if (logoMono != null && logoWidth > 0) {
      final crop = cropCenter(logoMono, logoWidth, 90);
      _bitmap(sb, crop.mono, crop.width, right - 90, 4);
    }
    sb.writeln('REVERSE 0,0,$widthDots,30');

    // Title: big single line when short, two-line fallback when long.
    // The right mini price block shares these rows, so the title width
    // budget accounts for it.
    var y = 34;
    final parts = splitPrice(m.price);
    final priceBlockW = _font2CharDots +
        parts.intPart.length * _font4CharDots +
        parts.cents.length * _font2CharDots;
    final titleMax = widthDots - marginDots * 2 - priceBlockW - 12;
    final bigMax = (titleMax ~/ _font3CharDots).clamp(8, 40);
    final smallMax = (titleMax ~/ _font2CharDots).clamp(8, 40);
    final big = m.displayName.length <= bigMax;
    final tFont = big ? '3' : '2';
    final lineH = big ? 25 : 21;
    final lines = titleLines(m.displayName,
        maxChars: big ? bigMax : smallMax, maxLines: big ? 1 : 2);
    for (final line in lines) {
      sb.writeln('TEXT $left,$y,"$tFont",0,1,1,"${_q(line)}"');
      y += lineH;
    }
    final pxx = (right - priceBlockW).clamp(left, widthDots);
    sb.writeln('TEXT $pxx,34,"2",0,1,1,"\$"');
    sb.writeln(
        'TEXT ${pxx + _font2CharDots},32,"4",0,1,1,"${parts.intPart}"');
    sb.writeln(
        'TEXT ${pxx + _font2CharDots + parts.intPart.length * _font4CharDots},40,"2",0,1,1,"${parts.cents}"');

    // SKU / pack micro row.
    final metaBits = [
      if (m.defaultCode.trim().isNotEmpty)
        'SKU: ${m.defaultCode.trim().toUpperCase()}',
      if (m.size.trim().isNotEmpty) 'PACK: ${m.size.trim().toUpperCase()}',
    ];
    if (metaBits.isEmpty) metaBits.add('CLOUD 9 MARKET');
    sb.writeln('TEXT $left,$y,"1",0,1,1,"${_q(metaBits.join(' • '))}"');
    y += 14;

    // Pack strip (knockout) + maxi barcode bay.
    sb.writeln('TEXT $left,${y + 2},"1",0,1,1,"SCAN • C9 RAPID"');
    sb.writeln('REVERSE 0,$y,$widthDots,16');
    y += 18;
    final norm = normalizeCode(m.code);
    if (norm.digits.isNotEmpty) {
      var narrow = 2;
      var est = barcodeWidthFor(norm.digits, norm.symbology);
      if (est > 360) {
        narrow = 1;
        est = (est / 2).ceil();
      }
      final bx = ((widthDots - est) ~/ 2).clamp(left, widthDots);
      const barcodeH = 56;
      final by = y.clamp(0, heightDots - barcodeH - 18);
      sb.writeln(
          'BARCODE $bx,$by,"${norm.symbology}",$barcodeH,0,0,$narrow,$narrow,"${_q(norm.digits)}"');
      final digits = _q(norm.digits);
      final dx = ((widthDots - digits.length * _font1CharDots) ~/ 2)
          .clamp(left, widthDots);
      sb.writeln('TEXT $dx,${by + barcodeH + 2},"1",0,1,1,"$digits"');
    } else {
      sb.writeln('TEXT $left,$y,"2",0,1,1,"NO BARCODE"');
    }

    sb.writeln('PRINT ${m.copies < 1 ? 1 : m.copies}');
    return sb.toString();
  }

  /// Type 02 promo (wireframe ..._promotional_special_value):
  /// knockout banner + title/ENDS + WAS strike + NOW hero + member band.
  /// Same REVERSE grace rule as rapid scan (Phase D decides the toggle).
  static String _composePromo(
    LabelModel m, {
    int density = 8,
    List<int>? logoMono,
    int logoWidth = 0,
  }) {
    final was = m.wasPrice ?? m.price;
    final sb = StringBuffer(_header(density, logoMono, logoWidth));
    const left = marginDots;
    const right = widthDots - marginDots;

    // Knockout banner: headline + save chip, then inverted.
    if (logoMono != null && logoWidth > 0) {
      final crop = cropCenter(logoMono, logoWidth, 70);
      _bitmap(sb, crop.mono, crop.width, left, 6);
    }
    sb.writeln('TEXT 90,6,"2",0,1,1,"SPECIAL VALUE"');
    final chipT =
        _q((m.saveText.trim().isNotEmpty ? m.saveText.trim() : 'SALE')
            .toUpperCase());
    final chipW = chipT.length * _font1CharDots + 16;
    final chipX = (right - chipW).clamp(left, widthDots);
    sb.writeln('BOX $chipX,6,$chipW,15,1');
    sb.writeln('TEXT ${chipX + 8},9,"1",0,1,1,"$chipT"');
    sb.writeln('REVERSE 0,0,$widthDots,30');

    // Title + ENDS chip.
    var y = 34;
    final title = titleLines(m.displayName, maxChars: 24);
    for (final line in title) {
      sb.writeln('TEXT $left,$y,"2",0,1,1,"${_q(line)}"');
      y += 21;
    }
    if (m.promoEnds.trim().isNotEmpty) {
      final ends = _q('ENDS: ${m.promoEnds.trim().toUpperCase()}');
      final ew = ends.length * _font1CharDots + 16;
      sb.writeln('BOX ${right - ew},$y,$ew,13,1');
      sb.writeln('TEXT ${right - ew + 8},${y + 2},"1",0,1,1,"$ends"');
      y += 14;
    }

    // WAS row: unit cell left, struck WAS right.
    final wasT = 'WAS \$${was.toStringAsFixed(2)}';
    final wasX = (right - wasT.length * _font2CharDots).clamp(left, widthDots);
    sb.writeln('TEXT $wasX,$y,"2",0,1,1,"${_q(wasT)}"');
    sb.writeln(
        'BAR $wasX,${y + 10},${wasT.length * _font2CharDots},2');
    final unit = unitPriceText(m.price, m.size);
    if (unit != null) {
      final uw = unit.length * _font1CharDots + 16;
      sb.writeln('BOX $left,${y + 2},$uw,13,1');
      sb.writeln('TEXT ${left + 8},${y + 4},"1",0,1,1,"${_q(unit)}"');
    }
    y += 18;

    // Lower split: barcode bay | NOW hero (worst case ends at 188).
    const splitX = 230;
    const blockH = 80;
    sb.writeln('BAR $splitX,$y,1,$blockH');
    final norm = normalizeCode(m.code);
    if (norm.digits.isNotEmpty) {
      var narrow = 2;
      var est = barcodeWidthFor(norm.digits, norm.symbology);
      if (est > 210) {
        narrow = 1;
        est = (est / 2).ceil();
      }
      final bayCx = (left + splitX) ~/ 2;
      final bx = (bayCx - est ~/ 2).clamp(left, widthDots);
      const barcodeH = 44;
      final by = (y + 2).clamp(0, heightDots - barcodeH - 22);
      sb.writeln(
          'BARCODE $bx,$by,"${norm.symbology}",$barcodeH,0,0,$narrow,$narrow,"${_q(norm.digits)}"');
      final digits = _q(norm.digits);
      final dx = (bayCx - digits.length * _font1CharDots ~/ 2)
          .clamp(left, widthDots);
      sb.writeln('TEXT $dx,${by + barcodeH + 2},"1",0,1,1,"$digits"');
      final sku = m.defaultCode.trim().isNotEmpty
          ? 'PLU: ${m.defaultCode.trim().toUpperCase()}'
          : '';
      if (sku.isNotEmpty) {
        sb.writeln(
            'TEXT $left,${by + barcodeH + 15},"1",0,1,1,"${_q(sku)}"');
      }
    } else {
      sb.writeln('TEXT $left,${y + 20},"2",0,1,1,"NO BARCODE"');
    }

    // NOW hero + member band.
    final parts = splitPrice(m.price);
    final intFont = parts.intPart.length > 2 ? '4' : '5';
    final intW = parts.intPart.length *
        (intFont == '5' ? _font5CharDots : _font4CharDots);
    final totalW = _font3CharDots + intW + parts.cents.length * _font3CharDots;
    final colCx = (splitX + right) ~/ 2;
    final px = (colCx - totalW ~/ 2).clamp(splitX + 2, widthDots);
    final py = y + 2;
    sb.writeln('TEXT $px,$py,"1",0,1,1,"NOW"');
    sb.writeln('TEXT $px,${py + 12},"3",0,1,1,"\$"');
    sb.writeln(
        'TEXT ${px + _font3CharDots},${py + 10},"$intFont",0,1,1,"${parts.intPart}"');
    sb.writeln(
        'TEXT ${px + _font3CharDots + intW},${py + 22},"3",0,1,1,"${parts.cents}"');
    const band = 'REWARDS MEMBER';
    final bandW = band.length * _font1CharDots + 16;
    final bandX = (colCx - bandW ~/ 2).clamp(splitX + 2, widthDots);
    sb.writeln('BOX $bandX,${py + 60},$bandW,13,1');
    sb.writeln('TEXT ${bandX + 8},${py + 62},"1",0,1,1,"$band"');

    sb.writeln('PRINT ${m.copies < 1 ? 1 : m.copies}');
    return sb.toString();
  }

  /// Type 04 kitchen fridge tag (wireframe ..._food_prep_kitchen_fresh):
  /// header + title/prep + USE-BY knockout + barcode/allergen row with
  /// mini price + discard footer. Lot travels as Code128 (never QR).
  static String _composeKitchen(
    LabelModel m, {
    int density = 8,
    List<int>? logoMono,
    int logoWidth = 0,
  }) {
    final p = m.prep ?? const PrepInfo(item: '');
    final sb = StringBuffer(_header(density, logoMono, logoWidth));
    const left = marginDots;
    const right = widthDots - marginDots;

    // Header: mini logo + KITCHEN FRESH left, station/lot right.
    if (logoMono != null && logoWidth > 0) {
      final crop = cropCenter(logoMono, logoWidth, 70);
      _bitmap(sb, crop.mono, crop.width, left, 4);
    }
    sb.writeln('TEXT 90,6,"1",0,1,1,"KITCHEN FRESH"');
    final metaR = [
      if (p.station.trim().isNotEmpty) p.station.trim().toUpperCase(),
      if (p.lot.trim().isNotEmpty) 'LOT ${p.lot.trim().toUpperCase()}',
    ];
    if (metaR.isNotEmpty) {
      final rt = _q(metaR.join(' • '));
      sb.writeln(
          'TEXT ${right - rt.length * _font1CharDots},"1",0,1,1,"$rt"'
          .replaceFirst('TEXT ', 'TEXT ')
          .replaceFirst(',"1"', ',4,"1"'));
    }
    var y = 26;

    // Title + qty right, prep micro below.
    final title = titleLines(
        p.item.trim().isNotEmpty ? p.item : m.displayName,
        maxChars: 26);
    for (final line in title) {
      sb.writeln('TEXT $left,$y,"2",0,1,1,"${_q(line)}"');
      y += 21;
    }
    final prepBits = [
      if (p.preppedAt.trim().isNotEmpty)
        'PREPPED: ${p.preppedAt.trim().toUpperCase()}',
      if (p.preppedBy.trim().isNotEmpty)
        p.preppedBy.trim().toUpperCase(),
    ];
    if (prepBits.isNotEmpty) {
      sb.writeln('TEXT $left,$y,"1",0,1,1,"${_q(prepBits.join(' • '))}"');
    }
    if (p.qty.trim().isNotEmpty) {
      final qt = _q(p.qty.trim().toUpperCase());
      sb.writeln(
          'TEXT ${right - qt.length * _font1CharDots},$y,"1",0,1,1,"$qt"');
    }
    y += 13;

    // USE-BY knockout band.
    final useBy = _q(p.useBy.trim().isNotEmpty
        ? 'USE BY: ${p.useBy.trim().toUpperCase()}'
        : 'USE BY: —');
    sb.writeln('TEXT $left,${y + 4},"2",0,1,1,"$useBy"');
    if (p.fifoChip.trim().isNotEmpty) {
      final chip = _q(p.fifoChip.trim().toUpperCase());
      final cw = chip.length * _font1CharDots + 16;
      sb.writeln('BOX ${right - cw},${y + 3},$cw,15,1');
      sb.writeln('TEXT ${right - cw + 8},${y + 6},"1",0,1,1,"$chip"');
    }
    sb.writeln('REVERSE 0,$y,$widthDots,22');
    y += 24;

    // Middle split: lot barcode + chips | mini price + pan.
    const splitX = 230;
    final norm = normalizeCode(
        p.lot.trim().isNotEmpty ? p.lot : m.code);
    if (norm.digits.isNotEmpty) {
      var narrow = 2;
      var est = barcodeWidthFor(norm.digits, norm.symbology);
      if (est > 210) {
        narrow = 1;
        est = (est / 2).ceil();
      }
      final bayCx = (left + splitX) ~/ 2;
      final bx = (bayCx - est ~/ 2).clamp(left, widthDots);
      const barcodeH = 32;
      sb.writeln(
          'BARCODE $bx,$y,"${norm.symbology}",$barcodeH,0,0,$narrow,$narrow,"${_q(norm.digits)}"');
      final digits = _q(norm.digits);
      final dx = (bayCx - digits.length * _font1CharDots ~/ 2)
          .clamp(left, widthDots);
      sb.writeln('TEXT $dx,${y + barcodeH + 2},"1",0,1,1,"$digits"');
    } else {
      sb.writeln('TEXT $left,$y,"2",0,1,1,"NO LOT"');
    }
    final parts = splitPrice(m.price);
    final pTotal = _font2CharDots +
        parts.intPart.length * _font4CharDots +
        parts.cents.length * _font2CharDots;
    final colCx = (splitX + right) ~/ 2;
    final pxx = (colCx - pTotal ~/ 2).clamp(splitX + 2, widthDots);
    sb.writeln('TEXT $pxx,$y,"2",0,1,1,"\$"');
    sb.writeln(
        'TEXT ${pxx + _font2CharDots},$y,"4",0,1,1,"${parts.intPart}"');
    sb.writeln(
        'TEXT ${pxx + _font2CharDots + parts.intPart.length * _font4CharDots},${y + 8},"2",0,1,1,"${parts.cents}"');
    if (p.unitText.trim().isNotEmpty) {
      sb.writeln(
          'TEXT $pxx,${y + 34},"1",0,1,1,"${_q('UNIT: ${p.unitText.trim().toUpperCase()}')}"');
    }
    if (p.pan.trim().isNotEmpty) {
      sb.writeln(
          'TEXT $pxx,${y + 46},"1",0,1,1,"${_q(p.pan.trim().toUpperCase())}"');
    }
    y += 50;

    // Chips row: temp + allergens.
    final chips = [
      if (p.temp.trim().isNotEmpty) p.temp.trim().toUpperCase(),
      if (p.allergens.trim().isNotEmpty)
        'ALLERGEN: ${p.allergens.trim().toUpperCase()}',
    ];
    if (chips.isNotEmpty) {
      var cx = left;
      for (final chip in chips) {
        final cw = chip.length * _font1CharDots + 16;
        if (cx + cw > right) break;
        sb.writeln('BOX $cx,$y,$cw,13,1');
        sb.writeln('TEXT ${cx + 8},${y + 2},"1",0,1,1,"${_q(chip)}"');
        cx += cw + 6;
      }
      y += 15;
    }

    // Discard footer (omitted when nothing to say).
    final footL = [
      if (p.origin.trim().isNotEmpty)
        'FDA • ORIGIN: ${p.origin.trim().toUpperCase()}',
    ];
    final footR = [
      if (p.fifoChip.trim().isNotEmpty)
        'DISCARD AFTER ${p.fifoChip.trim().toUpperCase()}',
      if (p.pan.trim().isNotEmpty) p.pan.trim().toUpperCase(),
    ];
    if (footL.isNotEmpty || footR.isNotEmpty) {
      sb.writeln('BOX $left,$y,${right - left},13,1');
      if (footL.isNotEmpty) {
        sb.writeln('TEXT ${left + 8},${y + 2},"1",0,1,1,"${_q(footL.join())}"');
      }
      if (footR.isNotEmpty) {
        final ft = _q(footR.join(' • '));
        sb.writeln(
            'TEXT ${right - ft.length * _font1CharDots - 8},${y + 2},"1",0,1,1,"$ft"');
      }
    }

    sb.writeln('PRINT ${m.copies < 1 ? 1 : m.copies}');
    return sb.toString();
  }

  /// Encode a composed label for the wire (TSPL is byte-oriented).
  /// Non-Latin-1 chars are replaced with '?' (latin1.encode throws on them).
  static List<int> encode(String tspl) =>
      latin1.encode(tspl.replaceAll(RegExp(r'[^\x00-\xFF]'), '?'));
}
