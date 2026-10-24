// Inventory home + tabs (Inventory | Labels | Account).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'batch_store.dart';
import 'i18n/lang.dart';
import 'odoo_client.dart';
import 'print/printer_service.dart';
import 'print/spp_transport.dart';
import 'screens/batch.dart';
import 'screens/inventory_home.dart';
import 'screens/login.dart';
import 'screens/privacy_policy.dart';
import 'session_store.dart';
import 'widgets/lang_switch.dart';

/// Brand palette sampled from the Cloud 9 Team oval:
/// orange field, white lettering, near-black outline.
const _brandOrange = Color(0xFFF26522);
const _brandInk = Color(0xFF141414);

/// Keep in sync with pubspec.yaml (shown on the Account tab).
const _appVersion = '1.0.1';

ThemeData _brandTheme() {
  const scheme = ColorScheme.light(
    primary: _brandOrange,
    onPrimary: Colors.white,
    secondary: _brandInk,
    onSecondary: Colors.white,
    surface: Colors.white,
    onSurface: _brandInk,
    surfaceContainerHighest: Color(0xFFFFEDE3),
    error: Color(0xFFB3261E),
  );
  WidgetStateProperty<Color?> selectedWhite(Color unselected) =>
      WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : unselected);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: _brandInk,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _brandOrange,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: _brandInk),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: _brandOrange),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _brandOrange,
      foregroundColor: Colors.white,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: selectedWhite(Colors.grey),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? _brandOrange : Colors.black12),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: _brandOrange,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? Colors.white
              : _brandInk)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          color: s.contains(WidgetState.selected) ? _brandInk : Colors.grey,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.bold
              : FontWeight.normal)),
    ),
  );
}

void main() {
  runApp(const Cloud9App());
}

class Cloud9App extends StatefulWidget {
  const Cloud9App({super.key});

  @override
  State<Cloud9App> createState() => _Cloud9AppState();
}

class _Cloud9AppState extends State<Cloud9App> {
  static const _baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://admin.cloud9market.net',
  );

  late final OdooClient _client = OdooClient(baseUrl: _baseUrl)
    ..credentialsProvider = SessionStore.loadCredentials
    ..onSessionRefreshed = ((cookie) async {
      final s = await SessionStore.loadSession();
      await SessionStore.saveSession(cookie, s?.user ?? '');
    });
  bool _ready = false;
  bool _loggedIn = false;
  String _user = '';
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      await Lang.instance.load();
    } catch (_) {
      // Prefs unavailable (e.g. widget test) -> default English.
    }
    try {
      final s = await SessionStore.loadSession();
      if (s != null) {
        _client.setSessionCookie(s.cookie);
        _user = s.user;
        _loggedIn = true;
      }
    } catch (_) {
      // Secure storage unavailable (e.g. widget test) -> stay logged out.
    }
    try {
      // Real Bluetooth transport + saved printer address before any tab
      // can print. loadSettings is time-bounded and never throws, so a
      // printer problem can never block boot (printer is optional; the
      // error surfaces when printing instead).
      PrinterService.instance.useTransport(SppTransport());
      await PrinterService.instance.loadSettings();
    } catch (_) {
      // Belt and suspenders; see loadSettings.
    }
    if (mounted) setState(() => _ready = true);
  }

  void _onLoggedIn() {
    setState(() {
      _loggedIn = true;
      _tab = 0;
    });
    SessionStore.loadSession().then((s) {
      if (mounted && s != null) setState(() => _user = s.user);
    });
  }

  Future<void> _logout() async {
    await SessionStore.clear();
    _client.logout();
    BatchStore.instance.clear();
    setState(() {
      _loggedIn = false;
      _tab = 0;
      _user = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Lang.instance,
      builder: (context, child) => MaterialApp(
        title: 'Cloud 9 Team',
        theme: _brandTheme(),
        locale: Lang.instance.current == AppLang.es
            ? const Locale('es')
            : const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: !_ready
            ? const Scaffold(
                body: Center(child: CircularProgressIndicator()))
            : !_loggedIn
                ? LoginScreen(client: _client, onLoggedIn: _onLoggedIn)
                : Scaffold(
                    body: IndexedStack(
                      index: _tab,
                      children: [
                        InventoryHome(
                            client: _client,
                            user: _user,
                            sessionCookie: _client.sessionCookie ?? ''),
                        BatchScreen(client: _client, user: _user),
                        _AccountTab(
                            user: _user,
                            baseUrl: _baseUrl,
                            onLogout: _logout),
                      ],
                    ),
                    bottomNavigationBar: NavigationBar(
                      selectedIndex: _tab,
                      onDestinationSelected: (i) =>
                          setState(() => _tab = i),
                      destinations: [
                        NavigationDestination(
                            icon: const Icon(Icons.inventory_2),
                            label: t('nav_inventory')),
                        NavigationDestination(
                            icon: const Icon(Icons.label),
                            label: t('nav_labels')),
                        NavigationDestination(
                            icon: const Icon(Icons.person),
                            label: t('nav_account')),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _AccountTab extends StatelessWidget {
  final String user;
  final String baseUrl;
  final Future<void> Function() onLogout;
  const _AccountTab(
      {required this.user, required this.baseUrl, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('account_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(baseUrl, style: const TextStyle(color: Colors.grey)),
          Text(t('account_db'),
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Text(
              user.isEmpty
                  ? t('account_user_none')
                  : Lang.instance.f('account_user', {'user': user}),
              style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          Text(t('account_language'),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const LangSwitch(),
          const SizedBox(height: 4),
          Text(t('account_language_note'),
              style: const TextStyle(color: Colors.grey)),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(t('account_privacy')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PrivacyPolicyScreen(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            Lang.instance.f('account_version', {'version': _appVersion}),
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            t('account_managed_note'),
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: () async {
                await onLogout();
              },
              child: Text(t('account_signout')),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t('account_note'),
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
