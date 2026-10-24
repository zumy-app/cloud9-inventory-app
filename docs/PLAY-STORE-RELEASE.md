# Play Store release — Cloud 9 Team

Production build to submit for Google Play review.

## Build

- App ID: `app.zumy.cloud9.employee`
- Version: `1.0.1` (versionCode `9`)
- Min SDK: 24
- Target SDK: 36 (meets the Aug 31, 2026 Android 16 requirement)
- Signing: upload key (`android/key.properties` + `android/cloud9-upload.keystore`)
- Artifact: `app/build/app/outputs/bundle/release/app-release.aab`

```powershell
cd app
flutter analyze
flutter test
flutter build appbundle --release
flutter build apk --release   # only for sideload testing
```

Upload the `.aab`, never the APK, to Play Console.

Verified on this build:

- `aapt dump badging`: `app.zumy.cloud9.employee`, versionCode `9`,
  versionName `1.0.1`, minSdk 24, targetSdk 36, native code
  `arm64-v8a`, `armeabi-v7a`, `x86_64`.
- `apksigner verify --print-certs`: signed by
  `CN=Cloud 9 Market, OU=Store Apps, O=Cloud 9 Market, C=US`.
- `zipalign -c -P 16`: verification successful (16 KB page alignment).
- `jarsigner -verify`: AAB signed; certificate valid until 2054-02-19.
- `flutter analyze`: no issues; `flutter test`: 97 tests passed.
- AAB SHA-256:
  `AC0B3CDFD5B5511C857FE989ACA872A1E870E217B7A6B0C785F2E0D4B2DDC498`
- APK SHA-256:
  `5C761EB29867D60A2692969BE219813A6031AC4837E5A1DDC5441CBCB2649554`

## Policy fixes already applied

- Version bumped to `1.0.1+9` (new versionCode for the upload).
- `android:allowBackup="false"` and `fullBackupContent="false"` so session
  credentials are not backed up.
- `android:usesCleartextTraffic="false"`; the app talks HTTPS only.
- Bluetooth hardware declared optional; the printer is optional and the app
  remains installable on devices without Bluetooth.
- In-app Privacy policy screen and a hosted policy file
  (`store/privacy-policy.html`).
- Account tab now shows the real version, privacy link, account-management /
  deletion instructions, and no longer says "POC build".
- Bluetooth `BLUETOOTH_SCAN` keeps `neverForLocation`; no location permission.
- Camera is used only for barcode scanning and is declared optional.

## Before you can submit (owner inputs)

1. **Host the privacy policy.** Upload `store/privacy-policy.html` to a public
   HTTPS URL (for example `https://admin.cloud9market.net/privacy`) and paste
   that URL in Play Console → App content → Privacy policy.
2. **Provide a reviewer test account.** The whole app is behind the Odoo login.
   In Play Console → App content → App access, add the test username/password
   and instructions: sign in, open Labels, optionally open the printer sheet.
   Reviewers cannot get past the login without this.
3. **New developer account?** Personal accounts created after Nov 13, 2023 must
   run a closed test with at least 12 testers for 14 continuous days before
   production access. Use Internal testing first, then Closed testing if needed.
4. **Confirm the support contact** used in the store listing and privacy policy
   (the current policy points to the Play listing contact).

## Play Console — App content

### App access
- All functionality requires login: **Yes**.
- Provide the test account and the steps above.

### Ads
- **No ads.**

### Content rating
- Category: Business / Utility.
- No violence, sex, profanity, drugs, gambling, user-generated content,
  purchases, or unrestricted web access.
- Expected rating: Everyone / PEGI 3.

### Target audience
- **18 and over** (workforce app). Do not opt into the Families program.

### News app
- **No.**

### Data safety
Declare:

| Data type | Collected | Shared | Optional | Purpose |
| --- | --- | --- | --- | --- |
| Personal info → User IDs (Odoo login) | Yes | No | No | Account management, app functionality |
| Personal info → Other info (account credentials) | Yes | No | No | Account management |
| App activity → Other actions (inventory edits/counts) | Yes | No | No | App functionality |

- Encrypted in transit: **Yes** (HTTPS).
- Users can request deletion: **Yes** — contact the store administrator (see
  privacy policy).
- No data sold.
- No advertising or analytics SDKs.
- Camera frames are processed on-device and are not collected; do not declare
  Photos/Videos.
- No location, contacts, messages, health, financial, or web-browsing data.

If Play Console asks about the ML Kit barcode scanner, it runs on-device and
the app does not store or transmit camera frames.

### Permissions
- `CAMERA` — barcode scanning only, requested at first scan.
- `BLUETOOTH_CONNECT` / `BLUETOOTH_SCAN` — connect to an already-paired label
  printer. `BLUETOOTH_SCAN` is marked `neverForLocation`; no location access.
- `BLUETOOTH` / `BLUETOOTH_ADMIN` — legacy Android 11 and lower only.
- `INTERNET` — Odoo API over HTTPS.

## Store listing

See `app/store/listing.md` for title, short/full description, and contact copy.

Assets:
- `app/store/icon_512.png` — 512×512 app icon
- `app/store/feature_graphic.png` — 1024×500 feature graphic
- `app/store/screenshots/` — phone screenshots (at least 2)

**Refresh required:** `app/store/screenshots/02-labels.png` was captured before
the duplicate Labels FAB was removed. Recapture it from build 9 so the
“Print all labels” button is not covered. The other two screenshots are current.

## Testing track recommendation

1. Internal testing → install on the two store phones, verify login, scanning,
   label printing, Spanish/English.
2. Closed testing → 12+ testers for 14 days if the developer account is new.
3. Production → upload the same `.aab`, complete the rollout.

## Signing notes

- Keep `android/cloud9-upload.keystore` and `android/key.properties` backed up
  outside the repo. They are git-ignored.
- Enroll in Play App Signing so Google holds the app signing key; the local
  keystore is the upload key.
- If the upload key is lost, request a reset in Play Console before uploading.
