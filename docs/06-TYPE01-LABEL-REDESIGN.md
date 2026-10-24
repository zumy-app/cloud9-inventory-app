# 06 — Type 01 Label Redesign Tech Plan (regular retail everyday)

* Source of truth: `labels-wireframes/type01-mockup.html` (approved) + `labels-wireframes/code.html` Card 1.
* Scope: **Type 01 only**. Types 02–04 + kitchen preview untouched (their turn after this ships).
* Rule carried over from 02: **zero Odoo changes**. New fields are app-local (defaults + per-line overrides).
* Timebox: 1–2 days, 1 dev. If TSPL hardware verification blocks, ship preview first, print second.

## 0. Repro first (before any redesign)

The "no barcode" complaint has three distinct causes — confirm which one on-device before changing layout:

1. Product has no barcode AND no SKU → placeholder is correct behavior; fix = capture a code, not layout.
2. `compact: true` collapse in Labels list / print-job rows (bars squeeze to ~0px) → fixed by the min-bay-height rule in §4.
3. Invalid data for the symbology → `BARCODE ERROR` text → fixed by keeping `normalizeCode` as the single classifier.

Repro: pump the exact product the reviewer used, in both full and compact widths. If (1), the redesign still shows an explicit `ADD BARCODE` state — never blank.

## 1. What changes (4 files + tests)

```
app/lib/print/label_model.dart       # +7 optional fields, defaults keep old lines working
app/lib/label_collections.dart       # CollectionLine carries + persists the 7 fields (tolerant fromJson)
app/lib/widgets/label_preview.dart   # _StandardPreview rewritten to mockup zones A–D
app/lib/print/tspl.dart              # _composeStandard mirrored zone-for-zone
app/test/label_preview_test.dart     # updated expectations (single-line title, badges, GS1 band)
app/test/tspl_test.dart              # updated zone/budget goldens + new field tests
app/lib/i18n/lang.dart               # new strings, en + es
```

TSV export (`toTsv` in both stores) stays byte-identical — `gen-label-pngs.js` on the PC is unaffected.

## 2. Model: new fields (all optional, all defaulted)

```dart
// LabelModel additions — every existing constructor call compiles unchanged.
final String shelfLoc;    // 'AISLE 04-B2 • DELI FRESH'. '' = fall back to category, then hidden.
final String verifyDate;  // 'MM/YY' override. '' = auto-stamp current MM/YY at render (preview and TSPL
                          // both compute it, so they agree; explicit value wins). Chip always shows — it is a
                          // compliance date, never blank-by-design.
final String slot;        // Slot codes, lines split on '\n' ('MK-203D\nST-084'). '' = block hidden.
final String dept;        // '04' -> 'DEPT 04'. '' = hidden.
final String allergens;   // 'CONTAINS GLUTEN/DAIRY'. '' = omitted from subtitle row.
final bool taxable;       // false = TAXABLE chip hidden. Default false: never claim tax status we don't know.
final String eachText;    // Unit word under cents ('EACH'). Default '' = hidden. 'EACH' is opt-in per
                          // store/line — a weighed ($/LB) item stamped EACH is wrong data.
```

* `copyWith` gains the same 7 params. `fromProduct` leaves them at defaults (Odoo has no source for them — see §3).
* `Tspl.verifyStamp(DateTime now)` helper formats MM/YY; preview and TSPL share it.
* `displayName`, `code`, `hasCode`, `splitNameSize` untouched.
* Open question (needs owner confirm): wireframe `C9-GROC` is a store code, not a category. Implemented as uppercased category shortcode (≤12 chars) until confirmed.

* `copyWith` gains the same 7 params. `fromProduct` leaves them at defaults (Odoo has no source for them — see §3).
* `displayName`, `code`, `hasCode`, `splitNameSize` untouched.

## 3. Where values come from (no Odoo fields exist for these)

Two tiers, mirroring how the promo section already works (`showLabelPreviewSheet` gets `initialPromo` + `onPromoChanged`):

