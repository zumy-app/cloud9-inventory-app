# Cloud 9 Inventory App — Tech Strategy v2 (revised)

* Date: 2026-10-03 (v2 addresses critique of v1)
* Targets: **Android P0**, iOS in P2. Single Flutter codebase.
* Prod truth to confirm before code: Dockerfile pins `odoo:18.0`, but `cloud9_self_order/__manifest__.py` says `19.0.1.0.0`. Treat as **unresolved — verify `SELECT version` / prod image tag first**. All Odoo specifics below assume 18.0 until confirmed.
* Principles: minimal facade, online-first, server owns stock logic.

## 1. Decision changes from v1

| v1 issue | v2 fix |
|---|---|
| iOS day 1 | Android-only P0 via sideload / Play Internal. iOS + TestFlight in P2 after flows stable. No iOS BLE/BG work in P0. |
| Session cookie + stored password | Odoo **API keys** (per-user, revocable). App stores key, never password. Login once = key in secure storage. Revoke on logout / device loss. |
| Full offline outbox + "never lost" | **Online-first + retry queue.** Queue only `receive-line` and `count-line` payloads with idempotency keys. Banner on offline, explicit Resync button. No background sync promise on iOS. |
| Per-scan `stock.move` post + undo | **Draft receipt in app, single Validate at end.** No per-scan stock write, no reverse-move undo. Undo = remove draft line client-side. |
| Lottery as `stock.quant` | Lottery is **separate model** (`cloud9.lottery.*`), not stock. P2 only. No `stock.inventory` coupling in P0. |
| TSV share-sheet printing | P1 prints via **POST batch to backoffice** (reuse `cloud9-print-agent` pattern / `price-labels/gen-label-pngs.js`). No on-phone BLE TSPL in v1. |
| `<500ms` lookup + images inline | Target **p95 <1.5s LTE cold, <800ms warm**. Scalar-only lookup, images lazy, barcode DB index required. |
| Heavy Clean Architecture | **Vertical slices + one repo interface.** No UseCase-per-CRUD, no deferred imports, no isolate JSON until proven slow. |
| Leaf cert pinning | Pin CA / public-key backup pin + server kill-switch (`min_app_version`, `blocked`). Survives Let's Encrypt 90-day rotation. |
| `units_per_case` client memory | Use Odoo **`product.packaging`** (outer GTIN-14 vs inner UPC-12). Server converts. App only sends scanned GTIN + each/case intent. |

## 2. Architecture

```
[Flutter Android P0] --HTTPS--> [Traefik -> Odoo prod]
  DTOs (app-owned)         cloud9_inventory_api v1 (3 endpoints P0)
  Drift: draft receipts,   Postgres: barcode index, packaging, audit log
  retry queue, pos.cat cache
[Backoffice PC] POST label batch -> gen-label-pngs.js -> PM-241-BT
```

Odoo module: `cloud9market/addons/cloud9_inventory_api/`
P0 routes only:

* `POST /api/v1/auth/check` — validates API key, returns `{user, groups, api_version, min_app_version}`
* `GET /api/v1/products/lookup?barcode=` — scalar fields only: `{id, tmpl_id, variant_id, name, barcode, default_code, list_price, standard_price, pos_categ_id, packaging:[{barcode, qty}], image_128_url?}`. No `qty_available` by default; `?include_qty=1` does separate call (computed field is slow).
* `POST /api/v1/receipts/validate` — atomic: `{idempotency_key, supplier?, invoice_no?, lines:[{barcode|product_id, qty_each, new_cost?, new_price?, packaging_barcode?}]}`. Server creates products? No — product-create is separate endpoint in P0.1, manager-only. Server applies AVCO, taxes, `available_in_pos`, writes one `stock.move` set + audit log, returns before/after qtys.

P1 adds `POST /api/v1/label-batches` (server returns print-ready TSV/JSON, forwards to backoffice agent). P2 adds `counts` + `lottery` routes + `product-create`.

Contract: `{api_version:"1.0", data:..., error:{code,message}}`. App sends `X-App-Version`, `Idempotency-Key`. Server sends `min_app_version` — app forces update if behind. Keep N-1 route compat (v1 + v2 side by side for one release), never silent break.

Why upgrade-safe: app never imports Odoo field names outside `OdooRemoteDataSource`. All renames (e.g. `mobile` removal precedent, `stock.inventory` -> `quant` changes) are absorbed in the facade + `test_contract.py` run in CI against the pinned `BASE_IMAGE` before bump.

## 3. Required Odoo migrations (do first)

