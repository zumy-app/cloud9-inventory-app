# Cloud 9 Market — Inventory Mobile App: Requirements v1

* Date: 2026-10-03
* Target: Odoo 18 Community prod (`admin.cloud9market.net`, DB `odoo`)
* Users: Market clerks + managers
* Devices: Android phones (primary), camera + Bluetooth HID scanner

Priority order (per owner):
P0 = Delivery receiving, P0 enabler = Login once, P1 = Continuous scan + print labels, P2 = Scan-based inventory / lottery open-close.

## 1. Goals / Non-Goals

Goals:

* Scan a delivery box/carton/case, instantly find the product in Odoo, update cost / price / qty.
* Create missing products in <30 sec with remembered POS category.
* Accumulate barcodes in bulk, one-tap label export.
* Daily start/end counts, incl. lottery bins.

Non-goals v1:

* No Purchase Order / vendor EDI, no accounting, no `/market` catalog editing.
* No changes to Odoo core. If needed, add small `cloud9_inventory` addon for batch RPC only.
* Label rendering/printing workflow after export is owner-built (reuse `price-labels/gen-label-pngs.js`).

## 2. FR-0 Auth — Login Once [P0 enabler]

* REQ-AUTH-1: Login with Odoo URL (default `https://admin.cloud9market.net`), DB (`odoo`), username, password via `/web/session/authenticate`.
* REQ-AUTH-2: Persist session (secure storage, Keychain/Keystore). Stay logged in 30 days. Auto re-auth on 401. Explicit Logout wipes tokens.
* REQ-AUTH-3: Least-privilege Odoo users. Enforce in app + Odoo groups:
  * Clerk: receive, count, label batch.
  * Manager: create product, change `list_price`, validate inventory adjustments.
* REQ-AUTH-4: Header shows user + DB + online/offline state.

## 3. FR-1 Delivery Receiving [P0]

User story: *Box arrives, I scan eaches, fix cost/price/qty, shelve.*

* REQ-REC-1 Session: `+ New Receipt` with supplier (optional v1), invoice #, staff, timestamp. All scans attach to `session_id` for audit/undo.
* REQ-REC-2 Single-scan loop:
  * Scan -> lookup `product.product` by `barcode`, fallback `default_code`.
  * Found -> bottom sheet: image, name, barcode, SKU, pos categ, `standard_price`, `list_price`, `qty_available`. Editable: Purchase Price, Sale Price, Qty Received (default 1, stepper + keypad). `Save & Next` posts immediately.
  * Not found -> New Product form prefilled `barcode=<scan>`: name*, pos.category* (default = last scan category, persisted per-device + per-user), purchase_price, sale_price, quantity, SKU (auto-suggest), inventory categ, tax. Save creates `product.template` with `available_in_pos=True`, `sale_ok=True`.
* REQ-REC-3 Units: Each / Case toggle + `units_per_case` remembered per barcode. Outer-case vs inner-each barcodes both supported. Case scan = N eaches.
* REQ-REC-4 Stock write: receiving posts `stock.move` (Supplier -> WH/Stock), not direct quant overwrite. Show before/after qty. Support `Undo last scan` in session.
* REQ-REC-5 Price guard: if new `list_price` < cost or delta > configurable % (default 20%), require manager PIN + reason. Log old->new.
* REQ-REC-6 Search fallback: name/SKU search when no barcode. Duplicate-barcode collision warning. No-barcode in-store SKU path (Code128 fallback, same rules as `price-labels`).
* REQ-REC-7 Summary: lines, total cost, price-changed lines flagged.

Odoo mapping:

| App | Odoo |
| --- | --- |
| barcode | `product.product.barcode` |
| name | `product.template.name` |
| SKU | `product.product.default_code` |
| POS categ | `product.template.pos_categ_ids` |
| sale | `product.template.list_price` |
| cost | `product.template.standard_price` |
| on-hand | `product.product.qty_available` |
| receive | `stock.move` |
| tax | `product.template.taxes_id` |

## 4. FR-2 Continuous Scan + Print Labels [P1]

User story: *Walk aisle, scan 50 tags needed, hit Print.*

* REQ-LBL-1 Batch mode: scanner listener appends `{barcode, name, price, copies}` with beep/vibrate/running count. No modal per scan. Same code increments copies.
* REQ-LBL-2 Batch list: edit copies, swipe delete, clear all. Persists across app kill.
* REQ-LBL-3 Generate: one tap exports TSV/JSON matching `gen-label-pngs.js` input: `name, list_price, barcode, default_code, category`. Share sheet + POST hook for owner print workflow.
* REQ-LBL-4 Barcode rules (same as `price-labels/README.md`): 11-digit UPC-A, 12-13 digit EAN-13, else Code128/SKU, else `NO BARCODE`.

## 5. FR-3 Stocktake / Lottery [P2]

User story: *Start/end of day counts, lottery bins reconciled.*

* REQ-INV-1 Count types: Full / Category / Lottery Open / Lottery Close. Fields: date, type, staff, blind-count toggle (hide expected qty).
* REQ-INV-2 Scan-to-count: scan -> expected qty (if not blind) -> enter counted qty. Rescan increments.
* REQ-INV-3 Lottery: per game/bin: `game, bin, start_seq, end_seq, start_value, end_value, sold, payout`. Open snapshot vs close snapshot, variance report for NJ lottery shift close.
* REQ-INV-4 Post: draft `stock.inventory` lines, Manager Validate only. Variance > threshold blocks auto-post, requires note.
* REQ-INV-5 Report: expected vs counted, variance $, CSV export.

## 6. Cross-cutting / NFR

* REQ-NFR-1 Perf: scan->result <500ms LTE, camera focus <1s.
* REQ-NFR-2 Offline: SQLite queue, sync on reconnect, conflict warning if Odoo qty/price changed meanwhile.
* REQ-NFR-3 Audit: every price/qty/product-create logs who/when/old->new/session (Odoo chatter or custom log model).
* REQ-NFR-4 Security: HTTPS only, no secrets in git, secure token store.
* REQ-NFR-5 UX: portrait one-handed, large targets, high-contrast for coolers, hardware-scanner compatible (volume-button confirm), remember last POS category.
* REQ-NFR-6 Categories: seed from `CONVENIENCE_STORE_CATEGORY_SCHEMA.md` (Tobacco, Drinks, Snacks, Fresh Food, Automotive, Propane, Ice, General Merchandise, Lottery/Games, Services).

## 7. Suggested Additions (were missing)

1. Supplier + invoice capture, cost history per product.
2. Low-stock / zero-barcode dashboard.
3. Expiry/lot for Fresh Food (future).
4. Reprint single label from product card.
5. Multi-pack / age-restricted (tobacco/lottery) flags.

## 8. Open Questions

1. Cost method: last-cost overwrite vs AVCO? (Odoo default AVCO)
2. Can clerks create products or manager-only?
3. Labels print from back-office PC (`print-labels.ps1`) or direct from phone to PM-241-BT?
4. iOS needed v1 or Android-only?
5. Expiry/lot tracking needed for Fresh Food v1?

## 9. Next Steps

1. Confirm questions above.
2. Draft Odoo RPC contract: `product lookup, receive, product create, label export, inventory validate`.
3. Prototype scan loop UX, then build P0 only.
