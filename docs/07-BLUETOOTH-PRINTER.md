# 07 — Bluetooth Printer Plan (PM-241Z, Classic SPP)

* Status: Phase 0a done (plugin viable + builds), Phase 1 done
  (SppTransport wired at startup, retry-once, friendly errors),
  Phase 2 done (status chip + printer sheet + darkness, untested on
  hardware). Phase 0b protocol proof STILL OPEN — no successful print
  observed yet (spike ran: BT-off on device; relaunch pending).
* Rule: rely on OS pairing (no in-app discovery scan, no location
  permission). The app connects to a bonded device by MAC.
* Platform: **Android only** (matches the app). Nothing here is
  reusable for iOS; a future iOS port needs its own transport.
* Order matters: Phase 0 → Phase 1 → Phase 2. No UI work starts
  until Phase 0's go/no-go passes.

## 0. Why "Bad state: no printer connected"

1. `PrinterService` ships with `UnconfiguredTransport`
   (`lib/print/printer_service.dart:29`) — `connect`/`write` always
   throw. `useTransport` is never called anywhere.
2. `savePrinter`/`loadSettings`/`forgetPrinter` exist but no UI calls
   them — the "Labels tab" pairing the error message mentions was never
   built. There is no saved address, so every print throws before any
   Bluetooth API is touched.
3. `AndroidManifest.xml` declares no Bluetooth permissions and
   `pubspec.yaml` has no BT plugin. Even a configured address could not
   connect today.

## Phase 0 — compatibility + protocol spike (GO/NO-GO GATE)

Nothing in Phase 1 starts until both checks pass on the Pixel 7 Pro
against the bonded `PM-241Z-BT-C075`.

**0a. Plugin build compatibility.** Candidate: `print_bluetooth_thermal`
(pin version at implementation). Verify it compiles and runs under
Flutter 3.44 + AGP 9.1 + targetSdk 36: embedding v2, `namespace`
present, no native `.so` outside 16 KB page-size support (Play
blocker at targetSdk 36 — pure Kotlin/Java passes trivially, anything
with bundled `.so` must be checked). Confirm the exact API surface at
the spike (expected: paired-device list, `connect(mac)` with timeout,
raw byte write, `disconnect`, connection state, BT-enabled state —
treat names as unconfirmed until seen compiling).
**Fallback, pre-approved:** if the plugin fails any of the above, do
NOT go plugin-shopping. Write a ~100-line Kotlin `MethodChannel`
doing raw RFCOMM/SPP socket I/O (`BluetoothAdapter.bondedDevices`,
`createRfcommSocketToServiceRecord(SPP_UUID)`, streams). Fewer
moving parts than a third-party dependency, and we own the failure
modes.

**0b. Protocol proof.** Send raw TSPL over SPP to the hardcoded bonded
MAC: `SIZE/GAP/CLS` hello, then one Type 01 with logo BITMAP and a
barcode. Photo-verify: bars scan on a handheld, no clipped zones,
knockout bands render (or show their designed fallback). **This is
the go/no-go:** the repo has always *assumed* TSPL for the 241
family, and the unit on hand is the **Z** variant — if it speaks
CPCL/vendor-protocol only, stop here and replan the composer
(`tspl.dart`) before touching UI.

## Phase 1 — transport + permissions (no UI except errors)

New `SppTransport implements PrinterTransport`
(`lib/print/spp_transport.dart`, ~120 lines):

* `connect(address)`: `BLUETOOTH_CONNECT` granted? → BT enabled? →
  connect with a 10s timeout. Map transport errors to the message
  table in §6 (raw plugin/socket strings never reach UI).
* `write(bytes)`: **single write by default.** Chunk (with sizes from
  experiment, not prescription) only if the Phase-0 BITMAP shows
  dropped bytes. Single-flight queue in `PrinterService` stays
  unchanged.
* Lifecycle: **connect on demand, stay connected, revalidate per
  batch.** Phomemos sleep and Android Dozes idle SPP sockets, so a
  blindly persistent socket goes stale. Design: before each
  `printLabels` batch, if not connected, connect; on write failure,
  one reconnect + retry of that label once, then fail the job into
  the existing per-label failed/retry rows (`print_job.dart:36`).
  `disconnect` on `forgetPrinter` and on unrecoverable errors only.
  (Rationale: per-job connect/disconnect would add 2–5s of SPP
  handshake to every label.)
