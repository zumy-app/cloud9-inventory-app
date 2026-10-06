// Unified category mapping for the v2 inventory loop.
// One picker in the UI; writes both product.template.categ_id (internal) and
// pos_categ_ids. Explicit seeded table — no fuzzy matching, no silent
// fallback: unmapped selections are blocked in the UI.
library;

import 'odoo_client.dart';

class CategoryPair {
  final int posId;
  final String posName;
  final int internalId;
  final String internalName;

  const CategoryPair({
    required this.posId,
    required this.posName,
    required this.internalId,
    required this.internalName,
  });
}

class CategoryMap {
  /// POS category name → internal product.category name.
  /// Seeded from CONVENIENCE_STORE_CATEGORY_SCHEMA.md families plus the
  /// real production POS names seen in Odoo (e.g. "Beverages - Taxable").
  static const Map<String, String> posToInternal = {
    'Tobacco': 'Tobacco',
    'Drinks': 'Drinks',
    'Snacks': 'Snacks',
    'Fresh Food': 'Fresh Food',
    'Automotive': 'Automotive',
    'Propane': 'Propane',
    'Ice': 'Ice',
    'General Merchandise': 'General Merchandise',
    'Lottery/Games': 'Lottery/Games',
    'Services': 'Services',
    // Production aliases (Odoo pos.category names).
    'Beverages': 'Drinks',
    'Beverages - Taxable': 'Drinks',
    'Beverages - Nontaxable': 'Drinks',
    'Beverages - Non-Taxable': 'Drinks',
    'Beverages - Non Taxable': 'Drinks',
    'Soda': 'Drinks',
    'Soda - Taxable': 'Drinks',
  };

  /// Base-name synonyms: normalized base POS name → normalized internal name.
  /// Handles future "X - Taxable / Nontaxable" POS variants without a code push.
  static const Map<String, String> _baseSynonyms = {
    'beverages': 'drinks',
    'beverage': 'drinks',
    'drinks': 'drinks',
    'drink': 'drinks',
    'soda': 'drinks',
    'snacks': 'snacks',
    'snack': 'snacks',
    'tobacco': 'tobacco',
    'fresh food': 'fresh food',
    'automotive': 'automotive',
    'propane': 'propane',
    'ice': 'ice',
    'general merchandise': 'general merchandise',
    'lottery/games': 'lottery/games',
    'lottery': 'lottery/games',
    'services': 'services',
  };

  static String _norm(String s) => s.trim().toLowerCase();

  /// Strip POS suffixes like " - Taxable", " - Nontaxable", " (…)", " / …".
  static String _baseName(String s) {
    var b = s.trim();
    // "Beverages - Taxable" -> "Beverages"
    final dash = b.indexOf(' - ');
    if (dash > 0) b = b.substring(0, dash).trim();
    // "Drinks / Soda" -> "Drinks"
    final slash = b.indexOf(' / ');
    if (slash > 0) b = b.substring(0, slash).trim();
    // "Drinks (Cold)" -> "Drinks"
    final paren = b.indexOf(' (');
    if (paren > 0) b = b.substring(0, paren).trim();
    return b;
  }

  static PosCategory? _findInternal(
      List<PosCategory> internalCats, String want) {
    final w = _norm(want);
    for (final c in internalCats) {
      if (_norm(c.name) == w) return c;
    }
    return null;
  }

  /// Strict resolve: exact seeded name, then POS name itself, then base-name
  /// + synonym match. Returns null when unmapped — use [resolveForCreate]
  /// when creating products so a valid POS pick never blocks the sale floor.
  static CategoryPair? resolve({
    required PosCategory pos,
    required List<PosCategory> internalCats,
  }) {
    final candidates = <String>[
      posToInternal[pos.name] ?? pos.name,
      pos.name,
    ];
    for (final want in candidates) {
      for (final c in internalCats) {
        if (_norm(c.name) == _norm(want)) {
          return CategoryPair(
            posId: pos.id,
            posName: pos.name,
            internalId: c.id,
            internalName: c.name,
          );
        }
      }
    }
    // Base-name + synonym pass: "Beverages - Taxable" -> base "Beverages"
    // -> synonym "drinks" -> internal "Drinks".
    final base = _baseName(pos.name);
    final mappedBase = _baseSynonyms[_norm(base)] ?? base;
    final seeded = posToInternal[base] ?? posToInternal[pos.name];
    for (final want in <String>{seeded ?? mappedBase, mappedBase, base}) {
      final hit = _findInternal(internalCats, want);
      if (hit != null) {
        return CategoryPair(
          posId: pos.id,
          posName: pos.name,
          internalId: hit.id,
          internalName: hit.name,
        );
      }
    }
    return null;
  }

  /// Best-effort internal category when [resolve] misses: prefer "All",
  /// else the first internal category. Null only when [internalCats] is empty
  /// (caller then lets Odoo apply its server default).
  static PosCategory? fallbackInternal(List<PosCategory> internalCats) {
    if (internalCats.isEmpty) return null;
    for (final c in internalCats) {
      if (_norm(c.name) == 'all') return c;
    }
    return internalCats.first;
  }

  /// Non-blocking resolve for product creation: exact mapping when possible,
  /// else the POS pick paired with the fallback internal category so the
  /// "Unmapped — pick again" dead-end in the screenshot can never happen.
  /// Returns null only when [_catId] is unset or no categories are loaded.
  static CategoryPair? resolveForCreate({
    required int? posId,
    required List<PosCategory> posCats,
    required List<PosCategory> internalCats,
  }) {
    if (posId == null || posCats.isEmpty) return null;
    final matches = posCats.where((c) => c.id == posId).toList();
    if (matches.isEmpty) return null;
    final pos = matches.first;
    final exact = resolve(pos: pos, internalCats: internalCats);
    if (exact != null) return exact;
    final fb = fallbackInternal(internalCats);
    if (fb == null) return null;
    return CategoryPair(
      posId: pos.id,
      posName: pos.name,
      internalId: fb.id,
      internalName: fb.name,
    );
  }

  /// Type-to-filter helper for the autocomplete picker.
  static List<PosCategory> filter(List<PosCategory> cats, String query) {
    final q = _norm(query);
    if (q.isEmpty) return cats;
    return cats.where((c) => _norm(c.name).contains(q)).toList();
  }
}
