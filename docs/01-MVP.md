# Cloud 9 Inventory App — POC / MVP (cut scope to ship now)

* Date: 2026-10-03
* Goal: staff can use it in the store this week for deliveries. Nothing fancy.
* Platform: **Android only**, online-only, camera scan only. No iOS, no offline, no Odoo changes.

If it’s not needed to receive a box today, it’s out.

## MVP scope (3 screens only)

1. **Login** — Odoo URL (fixed to `https://admin.cloud9market.net`), DB (`odoo`), username, password via existing `/web/session/authenticate`. Save session cookie in secure storage. One shared staff user for POC. Logout clears. No API keys, no scopes, no user switch.
2. **Receive (single-scan loop)** — the whole app:
   * Tap Scan → camera (ML Kit via `mobile_scanner`) → barcode string.
   * App calls standard Odoo `call_kw`: `product.product search_read` by `barcode` (fallback `default_code`), returns `name, barcode, list_price, standard_price, pos_categ_ids, qty_available`.
   * **Found:** show name, barcode, cost, price, on-hand. Editable: `Purchase Price, Sale Price, Qty Received (default 1)`. `Save` does 2 writes max: update template prices + bump qty via `stock.quant` (`inventory_quantity = on-hand + received`). Show toast, ready for next scan. No draft, no batch, no undo (delete/adjust manually in Odoo if mistake).
   * **Not found:** minimal form prefilled `barcode=`: `name*, pos.category dropdown* (default = last used, stored in SharedPreferences), sale_price, purchase_price, qty`. Save creates `product.template` with `available_in_pos=True, sale_ok=True, purchase_ok=True`, default `categ_id`, default taxes. No SKU, no image, no supplier, no search.
3. **Labels (stretch, include only if trivial):** second tab `Batch` — every scan in Receive has `[+ Label]` toggle; Batch lists `{barcode, name, price, copies}`, +/-/clear, `Share TSV` via `share_plus` in `gen-label-pngs.js` format. No backend, no BLE printing — owner prints from PC as today.

## Explicitly OUT for MVP

* iOS / TestFlight, HID Bluetooth scanner, offline queue, retry/sync, background tasks.
* Case/box barcodes, `product.packaging`, units-per-case. Enter eaches qty manually.
* Supplier, invoice #, sessions, summaries, price-guard / manager approval, audit log (use Odoo history for now).
* Inventory counts, lottery open/close, images, name/SKU search, duplicate-barcode handling (just show error text), cert pinning, flavors, Firebase/Sentry.
* Any new Odoo module, any migration. If lookup is slow with <5k SKUs, add barcode index later.

## Minimal tech

* Flutter + `dio` (or `http`) + `mobile_scanner` + `flutter_secure_storage` + `shared_preferences` + `share_plus`. No Riverpod/Drift/freezed needed — 1 `OdooClient` class + `setState` is fine for POC. Split later.
* Files: `lib/main.dart, lib/odoo_client.dart, lib/screens/{login,receive,labels}.dart`. That’s it.
* Odoo calls only: `authenticate`, `product.product search_read`, `product.template write/create`, `stock.quant search/write`, `pos.category search_read` (fetch once, cache 24h).

## Done = usable

* Login persists across restarts; logout works.
* Scan 20 delivery items in a row without crash; each Save updates Odoo (verify in Odoo backend).
* Create 2 new products with remembered POS category; rescan finds them.
* Batch Share produces TSV that `gen-label-pngs.js` accepts (if Labels included).

## After MVP (in order)

1. Barcode DB index + `product.packaging` for cases.
2. Draft receipt + single Validate + idempotency (kill per-scan writes).
3. `cloud9_inventory_api` facade + manager approval + audit (per TECH-STRATEGY v2).
4. HID scanner support, then counts, then lottery model, then iOS.
