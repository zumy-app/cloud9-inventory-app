// 1-bit logo raster for 2"x1" thermal labels.
// Decodes assets/logo.png, downscales to the TSPL dot budget
// (Tspl.maxLogoWidthDots x Tspl.maxLogoHeightDots), Floyd-Steinberg
// dithers to 1-bit, caches in memory. Failures return null so labels
// print without a logo instead of crashing.
library;

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'tspl.dart';

class LogoRaster {
  LogoRaster._();

  static ({List<int> mono, int width, int height})? _cache;
  static String? _cacheKey;

  /// Rasterize raw image bytes (png/jpg) to 1-bit row-major pixels.
  /// Pure logic, unit-testable without asset bundles.
  static ({List<int> mono, int width, int height})? rasterize(
    List<int> bytes, {
    int maxWidth = Tspl.maxLogoWidthDots,
    int maxHeight = Tspl.maxLogoHeightDots,
  }) {
    try {
      final decoded = img.decodeImage(Uint8List.fromList(bytes));
      if (decoded == null) return null;
      final scale = _scale(
        decoded.width,
        decoded.height,
        maxWidth,
        maxHeight,
      );
      final resized = scale < 1.0
          ? img.copyResize(
              decoded,
              width: (decoded.width * scale).round().clamp(1, maxWidth),
              height: (decoded.height * scale).round().clamp(1, maxHeight),
            )
          : decoded;
      final w = resized.width;
      final h = resized.height;
      if (w <= 0 || h <= 0 || w > 2000 || h > 200) return null;
      // Grayscale buffer composited over white (handles PNG alpha).
      final buf = List<double>.filled(w * h, 255);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = resized.getPixel(x, y);
          final a = p.a.toDouble();
          final lum =
              0.299 * p.r.toDouble() + 0.587 * p.g.toDouble() + 0.114 * p.b.toDouble();
          final overWhite = lum * (a / 255.0) + 255.0 * (1.0 - a / 255.0);
          buf[y * w + x] = overWhite.clamp(0, 255);
        }
      }
      // Floyd-Steinberg dither to 1-bit (1 = black, like Tspl.compose).
      final mono = List<int>.filled(w * h, 0);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          final old = buf[i];
          final next = old < 128 ? 0.0 : 255.0;
          mono[i] = next == 0.0 ? 1 : 0;
          final err = old - next;
          if (x + 1 < w) buf[i + 1] += err * 7 / 16;
          if (y + 1 < h) {
            if (x > 0) buf[i + w - 1] += err * 3 / 16;
            buf[i + w] += err * 5 / 16;
            if (x + 1 < w) buf[i + w + 1] += err * 1 / 16;
          }
        }
      }
      return (mono: mono, width: w, height: h);
    } catch (_) {
      return null;
    }
  }

  static double _scale(int w, int h, int maxW, int maxH) {
    if (w <= 0 || h <= 0) return 1.0;
    final s = [maxW / w, maxH / h].reduce((a, b) => a < b ? a : b);
    return s >= 1.0 ? 1.0 : s;
  }

  /// Load + rasterize the bundled store logo (cached per max-size).
  static Future<({List<int> mono, int width, int height})?> bundled({
    String asset = 'assets/logo.png',
    int maxWidth = Tspl.maxLogoWidthDots,
    int maxHeight = Tspl.maxLogoHeightDots,
  }) async {
    final key = '$asset@${maxWidth}x$maxHeight';
    if (_cache != null && _cacheKey == key) return _cache;
    try {
      final data = await rootBundle.load(asset);
      final r = rasterize(
        data.buffer.asUint8List(),
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
      _cache = r;
      _cacheKey = key;
      return r;
    } catch (_) {
      return null;
    }
  }

  /// Test-only cache reset.
  static void clearCache() {
    _cache = null;
    _cacheKey = null;
  }
}
