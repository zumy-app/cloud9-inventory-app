// Intuitive language switch: full language names, current highlighted,
// one tap, persists per device. Used on login (pre-auth) and Account.
library;

import 'package:flutter/material.dart';

import '../i18n/lang.dart';

class LangSwitch extends StatelessWidget {
  final bool compact;
  const LangSwitch({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Lang.instance,
      builder: (context, child) => SegmentedButton<AppLang>(
        segments: [
          ButtonSegment(
            value: AppLang.en,
            label: Text(Lang.instance.t('lang_english')),
          ),
          ButtonSegment(
            value: AppLang.es,
            label: Text(Lang.instance.t('lang_spanish')),
          ),
        ],
        selected: {Lang.instance.current},
        onSelectionChanged: (s) => Lang.instance.set(s.first),
        style: compact
            ? ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )
            : null,
      ),
    );
  }
}
