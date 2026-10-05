# 02 — MVP Tech Plan (build this now)

* Builds `01-MVP.md`. Nothing from `03`/`04` until MVP is in the store.
* Target: Android-only Flutter POC, online-only, **zero Odoo changes**.
* Timebox: 2–4 days, 1 dev. If a task takes >half a day, cut it.

## 1. What we build

```
app/
  lib/main.dart                 # tabs: Receive | Batch | Account
  lib/odoo_client.dart          # 1 class, 6 methods (below)
  lib/screens/login.dart
  lib/screens/receive.dart      # scan -> card -> save
  lib/screens/batch.dart        # label list + Share TSV (stretch)
  pubspec.yaml                  # http, mobile_scanner, flutter_secure_storage,
                                # shared_preferences, share_plus
```

No Riverpod/Drift/freezed. `setState` + `OdooClient` singleton is enough. Split later.

## 2. Odoo contract (stock JSON-RPC, no custom module)

Base: `https://admin.cloud9market.net`. All calls keep session cookie from login.

1. `POST /web/session/authenticate` → `{db:"odoo", login, password}` → store `session_id` cookie in `flutter_secure_storage`. Reuse until 401, then re-login screen.
2. `POST /web/dataset/call_kw/product.product/search_read`
   args: domain `["|", ["barcode","=",SCAN], ["default_code","=",SCAN]]`, fields `["id","product_tmpl_id","name","barcode","default_code","list_price","standard_price","pos_categ_ids","qty_available"]`, limit 2.
   * 0 rows → New Product form. 2+ rows → show "duplicate barcode" error, pick first, log for cleanup.
3. `POST /web/dataset/call_kw/pos.category/search_read` once at login, cache in memory + `shared_preferences` 24h. Fields `["id","name"]`.
4. Save existing: `product.product` → resolve `tmpl_id`, then `call_kw product.template/write` with `{"list_price":..,"standard_price":..}` only if changed.
   Qty: `call_kw stock.quant/search_read` domain `[["product_id","=",id],["location_id.usage","=","internal"]]` → take first quant, then `call_kw stock.quant/write` with `{"inventory_quantity": on_hand + received}`. If no quant, `call_kw stock.quant/create` with `{"product_id":id,"location_id": WH/Stock id (fetch once via stock.location),"inventory_quantity":qty}`. Then `call_kw stock.quant/action_apply_inventory` if needed (verify on staging — 18 auto-applies on write in most configs).
5. Save new: `call_kw product.template/create` with `{name, barcode (on variant via product_product? see note), list_price, standard_price, categ_id: default MARKET category id (hardcode after 1 lookup), pos_categ_ids:[[6,0,[posCatId]]], sale_ok:true, purchase_ok:true, available_in_pos:true, type:"consu", is_storable:true}` (Odoo 18: quants are gated on is_storable, not type) then set stock via step 4. Note: Odoo 18 puts `barcode` on `product.product` variant — after template create, `write` barcode on its single variant. Handle 2-step in `OdooClient.createProduct()` so UI calls once.
6. Labels TSV (client-only): header `name\tlist_price\tbarcode\tdefault_code\tcategory`, one row per batch line. Must match `price-labels/gen-label-pngs.js` columns.

Concurrency note: per-scan immediate writes are fine for POC volume. Do NOT add draft/batch/atomic validate now — that's step 1 after MVP.

## 3. Screens + flow

* **Login:** 3 fields (URL locked, DB locked, user, pass) + Sign in + error text. On success → preload pos.categories → go Receive.
* **Receive:** big Scan button + barcode text field (manual fallback) → result card:
  Found: `name, barcode, on-hand, cost, price` + inputs `cost, price, qty(=1)` + Save → toast + clear + focus scan.
  Not found: `barcode (locked), name*, POS category dropdown (=last used), cost, price, qty` + Create → toast + clear.
* **Batch (stretch):** list from Receive `[+ Label]` toggles, copies stepper, Clear, Share button → `share_plus` TSV file.
* Last POS category: `shared_preferences last_pos_categ_id`, set on every successful save.

## 4. Build order (do in this order, demo after each)

1. Scaffold + login + session persist + logout. Demo: kill app, still logged in.
2. Camera scan → barcode string → manual field. Demo in cooler.
3. Lookup + found card (read-only first). Demo 10 real SKUs.
4. Save existing (price + qty). Verify in Odoo backend each time.
5. New-product form + remembered category. Demo: create 2, rescan finds them.
6. Batch + Share TSV → run through `gen-label-pngs.js` on PC. Cut if >4h.
7. Polish: app icon, large 48dp targets, error toasts, Play Internal / sideload APK.

## 5. Test + release

* Devices: 1 mid-range Android + store WiFi. Test: login persist, 20-scan loop, airplane-mode shows error (no crash), duplicate barcode message, TSV imports clean.
* Release: `flutter build apk --release --dart-define API_BASE=https://admin.cloud9market.net` → sideload to 1 store phone. No Play review needed for POC. Staging first if available.
* Do NOT: add offline queue, HID support, packaging/cases, manager PIN, audit model, counts/lottery, iOS, pinning, analytics. Log them in `03`/`04`.

## 6. After MVP ships

Follow `01-MVP.md` § After MVP: barcode index → draft+validate → facade → HID → counts → lottery → iOS. Promote `OdooClient` to repository interface only when step 2 starts.
