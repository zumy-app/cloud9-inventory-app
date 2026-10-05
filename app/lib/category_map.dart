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
  /// Seeded from CONVENIENCE_STORE_CATEGORY_SCHEMA.md families.
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
  };

  static String _norm(String s) => s.trim().toLowerCase();

  /// Resolve [pos] to a [CategoryPair] using [internalCats].
  /// Tries the seeded name first, then the POS name itself.
  /// Returns null when unmapped — the caller must block, not fall back.
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
    return null;
  }

  /// Type-to-filter helper for the autocomplete picker.
  static List<PosCategory> filter(List<PosCategory> cats, String query) {
    final q = _norm(query);
    if (q.isEmpty) return cats;
    return cats.where((c) => _norm(c.name).contains(q)).toList();
  }
}
