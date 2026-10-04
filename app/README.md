# Cloud 9 Inventory App (MVP POC)

Android-only, online-only receiving + label batch. See `../docs/01-MVP.md` (scope) and `../docs/02-MVP-TECH-PLAN.md` (contract).

## Run

```bash
cd app
flutter pub get
flutter run --dart-define API_BASE=https://admin.cloud9market.net
```

Release APK for sideload:

```bash
flutter build apk --release --dart-define API_BASE=https://admin.cloud9market.net
```

## Test

```bash
flutter analyze
flutter test
```

## Files

* `lib/main.dart` — login gate + tabs (Receive | Labels | Account)
* `lib/odoo_client.dart` — stock JSON-RPC: authenticate, lookup, prices, quant, create
* `lib/session_store.dart` — session cookie (secure) + last POS category (prefs)
* `lib/batch_store.dart` — in-memory label batch + TSV export
* `lib/screens/login.dart|receive.dart|scan.dart|batch.dart`
