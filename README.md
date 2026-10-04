# Cloud 9 Market — Inventory Management Mobile App

Scanner-first mobile app for Cloud 9 Market staff, integrated with prod Odoo
(`admin.cloud9market.net`).

## Docs (read in order)

* `docs/README.md` — index
* `docs/01-MVP.md` — POC scope: build this now
* `docs/02-MVP-TECH-PLAN.md` — how to build the MVP
* `docs/03-FULL-REQUIREMENTS-post-MVP.md` — full v1, deferred
* `docs/04-TECH-STRATEGY-V2-future.md` — post-MVP architecture, deferred

## Related repos / folders

* `../cloud9market/` — Odoo 18 deployment + custom modules
* `../cloud9market/CONVENIENCE_STORE_CATEGORY_SCHEMA.md` — POS categories
* `../price-labels/` — 2"x1" Phomemo PM-241-BT label generator (`gen-label-pngs.js`, `print-labels.ps1`)
* `../cloud9-print-agent/` — kitchen ticket print agent (polling pattern)

## Status

MVP POC implemented in `app/` (Flutter, Android-only).
`flutter analyze` clean, `flutter test` passes.
Next: `flutter run` on a store phone and verify against Odoo backend.
