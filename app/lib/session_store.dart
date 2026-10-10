// Session + settings persistence for the MVP.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  static const _kCookie = 'odoo_session_cookie';
  static const _kUser = 'odoo_user';
  static const _kPass = 'odoo_password';
  static const _kDb = 'odoo_db';
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
    await storage.delete(key: _kPass);
    await storage.delete(key: _kDb);
  }

  static const _kLang = 'app_lang'; // 'en' | 'es', null = follow device

  /// UI language override (per device, survives logout — kept in
  /// SharedPreferences, not secure storage, by design).
  static Future<void> saveLang(String lang) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLang, lang);
  }

  static Future<String?> loadLang() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kLang);
    return (v == 'es' || v == 'en') ? v : null;
  }

  /// Credentials for transparent session refresh (same secure storage as
  /// the session cookie). Enables one automatic re-login + retry on 401 so
  /// an expired mid-shift session never wipes an in-progress form.
  static Future<void> saveCredentials({
    required String db,
    required String login,
    required String password,
  }) async {
    await storage.write(key: _kDb, value: db);
    await storage.write(key: _kUser, value: login);
    await storage.write(key: _kPass, value: password);
  }

  static Future<({String db, String login, String password})?>
      loadCredentials() async {
    try {
      final db = await storage.read(key: _kDb).timeout(
            const Duration(seconds: 3),
            onTimeout: () => null,
          );
      final u = await storage.read(key: _kUser).timeout(
            const Duration(seconds: 3),
            onTimeout: () => null,
          );
      final p = await storage.read(key: _kPass).timeout(
            const Duration(seconds: 3),
            onTimeout: () => null,
          );
      if (u == null || u.isEmpty || p == null || p.isEmpty) return null;
      return (
        db: (db == null || db.isEmpty) ? 'odoo' : db,
        login: u,
        password: p
      );
    } catch (_) {
      return null;
    }
  }

  static Future<int?> loadLastPosCat() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kLastPosCat);
  }

  static Future<void> saveLastPosCat(int id) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLastPosCat, id);
    await saveRecentPosCat(id);
  }

  // Recently used POS categories (most-recent first, capped) for one-tap
  // chips in the new-product forms. IDs that no longer exist in Odoo are
  // filtered by the caller against the freshly loaded category list.
  static const _kRecentPosCats = 'recent_pos_categ_ids';
  static const recentCap = 5;

  static Future<List<int>> loadRecentPosCats() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kRecentPosCats) ?? const [];
    final out = <int>[];
    for (final s in raw) {
      final id = int.tryParse(s);
      if (id != null && !out.contains(id)) out.add(id);
    }
    return out;
  }

  static Future<void> saveRecentPosCat(int id) async {
    final p = await SharedPreferences.getInstance();
    final recent = await loadRecentPosCats();
    recent.remove(id);
    recent.insert(0, id);
    await p.setStringList(
      _kRecentPosCats,
      recent.take(recentCap).map((i) => i.toString()).toList(),
    );
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

  // Per-product promo memory for Type 02 labels (was/ends/save),
  // keyed by the label line key (barcode || SKU || name). Prefills the
  // promo section next time the same product is promoted.
  static String _promoKey(String lineKey) => 'promo_$lineKey';

  static Future<void> savePromo(
    String lineKey, {
    required double wasPrice,
    String promoEnds = '',
    String saveText = '',
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_promoKey(lineKey), [
      wasPrice.toString(),
      promoEnds,
      saveText,
    ]);
  }

  static Future<({double wasPrice, String promoEnds, String saveText})?>
      loadPromo(String lineKey) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_promoKey(lineKey));
    if (raw == null || raw.isEmpty) return null;
    final was = double.tryParse(raw[0]);
    if (was == null) return null;
    return (
      wasPrice: was,
      promoEnds: raw.length > 1 ? raw[1] : '',
      saveText: raw.length > 2 ? raw[2] : '',
    );
  }

  static Future<void> clearPromo(String lineKey) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_promoKey(lineKey));
  }
}