* `status` stream: forward connection states into the existing
  `PrinterStatus` enum (no UI contract change).
* Wiring (pinned): `Cloud9App` startup calls `loadSettings()` then
  `useTransport(SppTransport())` exactly once, so address +
  transport exist before any tab can print. All existing print call
  sites keep working unchanged.

Manifest (no location permission by design):

```xml
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
```

* No `BLUETOOTH_SCAN`, no `ACCESS_FINE_LOCATION`: the app only talks
  to devices the user already bonded in Settings. This halves the
  permission UX and the Play review surface.
* Pre-31 devices fall back to the legacy flags (maxSdkVersion keeps
  them off 31+). minSdk stays as-is; all CONNECT-gated calls go
  through `permission_handler` status checks first. Needs
  compileSdk 31+ (already true on Flutter 3.44 defaults — confirm at
  implementation).

## Phase 2 — printer management UI (Labels tab)

* **Status chip** in the Labels AppBar (reuses `PrinterStatus`):
  `No printer` (grey) / `Connecting…` / `Ready · C075` (short
  suffix of the bonded name, **falling back to masked MAC
  `…:C0:75`** — the user can rename the device in Settings, the MAC
  we persist is stable) / `Error` (red, tap → message).
* **Printer sheet** (new, from the chip + the existing printer
  icon that currently dead-ends):
  1. BT-off state → "Turn on Bluetooth" button (system intent).
  2. Permission states → rationale → request → "denied" links to
     App settings (`permission_handler.openAppSettings`).
  3. Bonded list: `name` + masked MAC, tap → save address →
     connect → **test print: a tiny alignment ticket** (printer
     name, MAC suffix, 3 bars — not a full Type 01; don't burn
     stock/ribbon per tap) → success toast.
  4. Footer: darkness stepper (wires the existing `darkness`
     setting, which also has no UI today) + Forget button.
* All strings go through `lang.dart` en+es (badge rule from `06`
  does not apply here — this is app UI, not printed output).
* MAC is the persisted identity (stable across unpair/re-pair);
  display name is display-only.

## 6. Failure → message table (no raw exceptions in UI)

| Condition | Message |
|---|---|
| No saved printer | Existing "Pair a label printer first" + deep-link to the sheet |
| BT off | "Bluetooth is off — turn it on to print" + enable button |
| CONNECT denied | "Nearby-devices permission needed for printing" + settings link |
| Saved MAC not bonded anymore | "PM-241Z not found — pair it in Settings, then reselect" |
| Connect timeout / printer off / stale socket after 1 retry | "Couldn't reach the printer — check power and range" |
| Write fails mid-job | Per-label failed/retry rows (already routed) |

## 7. Test plan (Pixel 7 Pro + PM-241Z-BT-C075)

1. Phase-0 gates (§Phase 0): plugin-or-channel builds clean on
   targetSdk 36; photo-verify passes (bars scan, zones intact).
2. Feature: fresh install → status chip → sheet → select → ticket
   print → kill app → relaunch (address persists, reconnects).
3. Matrix: BT off, permission denied-then-granted, printer powered
   off, out of range, sleep-then-print (stale socket path),
   5-copy job, 10-label rapid batch, paper-out recovery
   (fire-and-forget: no status readback — document, don't build).
4. `flutter analyze`, `flutter test` (new: transport error mapping
   with a fake transport, reconnect-then-fail path, prefs
   round-trip, sheet permission states).
5. Play: Data-Safety declare `BLUETOOTH_CONNECT` ("connects to the
   store label printer"); nearby-devices rationale at upload.

## 8. Rollout + non-goals

* Bump `+8` → `+9`, release APK to both test devices, print one
  real shelf tag in-store.
* Update `05-LABEL-PRINTING.md` status (close Phase 0/1 for Classic)
  when the photo-verify lands — don't leave the trail cold.
* NOT building: BLE GATT, in-app discovery/pairing, iOS, printer
  status readback (paper/heat), multi-printer profiles, Wi-Fi
  printing.
