// Login screen: fixed URL + DB, username + password.
library;

import 'package:flutter/material.dart';

import '../odoo_client.dart';
import '../session_store.dart';

class LoginScreen extends StatefulWidget {
  final OdooClient client;
  final void Function() onLoggedIn;
  const LoginScreen({super.key, required this.client, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _err;
  bool _obscure = true;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.client.authenticate(
        db: 'odoo',
        login: _user.text.trim(),
        password: _pass.text,
      );
      final cookie = widget.client.sessionCookie;
      if (cookie == null) throw OdooException('No session cookie');
      await SessionStore.saveSession(cookie, _user.text.trim());
      widget.onLoggedIn();
    } on OdooException catch (e) {
      setState(() => _err = e.message);
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud 9 Inventory')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('https://admin.cloud9market.net',
                  style: TextStyle(color: Colors.grey)),
              const Text('DB: odoo', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: _user,
                decoration: const InputDecoration(
                    labelText: 'Username', border: OutlineInputBorder()),
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _login(),
              ),
              if (_err != null) ...[
                const SizedBox(height: 12),
                Text(_err!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Sign in', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
