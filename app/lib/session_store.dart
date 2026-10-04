// Session + settings persistence for the MVP.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  static const _kCookie = 'odoo_session_cookie';
  static const _kUser = 'odoo_user';
  static const _kLastPosCat = 'last_pos_categ_id';

  static const storage = FlutterSecureStorage();

  static Future<void> saveSession(String cookie, String user) async {
    await storage.write(key: _kCookie, value: cookie);
    await storage.write(key: _kUser, value: user);
  }

  static Future<({String cookie, String user})?> loadSession() async {
    try {
      final c = await storage.read(key: _kCookie).timeout(
            const Duration(seconds: 3),
            onTimeout: () => null,
          );
      final u = await storage.read(key: _kUser).timeout(
            const Duration(seconds: 3),
            onTimeout: () => null,
          );
      if (c == null || c.isEmpty) return null;
      return (cookie: c, user: u ?? '');
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    await storage.delete(key: _kCookie);
  }

  static Future<int?> loadLastPosCat() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kLastPosCat);
  }

  static Future<void> saveLastPosCat(int id) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLastPosCat, id);
  }
}
