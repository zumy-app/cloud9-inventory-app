# 08 — Waste / Loss Tracking v2 (scrap-based, IRS-ready)

Implements the updated plan on `feature/waste-loss-v2`. Read after `07-BLUETOOTH-PRINTER.md`.

## Rule

Disposition date (`disposedAt`, server-validated) is the tax date.
Package expiry is supporting detail only. No quant overwrites for waste —
every loss is a `stock.scrap` move with frozen layer value.

## Files

* `lib/waste_store.dart` — append-only log: `draft → posted → validated → voided`.
  Corrections are reversing entries. `netDeductible` excludes drafts, voided,
  quarantined, donated, vendor-credited. `toLinesCsv` / `toSummaryCsv` for CPA.
* `lib/screens/waste.dart` — scan → lookup → reason/disposition chips →
  expiry pick / No-date → confirm `before → after` → `createScrap` →
  freeze `unitValue`. Offline keeps a draft with `discoveredAt`; no fake `disposedAt`.
* `lib/odoo_client.dart` — `scrapLocationId`, `findLots`, `createScrap`,
  `attachScrapPhoto`. Scrap create + `action_validate` + read-back `value/qty`.
* `lib/screens/inventory_home.dart` — Waste tile (red flow, separate from Count).
* `lib/i18n/lang.dart` — `waste_*`, `home_waste*` in EN/ES (chrome only).
* `test/waste_store_test.dart` — net rules, self-approve block, lock, void chain, CSV freeze.

## Controls

* Clerk logs; manager validates/locks; owner exports. No self-approval.
* `qty > on-hand` allowed (trash already out) but quarantined until validated.
* Monthly lock (`lockMonth`) blocks validate/void in locked `yyyy-MM`.
* Donation / vendor-credit / theft are separate dispositions; donations export
  separately for §170(e)(3), theft is manager-only follow-up (not in Waste tab).

## CPA gates (before calling any export deductible)

1. Inventory method (AVCO/FIFO) + accrual vs cash/263A.
2. Donation intent + donee paperwork.
3. Vendor-credit suppliers + timing.
4. Photo/witness threshold + monthly lock owner.

## Exports

* Lines: `disposed_at,discovered_at,staff,validated_by,barcode,sku,name,
  reason,disposition,qty,unit_value,total_value,package_expiry,
  supplier_invoice,note,scrap_id,status,quarantined,void_chain`
* Summary: `month,lines,units,scrap_value,vendor_credits,donations,
  net_deductible,inventory_method`
* Net = `SUM(total_value) WHERE validated AND NOT quarantined
  AND disposition NOT IN (donated, vendor-credited)`.

## Done

* 20 scraps reduce Odoo on-hand; export total == sum of scrap values;
  cost change after posting does not alter export; void leaves original +
  reversal; airplane-mode cooler test keeps draft with empty `disposedAt`.