1. Pin version: fix `Dockerfile ARG BASE_IMAGE` vs manifest version mismatch. Confirm prod image digest.
2. `barcode` index: `product.product.barcode` + `product.packaging.barcode` need `index=True` (migration + `CREATE INDEX CONCURRENTLY` on prod). Without this lookup is full table scan.
3. `product.packaging` seed for known cases (soda 12pk, etc.). Outer-case barcode != inner-each.
4. Groups: `cloud9_inventory_clerk` (lookup, receive draft, labels) vs `cloud9_inventory_manager` (create product, set `list_price`, validate). Enforce server-side with record rules, never client-side.
5. Audit model: `cloud9.inventory.log {when, who, session_key, product_id, field, old, new, reason}`. Write in same transaction as validate. No reliance on `mail.message` chatter for compliance.
6. Price guard config: `ir.config_parameter: cloud9.price_guard_pct` (default 20) + below-cost block. Returns `needs_manager: true` instead of writing; app prompts manager API key re-auth, resubmits with `manager_key + reason`.

## 4. Mobile — simplified

```
app/lib/
  core/{env, http(dio), auth_store, scanner/, sync_queue, theme}
  features/auth/ receive/ labels/ counts/  # vertical slice: ui+repo+models together
  shared/
```

* State: Riverpod, one `ReceiveController` (draft), one `ScanController` per screen. No shared singleton scanner.
* Repo: single `InventoryRepository` interface (`lookup, validateReceipt, getCategories`). `OdooInventoryRepository` is the only Odoo-aware class.
* Scanner: `BarcodeScanner` interface, impls `MlKitScanner` + `HidScanner`.
  * HID: hidden focus-trapped input, 80ms inter-char timeout, Enter-terminated buffer. Handles wedge + keyboard coexistence. Log raw HID for store testing.
  * Camera: `mobile_scanner`, 720p, torch toggle, aim box, 500-800ms same-code lockout, manual entry fallback always visible. Test in cooler + wrinkled labels.
* Draft receipt: all in Drift `receipt_drafts + receipt_lines`. Validate = one POST. No stock change until server 200. Offline = draft persists, Validate retries with same idempotency key (safe duplicate).
* Labels P1: batch list in Drift, `POST /label-batches` -> server stores + backoffice polls/prints. App shows `queued/printing/done`, no file juggling.
* Images: lazy `image_128` only on product sheet, cached by Coil-equivalent (`cached_network_image`), never in lookup list.
* Packages: `dio, riverpod, drift, flutter_secure_storage, mobile_scanner, share_plus (P1 debug only), connectivity_plus`. No freezed unless DTOs stabilize; hand-written `fromJson` for 5 models is fine. No deferred imports.

## 5. Security + devices

* API key in `flutter_secure_storage`, key per staff user (not per device). Shared store phones: fast user switch (PIN -> swap key), plus "kiosk device key" with clerk-only scope for quick scans. Lost phone = revoke key in Odoo, no password reset needed.
* Manager approval = manager scans badge / enters API key on same device for that one `validate` call (short-lived, never stored). No client-side PIN check.
* HTTPS only, CA pin + backup pin, kill-switch via `min_app_version`. No secrets in git. Scrub barcodes/prices from logs.

## 6. Perf budget (honest)

* Lookup warm (LRU 500 + Drift): <200ms. Cold LTE scalar lookup: p95 <1.5s (Odoo `qty` excluded). With `?include_qty=1`: <2.5s.
* Validate 50-line receipt: single transaction, <5s, progress UI.
* Startup cold mid-range Android: <2s (no deferred tricks needed).
* Measure with Firebase/Sentry perf traces on `lookup` + `validate` from store WiFi before tuning further.

## 7. Build / release (reduced)

* Flavors: `dev` (staging Odoo) / `prod` (`admin.cloud9market.net`) via `--dart-define`.
* CI: `flutter analyze + test` + facade `test_contract.py` against staging. CD P0: Play Internal + sideload APK for store. iOS/TestFlight deferred to P2.
* Versioning: app `1.x` requires `api_version 1.x`. Server rejects old apps with `UPGRADE_REQUIRED` + store link.

## 8. Roadmap (realistic)

* Week 1-2: confirm Odoo version, land barcode index + groups + `auth/check + lookup` facade + Flutter shell + login (API key) + scanner test build in store.
* Week 3-5 P0: draft receipt + `validate` + product-create (manager) + packaging conversion + price guard + retry queue. Dogfood deliveries.
* Week 6 P1: label batch POST -> backoffice `gen-label-pngs.js` integration.
* Week 7-9 P2: counts (non-lottery) then lottery model + open/close + iOS build.

## 9. Requirement changes needed

* REQ-REC-4: change "posts stock.move per scan + undo" -> draft + single validate.
* REQ-REC-5: manager PIN -> manager API-key approval server-side.
* REQ-INV-3/4: remove `stock.inventory` language, replace with `cloud9.lottery.*` snapshots + manager validate.
* REQ-NFR-1: 500ms -> p95 targets above. REQ-NFR-2: offline -> online-first + retry.
