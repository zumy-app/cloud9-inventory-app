# 10 — Native POS Checkout (no WebView login)

Replaces the WebView POS (which asked for a second login — the session
cookie never reliably transferred into the WebView jar) with a cashier-first
native checkout on `feature/native-pos`. Read after `09`.

## Flow

Register → scan/search → cart → tender → paid receipt.

* `lib/screens/pos_checkout.dart` — register dropdown + open-session chip,
  search + Scan, horizontal product cards (exact barcode scans go straight
  in the cart), cart with +/− steppers, live subtotal / tax-est / total,
  payment-method chips, tendered + Exact shortcut, big green Charge button
  with `total → tendered → change` confirm, success receipt card + New sale.
* Entry: Odoo hub **POS checkout** tile now opens the native screen
  (backend WebView kept as-is for back-office browsing).

## Odoo mapping (standard models only, no custom module)

* `pos.config` (active) → registers.
* `pos.session` (`opened`/`opening_control`, newest) → selling session.
  No open session = locked Charge button with "open the register first".
* `product.product` (`sale_ok`, name/barcode search) → catalog with
  `list_price`, `taxes_id`, `qty_available`.
* `account.tax` → local tax estimate (included vs excluded aware; unknown
  taxes count 0% — server total stays authoritative).
* `pos.payment.method` (cash/bank tolerant to missing fields) → tender.
* Sale = `pos.order` create (session + lines with `tax_ids`) →
  `pos.payment` create per tender → `action_pos_order_paid` →
  read `pos_reference` + `amount_total` for the receipt.
* Any step can fail loudly: drafts stay payable/voidable at the register,
  messages name the order id. Nothing is ever silently half-posted.

## Tests

* `test/pos_checkout_test.dart` — cart math (included/excluded/mixed/
  unknown taxes), register/session/catalog/tax/method RPC shapes, closed
  register → null session, full checkout sequence, payment-failure →
  DRAFT message naming the order.

## Done

* `flutter analyze` clean, 126/126 tests pass.
* Charge button enables only with open session + non-empty cart + tendered
  ≥ total; receipt shows server reference + server total + change.

## First live sale (supervised)

Ring a real item with cash tender, then confirm in Odoo: POS order Paid,
correct totals/taxes, stock decremented, payment journal entry present.
