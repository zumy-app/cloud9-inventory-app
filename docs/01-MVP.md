# Cloud 9 Inventory App — POC / MVP (cut scope to ship now)

* Date: 2026-10-03
* Revised: 2026-10-05 — v2 inventory loop (supersedes §MVP scope / §After-MVP for
  this slice; `02/03/04` otherwise untouched — this doc supersedes `03` §FR-1/FR-3
  for ad-hoc scan-fix-next only, not for sessions/variance).
* Goal: staff can use it in the store this week for deliveries. Nothing fancy.
* Platform: **Android only**, online-only, camera scan only. No iOS, no offline, no Odoo changes.

If it’s not needed to receive a box today, it’s out.

## MVP scope (3 screens only)

1. **Login** — Odoo URL (fixed to `https://admin.cloud9market.net`), DB (`odoo`), username, password via existing `/web/session/authenticate`. Save session cookie in secure storage. One shared staff user for POC. Logout clears. No API keys, no scopes, no user switch. Credentials are kept in secure storage so a 401 mid-shift triggers one transparent re-login + retry — an expired session never wipes an in-progress form.
2. **Receive / Count (scan-fix-next loop)** — the whole app. Two modes behind one
   visible toggle (`Receive +` | `Count =`), persisted per-device:
   * Tap Scan → camera (ML Kit via `mobile_scanner`) → barcode string. Manual
     barcode field with Go always available. Supported: UPC-A/E, EAN-8/13,
     Code128, Code39.
   * App calls standard Odoo `call_kw`: `product.product search_read` by
     `barcode` (fallback `default_code`, limit 2), returns `name, barcode,
     default_code, list_price, standard_price, pos_categ_ids, qty_available`.
   * Every lookup failure is a specified row state, never a dead sheet:
     `offline` (retry + barcode-only provisional line), `401`
     (`Session expired — sign in again`), `not found` (→ new-item form),
     `duplicate` (→ variant picker, Save blocked until one is picked).
   * **Found, Receive + mode (additive):** show name, barcode, SKU, on-hand,
     cost, price. Editable: name, `Qty to add (≥1, default 1, stepper+keypad)`,
     cost, price, SKU, Category (single autocomplete, §Category mapping).
     One `Update` button saves everything changed: details always, plus
     stock (`on-hand + entered`) when a qty is entered — empty qty means
     details only (stated under the field and in the toast). Show toast,
     clear, focus scan. No draft, no batch, no undo (fix in Odoo).
   * **Found, Count = mode (absolute):** qty field blank by default (forced
     entry — no silent zero). Price fields hidden behind `Adjust price` link.
     `Set count` requires qty ≥ 0 then mandates a `before → after` confirm
     sheet showing the resulting absolute number; write sets
     `inventory_quantity = counted` directly (new `setStock`, not `addStock`).
     Blank qty + `Adjust price` = prices-only fix, no stock write.
   * **Not found (both modes):** form prefilled locked `barcode=<scan>`:
     `name* (≥2 chars), Category* (default = last pair), cost, price, qty,
     SKU (auto-suggest = scan if numeric)`, sellable/purchasable toggles
     (default ON, inside collapsed Details). `Create & next` creates
     `product.template` (`available_in_pos=True, sale_ok=True,
     purchase_ok=True`, mapped `categ_id`, `pos_categ_ids=[[6,0,[id]]]`,
     `type=consu` + `is_storable=True` (Odoo 18 gate for quants — `product`
     is not a valid type value)
     ) → variant barcode write → initial quant; shows `0 → qty`
     confirm line. No image, no supplier, no expiry.
   * **Price guard:** new price `< cost` or `|Δ| > 20%` (config constant) shows
     inline warning; below-cost writes additionally require a typed reason
     (recorded in the audit line). Stepping stone to manager-key approval (P1).
   * **SKU collision:** on SKU edit/create, `product.product search_read`
     on `default_code` (limit 2); collision on another variant blocks Save
     until changed or `Use anyway` + reason.
3. **Labels:** second tab `Batch` — every scan in Receive has `[+ Label]`
   toggle; Batch lists lines keyed by `barcode || default_code || name`
   (so barcode-less items never merge), `{barcode, name, price, copies}`,
   +/-/clear, `Share TSV` via `share_plus` in `gen-label-pngs.js` format
   (`name, list_price, barcode, default_code, category` — `default_code` and
   category now populated from lookup at add time). No backend, no BLE
   printing — owner prints from PC as today.
