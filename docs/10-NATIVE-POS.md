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
* `pos.payment.method` (cash/bank tolerant to missing fields,
  `use_payment_terminal` flags terminal methods) → tender.
* **Sale = `pos.order/create_from_ui` with a complete frontend-style dict**
  (`session_id`, `uuid`, lines with `tax_ids`/`price_subtotal`, `payment_ids`,
  `amount_total`/`amount_tax`/`amount_paid`/`amount_return`).
  This is the exact path web POS uses daily, so custom required fields
  (e.g. a required `amount_tax` on prod) are satisfied like prod. Single
  call, fresh uuid per attempt — a retry can never double-charge; an
  unconfirmed response throws instead of guessing an order id. Optional
  `draft: true` creates a backend draft for terminal-first flows.
* Draft state after sync falls back to `action_pos_order_paid`; failures
  name the order id for register-side pay/void. Error dialogs show the
  FULL server text with a Copy button.
* **Helcim Smart Terminal (optional, per device):** gear icon → device
  code + currency + API token (secure storage). Charge pushes the total
  to the physical terminal (`POST /v2/devices/{code}/payment/purchase`),
  cashier confirms approval on the device, app records the payment in
  Odoo. Card data never touches the phone. Unconfigured → manual
  record-after-charge flow with terminal warning.

## Tests

* `test/pos_checkout_test.dart` — cart math (included/excluded/mixed/
  unknown taxes), register/session/catalog/tax/method RPC shapes, closed
  register → null session, full `create_from_ui` dict (asserts `amount_tax`,
  `payment_ids`, `session_id`, `uuid` travel), draft fallback,
  unconfirmed-response guard, terminal-method flag, full server error text.
* `test/helcim_test.dart` — push URL/header/payload, 403/404/409/500
  mapping, no-config no-call guard.

## Done

* `flutter analyze` clean, 132/132 tests pass.
* Charge button enables only with open session + non-empty cart + tendered
  ≥ total; receipt shows server reference + server total + change.

## First live sale (supervised)

Ring a real item with cash tender, then confirm in Odoo: POS order Paid,
correct totals/taxes, stock decremented, payment journal entry present.