1. **Store defaults** — new `LabelDefaults` in `label_collections.dart` (SharedPreferences keys `lbl_slot`, `lbl_shelf`, `lbl_verify`, `lbl_dept`, each set once per store in a small settings row on the Labels tab). Applied at pick time when a line is created.
2. **Per-line override** — extend the preview bottom sheet with a "Shelf tag" section (same pattern as the promo `ExpansionTile`): 5 text fields + taxable switch. Writes through to the `CollectionLine`.

Fallback chain in render: `shelfLoc` → `category` → hidden. `C9-GROC` micro text ← `category` (short, uppercased, max 12 chars). Nothing renders a blank/empty chip — every new zone is hidden when its source is empty (same defensive rule as `unitPriceText` returning null).

## 4. Preview rewrite (`_StandardPreview`, zones A–D per mockup)

* Frame: `border: black 2px`, `borderRadius: 0` (was grey + rounded). Matches thermal die-cut + wireframe sharp-0 rule.
* **A header:** logo left + `slot` stacked micro (`MK-203D` 8px / `ST-084` 7px, divider line); right: shelf line 9px mono bold + row (`VERIF:` black knockout chip + category micro). All three right-side elements hide independently when empty.
* **B title:** two-tier via `Tspl.titleFit` — full 18px to 30 chars, smaller 13px cut to 44 chars; ellipsis only past 44 (was: cut at 30). Subtitle row: `size • allergens` 8px left, `TAXABLE` bordered chip right (hidden when `!taxable`). Logo: `assets/logo.png` cropped to the oval (was full-bleed navy square) and enlarged 28→36px (compact 14→18) to use the header space.
* **C barcode bay (the "don't show barcode" fix):** `LayoutBuilder` enforces **min bay height 56px** (bars never collapse in `compact: true` lists — the current failure in `browse.dart:456` / `print_job_screen.dart:178`). Data path unchanged (`normalizeCode` → UPCA/EAN13/128, `drawText: false` + digits line). Empty code → explicit `ADD BARCODE` placeholder state (was `NO BARCODE` text that looked like a rendering bug). Unit cell becomes **black knockout** (`UNIT PRICE:` left, value right) per wireframe.
* **D price block:** top row `EVERYDAY RETAIL` black badge + `DEPT 04` (hidden when dept empty); hero `$` 26 / int **64** / cents 26 with `eachText` under cents (drop the `RETAIL` chip — not in wireframe); bottom full-width black band `GS1 COMPLIANT SHELF EDGE` (static hardcoded English — see i18n rule below).
* **Compact scale (applies in Labels list + print-job rows):** pad 10→5, logo 28→14, title 18→12, hero int 64→22, `$`/cents 26→10, micro 9→7, badge 9→6px with zero letterspacing. Hidden at compact: slot block, store code, subtitle/TAXABLE row, unit cell, EACH, DEPT, GS1 band. Bulletproofing (added after the constraint pump caught real overflows): `FittedBox.scaleDown` around the badge and the hero row, so long prices/codes can never push past narrow columns. Print-job thumbnail widened 140→180px (`print_job_screen.dart`). Verified by fixed-constraint pumps (400px full + 180px compact) asserting `takeException()` is null and bars present.
* Printed badge/furniture strings stay **hardcoded English** (current precedent: `RETAIL`, `SPECIAL VALUE`, `NOW`) so print and preview agree in both app languages. Only the sheet's *UI labels* ("Shelf tag", field hints) get `en`+`es` i18n keys.
* Fonts stay bundled (`BarlowCondensed`/`SpaceMono`); no network fonts.

## 5. TSPL mirror (`_composeStandard` only)

Same zones, same order, same hide-when-empty rules. Coordinates for the 384×200 canvas:

