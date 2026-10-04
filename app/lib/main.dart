// MVP entry: login gate + tabs Receive | Labels | Account.
library;

import 'package:flutter/material.dart';

import 'batch_store.dart';
import 'odoo_client.dart';
import 'screens/batch.dart';
import 'screens/login.dart';
import 'screens/receive.dart';
import 'session_store.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: !_ready
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()))
          : !_loggedIn
              ? LoginScreen(client: _client, onLoggedIn: _onLoggedIn)
              : Scaffold(
                  body: IndexedStack(
                    index: _tab,
                    children: [
                      ReceiveScreen(client: _client),
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
                          label: 'Receive'),
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
