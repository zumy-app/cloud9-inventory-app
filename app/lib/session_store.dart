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
    await storage.delete(key: _kUser);
  }

  static Future<int?> loadLastPosCat() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kLastPosCat);
  }

  static Future<void> saveLastPosCat(int id) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLastPosCat, id);
  }

  static const _kInvMode = 'inv_mode'; // 'receive' | 'count'

  static Future<String> loadInvMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kInvMode) ?? 'receive';
  }

  static Future<void> saveInvMode(String mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kInvMode, mode);
  }

  static const _kContinuous = 'continuous_scan';

  static Future<bool> loadContinuous() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kContinuous) ?? false;
  }

  static Future<void> saveContinuous(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kContinuous, v);
  }

  // Local per-product expiry dates (yyyy-MM-dd) captured in Add inventory.
  // Odoo lot-tracked expiry needs lot tracking enabled on the product —
  // P1 follow-up; until then the app keeps the date per variant and shows
  // it in View/Manage.
  static String _expiryKey(int variantId) => 'expiry_$variantId';

  static Future<String?> loadExpiry(int variantId) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_expiryKey(variantId));
  }

  static Future<void> saveExpiry(int variantId, String ymd) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_expiryKey(variantId), ymd);
  }

  // AI suggestions kill-switch. The AI assist is untested: default OFF,
  // and every future AI call site must check loadAiEnabled() first.
  static const _kAiEnabled = 'ai_enabled';

  static Future<bool> loadAiEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAiEnabled) ?? false;
  }

  static Future<void> saveAiEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAiEnabled, v);
  }
}
