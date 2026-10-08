import 'package:cloud9_inventory_app/print/label_model.dart';
import 'package:cloud9_inventory_app/print/logo_raster.dart';
import 'package:cloud9_inventory_app/print/tspl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('rasterize downscales to the dot budget and emits 1-bit pixels', () {
    // 400x100 white image with a black bar -> must shrink to ≤240x24.
    final src = img.Image(width: 400, height: 100);
    img.fill(src, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(src,
        x1: 0, y1: 40, x2: 399, y2: 59, color: img.ColorRgb8(0, 0, 0));
    final png = img.encodePng(src);
    final r = LogoRaster.rasterize(png);
    expect(r, isNotNull);
    expect(r!.width, lessThanOrEqualTo(Tspl.maxLogoWidthDots));
    expect(r.height, lessThanOrEqualTo(Tspl.maxLogoHeightDots));
    expect(r.mono.length, r.width * r.height);
    expect(r.mono.any((v) => v == 1), isTrue); // black bar survived
    expect(r.mono.any((v) => v == 0), isTrue); // white survived
    expect(r.mono.every((v) => v == 0 || v == 1), isTrue);
  });

  test('rasterize returns null for garbage bytes, never throws', () {
    expect(LogoRaster.rasterize([0, 1, 2, 3]), isNull);
    expect(LogoRaster.rasterize([]), isNull);
  });

  test('raster output feeds Tspl.compose bitmap path', () {
    final src = img.Image(width: 16, height: 8);
    img.fill(src, color: img.ColorRgb8(0, 0, 0));
    final r = LogoRaster.rasterize(img.encodePng(src))!;
    const m = LabelModel(name: 'n', price: 1, barcode: '1');
    final out = Tspl.compose(m, logoMono: r.mono, logoWidth: r.width);
    expect(out, contains('BITMAP'));
  });
}
