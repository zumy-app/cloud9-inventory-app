// Inventory home + tabs (Inventory | Labels | Account).
library;

import 'package:flutter/material.dart';

import 'batch_store.dart';
import 'odoo_client.dart';
import 'screens/batch.dart';
import 'screens/inventory_home.dart';
import 'screens/login.dart';
import 'session_store.dart';

/// Brand palette sampled from the Cloud 9 Kitchen & Market oval:
/// orange field, white lettering, near-black outline.
const _brandOrange = Color(0xFFF26522);
const _brandInk = Color(0xFF141414);

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

  late final OdooClient _client = OdooClient(baseUrl: _baseUrl);
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
      final s = await SessionStore.loadSession();
      if (s != null) {
        _client.setSessionCookie(s.cookie);
        _user = s.user;
        _loggedIn = true;
      }
    } catch (_) {
      // Secure storage unavailable (e.g. widget test) -> stay logged out.
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
    return MaterialApp(
      title: 'Cloud 9 Inventory',
      theme: _brandTheme(),
      home: !_ready
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()))
          : !_loggedIn
              ? LoginScreen(client: _client, onLoggedIn: _onLoggedIn)
              : Scaffold(
                  body: IndexedStack(
                    index: _tab,
                    children: [
                      InventoryHome(client: _client, user: _user),
                      const BatchScreen(),
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
                    destinations: const [
                      NavigationDestination(
                          icon: Icon(Icons.inventory_2),
                          label: 'Inventory'),
                      NavigationDestination(
                          icon: Icon(Icons.label), label: 'Labels'),
                      NavigationDestination(
                          icon: Icon(Icons.person), label: 'Account'),
                    ],
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
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(baseUrl, style: const TextStyle(color: Colors.grey)),
          const Text('DB: odoo',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Text('User: ${user.isEmpty ? '—' : user}',
              style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: () async {
                await onLogout();
              },
              child: const Text('Sign out'),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'POC build. Online-only. Mistakes: fix in Odoo backend.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
