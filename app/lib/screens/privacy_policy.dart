import 'package:flutter/material.dart';

/// In-app copy of the privacy policy referenced by the Play listing.
/// Keep this in sync with store/privacy-policy.html.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _updated = 'Last updated: October 24, 2026';

  static const _sections = <(String, String)>[
    (
      'Who we are',
      'Cloud 9 Team is provided by Cloud 9 Market for authorized staff. '
          'This policy explains what the app does with information when you '
          'use it to manage inventory, print shelf labels, record attendance, '
          'and check out customers.',
    ),
    (
      'Information we process',
      'Account: your Odoo username and password are used to sign in. They are '
          'stored in the device secure storage and sent over HTTPS to the '
          'Cloud 9 Odoo server at admin.cloud9market.net. The password is '
          'never written to logs.\n\n'
          'Inventory: barcodes, product names, quantities, prices, expiry '
          'dates, categories and notes that you scan or enter are sent to the '
          'Cloud 9 Odoo server so the store inventory stays up to date.\n\n'
          'Attendance: when you clock in or out, the check-in/out time and '
          'your employee record are stored in the Cloud 9 Odoo server.\n\n'
          'Device settings: the selected Bluetooth printer address, print '
          'darkness, language preference, recent category choices, and the '
          'calibrated store location are stored locally on the device.',
    ),
    (
      'Location',
      'Location is used for one purpose only: to confirm you are at the store '
          'when you clock in or out. Your position is checked on the device '
          'against the calibrated store geofence at the moment you tap the '
          'clock button. The app does not track your location in the '
          'background, does not store a history of your movements, and does '
          'not send raw coordinates to the server.',
    ),
    (
      'Camera',
      'The camera is used only to scan product barcodes. Frames are processed '
          'on the device by the barcode scanner and are not stored or sent to '
          'us. The app does not access photos or files.',
    ),
    (
      'Bluetooth',
      'Bluetooth is used only to connect to a label printer that you have '
          'already paired in Android settings. The app does not scan for '
          'nearby devices and does not use Bluetooth to determine location.',
    ),
    (
      'How we use information',
      'We use the information to sign you in, load and update inventory, '
          'print labels, remember your settings, provide support, and protect '
          'the service. We do not use it for advertising.',
    ),
    (
      'Sharing',
      'We do not sell your information. Inventory and account data are stored '
          'in Cloud 9 Market\'s Odoo system and may be handled by service '
          'providers that host or support that system. We may disclose '
          'information when required by law or to protect the service. The app '
          'has no advertising, analytics or crash-reporting SDKs. If you use '
          'Share TSV, the export is handed to the app you choose and that app\'s '
          'privacy policy applies.',
    ),
    (
      'Retention and deletion',
      'Account and inventory records are kept according to Cloud 9 Market '
          'policy. Local settings and cached session data are removed when you '
          'sign out or uninstall the app. Accounts are created and managed by '
          'Cloud 9 Market. To request deletion of your account or a copy of '
          'your data, contact your store administrator or the support contact '
          'shown on the Google Play listing.',
    ),
    (
      'Security',
      'Data is sent over HTTPS. Sign-in credentials are kept in the Android '
          'secure storage. Access to the Odoo server is limited to authorized '
          'accounts.',
    ),
    (
      'Children',
      'This is a workforce app and is not directed to children. We do not '
          'knowingly collect information from children.',
    ),
    (
      'Changes',
      'If this policy changes, we will update the date above and publish the '
          'new version at the privacy policy link in the Google Play listing.',
    ),
    (
      'Contact',
      'For privacy questions, contact your Cloud 9 Market administrator or '
          'the support contact shown on the Google Play listing.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            'Cloud 9 Team',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(_updated, style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          for (final (heading, body) in _sections) ...[
            Text(
              heading,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(body, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}