4. **Continuous mode:** `Continuous` toggle in Receive app bar opens a
   stay-open scan sheet (500–800ms same-code lockout, torch, beep + haptic,
   running count, manual entry row). New barcode → compact card (name/on-hand
   + qty stepper default 1, cost/price collapsed); rescan same barcode →
   `qty++` with beep, no duplicate card. Scanning a new barcode **auto-saves
   qty only**; any touched-but-unconfirmed cost/price/SKU/category field forces
   a one-tap `Save changes / Discard` prompt first. Text fields are never
   auto-persisted. Every save (receive +1, scan-away auto-save, manual save)
   ends in a green/red result banner; Count mode additionally requires the
   `before → after` confirm before any write, and exiting with a pending item
   offers Save & exit / Discard / Stay. Exit anytime via X.
5. **Category mapping:** one `Category` field with type-to-filter over the
   union of `pos.category` + `product.category` (`Drinks › Soda`). Backed by an
   explicit seeded table (from `CONVENIENCE_STORE_CATEGORY_SCHEMA.md`:
   Tobacco, Drinks, Snacks, Fresh Food, Automotive, Propane, Ice, General
   Merchandise, Lottery/Games, Services) mapping each POS category → one
   internal `categ_id`. Unmapped selection blocks with `Unmapped — pick
   again`; no silent default fallback. Writes both `categ_id` and
   `pos_categ_ids`; remembers last pair per device.
6. **Audit:** every price/qty/create writes one in-app log line
   `{when, who, mode, product_id, field, old → new, reason?}` (200-line cap,
   shown in confirmation). No new Odoo model in this slice — stepping stone
   to `cloud9.inventory.log` (per TECH-STRATEGY v2).

## Explicitly OUT for MVP

* iOS / TestFlight, HID Bluetooth scanner, offline queue, retry/sync, background tasks.
* Case/box barcodes, `product.packaging`, units-per-case. Enter eaches qty manually.
* Supplier, invoice #, sessions, summaries, blind count, variance report (P2).
* Manager-key approval (P1 — reason-field above is the stepping stone),
  `cloud9_inventory_api` facade (P1), `cloud9.inventory.log` model (P1).
* Draft receipt + single Validate + idempotency (P1 — per-scan immediate
  writes stay for this slice).
* Inventory sessions, lottery open/close, images, name/SKU search,
  cert pinning, flavors, Firebase/Sentry.
* Any new Odoo module, any migration. If lookup is slow with <5k SKUs, add barcode index later.

## Minimal tech

* Flutter + `http` + `mobile_scanner` + `flutter_secure_storage` + `shared_preferences` + `share_plus`. No Riverpod/Drift/freezed needed — 1 `OdooClient` class + `setState` is fine for POC. Split later.
* Files: `lib/main.dart, lib/odoo_client.dart, lib/category_map.dart, lib/audit_log.dart, lib/screens/{login,receive,scan_sheet,batch}.dart`. (`scan.dart` superseded by `scan_sheet.dart` when continuous lands.)
* Odoo calls only: `authenticate`, `product.product search_read` (lookup + SKU check), `product.template write/create`, `product.product write` (variant barcode), `stock.quant search/write/create (+action_apply_inventory best-effort)`, `pos.category search_read` + `product.category search_read` (fetch once, cache 24h).

## Done = usable

* Login persists across restarts; logout works.
* 20 mixed items in Receive + mode: Odoo shows `old + entered` per line; audit list has 20 lines.
* 20 items in Count = mode: each required the `before → after` confirm; spot-check 5 in Odoo backend, all absolute.
* Attempt: duplicate barcode (blocked until variant picked), below-cost price (reason required), empty qty in Count (blocked), mid-edit scan-away in continuous (prompt appears, nothing auto-saved except qty).
* New item with `dri` → Drinks mapping correct in both `categ_id` and `pos_categ_ids`; rescan finds it.
* Airplane-mode scan in each mode shows the specified error state, no crash, no lost input.
* Batch Share produces TSV that `gen-label-pngs.js` accepts.

## After MVP (in order)

1. Manager-key approval (price guard P1) + `cloud9.inventory.log` audit model.
2. Draft receipt + single Validate + idempotency (kill per-scan writes) + `cloud9_inventory_api` facade (per TECH-STRATEGY v2).
3. `product.packaging` for cases + barcode DB index.
4. Blind count + sessions + variance report (P2), then HID scanner, then counts, then lottery model, then iOS.
