import 'package:flutter_test/flutter_test.dart';

import 'support/dart_source.dart';

/// `ListenTheme._textTheme` maps the `ListenType` ladder onto eight Material
/// `textTheme` slots (labelSmall … titleLarge). The display/headline slots are
/// deliberately left unmapped, so reading one hands the widget Material's own
/// geometry — 24/28px at w400 — which is nowhere on the ladder
/// (11/12/13/14/16/22) and belongs to no typographic decision anyone made
/// here. Sixteen sites had picked one up that way, while the real hero size
/// was used exactly once.
///
/// A page title is `titleLarge` (= `ListenType.hero`). If a page genuinely
/// needs a size above 22, the fix is a new rung on the ladder plus a mapping
/// in `_textTheme`, not a raw Material slot.
///
/// Matching runs over the whole file, with comments and string literals
/// blanked, so a slot read that `dart format` wrapped onto its own line
/// (`)\n    .textTheme\n    .headlineMedium`) still counts.
final _pattern = RegExp(
  r'textTheme\s*\.\s*(?:headline|display)(?:Small|Medium|Large)\b',
);

/// Files under `lib/` reading an unmapped slot, mapped to their
/// `path:line → source` records.
Map<String, List<String>> _offences() {
  final byFile = <String, List<String>>{};
  for (final file in libDartFiles()) {
    // The mapping itself, and the doc that explains the rule, live here.
    if (file.path.endsWith('theme/listen_theme.dart')) continue;
    final source = file.readAsStringSync();
    for (final match in _pattern.allMatches(maskNonCode(source))) {
      final line = lineNumberAt(source, match.start);
      (byFile[file.path] ??= []).add(
        '${file.path}:$line → ${lineAt(source, line)}',
      );
    }
  }
  return byFile;
}

void main() {
  // Existing violations at the moment this rule was written (S1). The S2
  // migration slice is done when this set is empty; no new entry may be
  // added. File-path granularity on purpose — line numbers drift with every
  // unrelated edit, so a line-level list would cost more to maintain than the
  // debt it tracks.
  const knownOffenders = <String>{
    'lib/screens/review_queue_screen.dart',
    'lib/widgets/coach/coach_dashboard_screen.dart',
    'lib/widgets/common/capability_viz.dart',
    'lib/widgets/panels/speaking_task_studio.dart',
    'lib/widgets/panels/word_learning_panel.dart',
    'lib/widgets/panels/writing_task_studio.dart',
  };

  test('text styles come from mapped textTheme slots, not display/headline', () {
    final offenders = [
      for (final entry in _offences().entries)
        if (!knownOffenders.any(entry.key.endsWith)) ...entry.value,
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Use a slot the theme maps to the ListenType ladder — titleLarge '
          'for a page title (ListenType.hero), titleMedium for a section '
          'title, bodyLarge/titleSmall for emphasis (lib/theme/typography.dart, '
          'lib/theme/listen_theme.dart):\n${offenders.join('\n')}',
    );
  });

  test('the known-offender list only shrinks', () {
    // A registered file that no longer offends must leave the list, so the
    // count stays an honest measure of the remaining debt.
    final offendingPaths = _offences().keys;
    final stale = knownOffenders.where(
      (known) => !offendingPaths.any((path) => path.endsWith(known)),
    );

    expect(
      stale,
      isEmpty,
      reason:
          'These files are registered as known offenders but no longer read '
          'an unmapped slot — delete them from knownOffenders.',
    );
  });
}
