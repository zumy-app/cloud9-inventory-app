# Cloud 9 Inventory App — docs

Read in order. Start at 01, build 02, defer 03–04 until MVP is in the store.

* `01-MVP.md` — POC scope. 3 screens, Android-only, zero Odoo changes. Source of truth for what to build now.
* `02-MVP-TECH-PLAN.md` — how to build 01. Exact Odoo calls, files, build order, test + sideload. Start here when coding.
* `03-FULL-REQUIREMENTS-post-MVP.md` — full v1 requirements (receiving sessions, labels, counts, lottery). Do NOT build yet.
* `04-TECH-STRATEGY-V2-future.md` — post-MVP architecture (facade API, draft+validate, HID, iOS). Do NOT build yet.
* `05-LABEL-PRINTING.md` — Bluetooth printing on Phomemo PM-241-BT (status + phases).
* `06-TYPE01-LABEL-REDESIGN.md` — Type 01 retail-label redesign tech plan (approved mockup: `labels-wireframes/type01-mockup.html`). Build this now.
* `07-BLUETOOTH-PRINTER.md` — Bluetooth printer plan (PM-241Z over Classic SPP): why the app can't see the OS-paired printer, transport, permissions, management UI, test plan.
* `08-WASTE-LOSS-TRACKING-v2.md` — Waste/loss tracking (scrap-based, IRS-ready): append-only log, disposition-date tax rule, validation/lock, CSV exports. Build on `feature/waste-loss-v2`.
* `09-ATTENDANCE-POS.md` — GPS-gated clock in/out + hours and in-app Odoo apps / POS checkout. Build on `feature/attendance-pos`.
* `10-NATIVE-POS.md` — Native POS checkout (no WebView login): register → scan/search → cart → tender → paid receipt. Build on `feature/native-pos`.
