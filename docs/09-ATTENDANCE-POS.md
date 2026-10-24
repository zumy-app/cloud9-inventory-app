# 09 — Attendance (GPS-gated) + Odoo Apps / POS Checkout

Implements clock in/out with a store geofence and in-app Odoo access
(POS register + backend) on `feature/attendance-pos`. Read after `08`.

## Rule

Clock buttons enable ONLY inside the calibrated store geofence. No GPS fix,
no store calibration, or outside the radius → locked with a reason. Failed
server writes never fake success (verified re-reads).

## Attendance

* `lib/attendance_store.dart` — pure geofence math (`haversineMeters`,
  `geofenceVerdict`), store calibration persistence (`SharedPreferences`),
  radius 50–1000m (default 150m), `fmtHours`.
* `lib/screens/attendance.dart` — status card, live GPS, Clock in/out
  (green/red, 56px), gate hint + retry, hours today/week/shifts, store card
  (Set store location here + radius), recent-shifts history.
* `lib/odoo_client.dart` — `myEmployee` (uid via
  `/web/session/get_session_info` → `hr.employee.user_id`),
  `openAttendance`, `clockIn`, `clockOut`, `attendanceHistory`,
  `AttendanceRecord.hours()` (naive Odoo timestamps parsed as UTC).
* Graceful without the Attendance app: `ATTENDANCE_UNAVAILABLE` /
  `ATTENDANCE_NO_EMPLOYEE` with setup instructions, never a crash.
* No custom Odoo module. Requires: Attendance app installed + employee
  linked to the Odoo user (HR → employee → Linked User).

## Store calibration (no hardcoded coords)

A manager stands in the store → Attendance → **Set store location here** →
confirm. Radius adjustable (100/150/250/500m). Survives restarts.

## Odoo hub + POS checkout

* `lib/screens/odoo_hub.dart` — hub with **POS checkout** (`/pos/web`) and
  **Odoo backend** (`/web`). Session cookie injected into the WebView jar:
  same login, no second sign-in.
* **Scan to POS** FAB: phone camera scans a barcode, JS types it into the
  focused POS field + Enter. If POS has no field focused, a hint toast
  asks to tap the search line first.
* POS needs an open POS session (started on the register or backend).
  WebView camera scanning inside Odoo POS web is best-effort; the native
  scan button is the reliable path.
* Tiles added to Inventory home: Clock in/out, Checkout & Odoo apps.

## Permissions & privacy

* `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION` (runtime, Attendance
  screen only — position checked on-device at tap time, no background
  tracking, no stored movement history, no raw coords to server).
* `store/privacy-policy.html` + in-app policy updated (Location section,
  Oct 24 2026). Re-host the HTML and bump Play Data Safety (location:
  approximate, app functionality, not shared).

## Tests

* `test/attendance_store_test.dart` — haversine, verdict
  (unset/no-gps/outside/inside), hours format, radius clamp, RPC shapes
  (employee/open/clock in-out/history), unavailable mapping, TZ-correct
  open-shift hours.

## Done

* `flutter analyze` clean, full suite passes.
* Outside geofence → buttons locked with reason; inside → clock posts
  `hr.attendance` and history/hours update.
* POS opens logged in; scan button types codes into POS search.
