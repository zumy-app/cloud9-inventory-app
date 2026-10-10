// One-tap category picker shared by the new-product forms.
// Tap the field -> bottom sheet with the full Odoo list + search on top.
// Keyword-ranked by product name (see CategoryMap.rankForName); every
// category stays selectable, the top match just gets a "Suggested" badge.
library;

import 'package:flutter/material.dart';

import '../category_map.dart';
import '../i18n/lang.dart';
import '../odoo_client.dart';

class CategoryPickerField extends StatelessWidget {
  final List<PosCategory> categories;
  final int? selectedId;
  final ValueChanged<int> onSelected;
  final String productName;
  final bool enabled;

  const CategoryPickerField({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.productName = '',
    this.enabled = true,
  });

  String _label() {
    if (selectedId == null) return t('cat_choose');
    final m = categories.where((c) => c.id == selectedId);
    return m.isEmpty ? t('cat_choose') : m.first.name;
  }

  Future<void> _open(BuildContext context) async {
    if (!enabled || categories.isEmpty) return;
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CategorySheet(
        categories: categories,
        selectedId: selectedId,
        productName: productName,
      ),
    );
    if (id != null) onSelected(id);
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection =
        selectedId != null && categories.any((c) => c.id == selectedId);
    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: t('cat_label'),
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          _label(),
          style: TextStyle(
            color: hasSelection ? null : Theme.of(context).hintColor,
          ),
        ),
      ),
    );
  }
}

class _CategorySheet extends StatefulWidget {
  final List<PosCategory> categories;
  final int? selectedId;
  final String productName;

  const _CategorySheet({
    required this.categories,
    required this.selectedId,
    this.productName = '',
  });

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ranked =
        CategoryMap.rankForName(widget.categories, widget.productName);
    final q = _search.text;
    final shown =
        q.trim().isEmpty ? ranked : CategoryMap.filter(ranked, q);
    final topId = shown.isNotEmpty &&
            widget.productName.trim().isNotEmpty &&
            CategoryMap.matchScore(shown.first, widget.productName) > 0
        ? shown.first.id
        : null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: t('cat_search'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(t('cat_empty')))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final c = shown[i];
                        final selected = c.id == widget.selectedId;
                        final suggested = c.id == topId && !selected;
                        return ListTile(
                          title: Text(c.name),
                          trailing: selected
                              ? const Icon(Icons.check,
                                  color: Colors.green)
                              : (suggested
                                  ? Chip(
                                      label: Text(t('cat_suggested')),
                                      visualDensity:
                                          VisualDensity.compact,
                                    )
                                  : null),
                          onTap: () => Navigator.of(context).pop(c.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
