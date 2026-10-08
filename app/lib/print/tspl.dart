// TSPL composer for 2"x1" price labels (Phomemo PM-241-BT target).
// Pure Dart, no plugins: output is verified by golden tests
// (test/tspl_test.dart) and byte-checked on hardware in Phase 0.
//
// Layout @203dpi (384 x 200 dots usable), vertical order:
//   logo (optional BITMAP) .... top-center, capped at 240x24 recommended
//   name + BIG price .......... one row (name truncated, price right-aligned)
//   big barcode ............... centered below, human-readable digits
// Budget: 8 + 24 + 6 + 30 + 10 + 64 + 12 ≈ 154 ≤ 200 dots.
library;

import 'dart:convert';

import 'label_model.dart';

class Tspl {
  /// Printable width in dots at 203dpi for 48mm stock.
  static const int widthDots = 384;

  /// Printable height in dots at 203dpi for 25mm stock.
  static const int heightDots = 200;

  /// Recommended logo caps so the 200-dot budget survives gap variance.
  /// The composer accepts larger bitmaps but they push the barcode down.
  static const int maxLogoWidthDots = 240;
  static const int maxLogoHeightDots = 24;

  /// Barcode height in dots ("big barcode" while keeping bottom margin).
  static const int barcodeHeightDots = 64;

  /// Pick a printer-native symbology. 12-13 digit numerics get EAN-13
  /// (readers handle UPC-A 11-digit as EAN-13 with leading zero);
  /// everything else falls back to Code 128, which encodes any ASCII.
  static String symbologyFor(String code) {
    final c = code.trim();
    if (RegExp(r'^\d{12,13}$').hasMatch(c)) return 'EAN13';
    return '128';
  }

  static String _q(String s) => s.replaceAll('"', "'").replaceAll('\n', ' ');

  /// Internal bitmap font metrics at 1x (used for right-alignment).
  /// Font "3" is the BIG price font; font "2" is the name font.
  static const int _font2CharDots = 12;
  static const int _font3CharDots = 16;

  /// Rough barcode width estimate in dots for centering.
  /// EAN-13 is fixed-width; Code128 scales with content length.
  static int barcodeWidthFor(String code, String sym) {
    if (sym == 'EAN13') return 200;
    return (code.length * 13 + 40).clamp(80, 340);
  }

  /// Compose one label. [logoMono] is optional pre-rasterized 1-bit pixels
  /// (row-major, 1 = black), [logoWidth] its width in dots; height is
  /// derived. Logo raster comes from lib/print/logo_raster.dart; labels
  /// print fully without it (blank 0-dot gap, zones never shift).
  static String compose(
    LabelModel m, {
    int density = 8,
    List<int>? logoMono,
    int logoWidth = 0,
  }) {
    final sb = StringBuffer();
    sb.writeln('SIZE 48 mm,25 mm');
    sb.writeln('GAP 3 mm,0');
    sb.writeln('DENSITY $density');
    sb.writeln('DIRECTION 1');
    sb.writeln('CLS');
    var y = 8;
    if (logoMono != null && logoWidth > 0) {
      final rows = logoMono.length ~/ logoWidth;
      final widthBytes = (logoWidth + 7) ~/ 8;
      final packed = <int>[];
      for (var r = 0; r < rows; r++) {
        var acc = 0;
        var bits = 0;
        for (var c = 0; c < logoWidth; c++) {
          acc = (acc << 1) | (logoMono[r * logoWidth + c] != 0 ? 1 : 0);
          bits++;
          if (bits == 8) {
            packed.add(acc);
            acc = 0;
            bits = 0;
          }
        }
        if (bits > 0) packed.add(acc << (8 - bits));
      }
      final hex = packed
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join();
      final x = ((widthDots - logoWidth) ~/ 2).clamp(0, widthDots);
      sb.writeln('BITMAP $x,$y,$widthBytes,$rows,1,$hex');
      y += rows + 6;
    }
    final price = _q(m.priceText);
    final priceX =
        (widthDots - 10 - price.length * _font3CharDots).clamp(10, widthDots);
    final maxNameChars =
        ((priceX - 10 - 10) ~/ _font2CharDots).clamp(1, 48);
    var name = _q(m.displayName);
    if (name.length > maxNameChars) name = name.substring(0, maxNameChars);
    sb.writeln('TEXT 10,$y,"2",0,1,1,"$name"');
    sb.writeln('TEXT $priceX,$y,"3",0,1,1,"$price"');
    final code = m.code;
    if (code.isNotEmpty) {
      final sym = symbologyFor(code);
      final w = barcodeWidthFor(code, sym);
      final bx = ((widthDots - w) ~/ 2).clamp(10, widthDots);
      final by = (y + 38).clamp(0, heightDots - barcodeHeightDots - 4);
      sb.writeln(
          'BARCODE $bx,$by,"$sym",$barcodeHeightDots,1,0,2,2,"${_q(code)}"');
    } else {
      final by = (y + 38).clamp(0, heightDots - 24);
      sb.writeln('TEXT 10,$by,"2",0,1,1,"NO BARCODE"');
    }
    sb.writeln('PRINT ${m.copies < 1 ? 1 : m.copies}');
    return sb.toString();
  }

  /// Encode a composed label for the wire (TSPL is byte-oriented).
  /// Non-Latin-1 chars are replaced with '?' (latin1.encode throws on them).
  static List<int> encode(String tspl) =>
      latin1.encode(tspl.replaceAll(RegExp(r'[^\x00-\xFF]'), '?'));
}