| Step | Dots | Running y |
|---|---|---|
| header (logo crop 150 + cat/SKU right) | 30 | 2 → 32 |
| title 1× font2 (was 2 lines, saves 21) | 21 | 37 → 58 |
| micro sub | 13 | 58 → 71 |
| badge/DEPT row (font1 + BOX) | 15 | 76 → 91 |
| lower block: barcode 56 + digits + unit BOX ≈ 81; hero `py+58+13` ≈ 79 | ≤ 81 | 91 → ≤ 172 |
| GS1 band (`BOX` + centered TEXT, fixed) | 13 | 185 → 198 |

Worst case ends at **≈198/200** — advisory arithmetic, not a guarantee. The composer asserts at runtime in debug (`assert(y <= heightDots)`) and the golden test pins the exact end position; if a future field pushes past 200, the test fails instead of the printer clipping.
Knockouts (`unitbar`, `EVERYDAY RETAIL`, GS1 band, VERIF chip) via `REVERSE` placed **after** their `TEXT` (so a firmware that ignores `REVERSE` still shows readable black-on-white — same grace rule rapid/promo use; Phase D photo-verify decides per band). Hero keeps the existing `intFont` fallback (3+ digit ints → font 4). `encode()` Latin-1 sanitizer covers the `•` separators (replaced with `?` on-wire; preview keeps `•`).

## 6. Tests (must stay green: `flutter analyze`, `flutter test`)

* `tspl_test.dart`: rewrite the `type01` golden for the new zone sequence (single title line, badge row, GS1 band at fixed y); add: per-field hide tests (empty `shelfLoc`/`slot`/`dept`/`allergens` omit their zones), `taxable=false` omits chip, `verifyStamp` MM/YY format, `eachText=''` omits unit word, end-position pin (`≤ 200`), `REVERSE` follows its `TEXT` (fallback order).
* `label_preview_test.dart`: update type01 (single-line title, `EVERYDAY RETAIL`, `DEPT`, `EACH` only when set, GS1 band, `TAXABLE` hidden by default); add: **fixed-constraint pumps** (full 400px + compact 180px) asserting `tester.takeException()` is null (catches overflow/collapse — `find.text` alone cannot), `ADD BARCODE` state for codeless models, barcode bars present (`find.byWidgetPredicate` on `BarcodeWidget`) in both scales.
* New `label_model_test.dart` cases: defaults (`taxable` false, `eachText` ''), `copyWith` round-trip, `CollectionLine` JSON round-trip with **legacy JSON** (missing keys → defaults, no crash).
* Manual: Labels tab → full preview + compact list + print-job rows on both test devices (Pixel 7 Pro `36121FDH30002B`, Samsung `R5CXC2YATLA`).

## 7. Build order (demo after each)

1. Model + collections persistence + tests. Demo: old collections load, new fields round-trip.
2. Preview rewrite + sheet "Shelf tag" section + i18n. Demo on both devices: full + compact, codeless product shows `ADD BARCODE`, never blank.
3. TSPL mirror + golden updates. Demo: `PRINT` byte diff reviewed, budget assert passes.
4. Store defaults UI (one row on Labels tab). Demo: set once → new picks inherit.
5. Hardware: Phase D photo-verify one Type 01 on PM-241-BT (scan the UPC, check quiet zones, confirm `REVERSE` renders or flip to bordered fallback).
6. Release: bump `+8` → `+9`, `flutter build apk --release --dart-define API_BASE=...`, install both devices.

## 8. Risks

* **200-dot overflow** if title ellipsis misbehaves with very long single words — mitigated by existing `…` truncation + budget assert in tests.
* **Phomemo ignores `REVERSE`** — already handled by graceful fallback; photo-verify decides per band.
* **TSC bitmap fonts differ** (hero metrics assume font 5 = 32 dots/char) — same assumption as today; calibration print in step 5 confirms before locking.
* Out of scope on purpose: Types 02–04 restyle, kitchen preview (Type 04 has none — tracked next), Odoo-sourced shelf/slot data, TSV column changes.
