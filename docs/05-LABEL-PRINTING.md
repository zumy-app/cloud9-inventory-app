# 05 — Bluetooth Label Printing (Phomemo PM-241-BT, 2"x1")

* Status: Phase 1 scaffolding on branch `label-print-bt`. No transport yet.
* Rule: phone is the printer host — the device running the app pairs over
  Bluetooth and prints. PC TSV export stays as fallback.

## What exists (code, unverified — other pipeline owns the toolchain)

* `lib/print/label_model.dart` — canonical label content (name, price,
  barcode/SKU fallback, copies). Both BT + TSV build from this.
* `lib/print/tspl.dart` — pure-Dart TSPL composer (SIZE/GAP/DENSITY/CLS,
  optional BITMAP logo, TEXT name+price row, BARCODE EAN13/128 auto-select,
  PRINT n). Golden tests in `test/tspl_test.dart`.
* `lib/print/printer_service.dart` — `PrinterTransport` interface,
  single-flight queue, persisted settings (address, darkness).
  Default transport throws an actionable "pair first" message.
* UI buttons: found card + browse detail + Add snackbar action + Labels
  batch print-all. All route through `PrinterService`; unconfigured =
  snackbar to pairing setup, never a crash.

## Phase 0 — spike (needs hardware + toolchain, NOT done)

1. Pair PM-241-BT, identify transport (SPP serial vs BLE GATT).
2. Send raw TSPL from a scratch page; photo-verify one 2"x1" label.
3. Record printable width, gap, darkness range, logo BITMAP behavior.
4. Implement `PrinterTransport` winner; add BT plugin dep (`pubspec.yaml`)
   + Android `BLUETOOTH_CONNECT`/`BLUETOOTH_SCAN` manifest entries.
5. Logo raster: needs an image codec (`image` package) to dither
   `assets/logo.png` to 1-bit; `Tspl.compose` already accepts the bytes.

## Phase 2 — verify

* `flutter analyze`, `flutter test` (incl. new golden tests).
* Pairing sheet UI, printer status chip, test-print button.
* On-device: pair → single → copies=5 → rapid 10 → paper-out recovery.
* Play data-safety note for BLUETOOTH_CONNECT ("prints price labels").

## Deferred

* Release AAB/version bump for the print feature (cut at release time).
* Higher-res logo asset (current 180px softens at 203dpi).
