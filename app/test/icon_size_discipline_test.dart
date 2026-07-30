import 'package:flutter_test/flutter_test.dart';

import 'support/dart_source.dart';

/// Icon sizes live in `lib/theme/icon_size.dart` as four steps pinned to the
/// type ladder (inline 14 · control 18 · chrome 22 · illustration 48), so an
/// icon and the label beside it carry the same visual weight on every row —
/// instead of the 14 `Icon(size:)` values and 7 `iconSize:` values the app had
/// picked site by site.
///
/// Matching runs over the whole file rather than line by line. An earlier
/// line-based version exempted every `Icon(` that `dart format` had wrapped,
/// which is not a harmless edge: wrapping is triggered by argument count, so
/// the exemption landed squarely on the busiest call sites — 34 wrapped icons
/// escaped, about a quarter of the total.
///
/// Anchoring on `Icon(` and walking a paren-balanced argument list is what
/// makes the whole-file scan safe. `ListenLoading.inline(size: 22)` shares the
/// `size:` argument name and is indistinguishable from an icon when a bare
/// `size:` line is read on its own — but it can never match here, because the
/// scan only ever looks inside an argument list that began at `Icon(`.
/// `IconButton(` and `ImageIcon(` are excluded by the lookbehind and the
/// literal `(`.
///
/// Known limits, so nobody reads this gate as total coverage: a `size:` whose
/// value is not a numeric literal is not counted; an icon nested more than two
/// paren levels deep before its `size:` argument is missed; and a size passed
/// through a variable is invisible to any textual gate.
final _pattern = RegExp(
  // `Icon(… size: <n>)`, arguments allowed to wrap.
  r'(?<![A-Za-z0-9_$])Icon\('
  '$balancedArgUnit*?'
  r'\bsize:\s*[0-9]'
  // …or an `iconSize:` literal, which is specific enough to stand alone.
  r'|\biconSize:\s*[0-9]',
);

/// Files under `lib/` holding at least one bare icon-size literal, mapped to
/// the offending `path:line → source` records.
Map<String, List<String>> _offences() {
  final byFile = <String, List<String>>{};
  for (final file in libDartFiles()) {
    // The steps themselves are defined here.
    if (file.path.endsWith('theme/icon_size.dart')) continue;
    final source = file.readAsStringSync();
    // Comments and string literals are blanked, so docs may quote the
    // forbidden form while explaining it.
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
    'lib/phonetic_analysis_ui.dart',
    'lib/screens/review_queue_screen.dart',
    'lib/widgets/common/listen_empty_state.dart',
    'lib/widgets/common/listen_error_state.dart',
    'lib/widgets/panels/reading_task_sheet.dart',
    'lib/widgets/panels/reading_task_studio.dart',
    'lib/widgets/panels/reading_view.dart',
    'lib/widgets/panels/speaking_task_studio.dart',
    'lib/widgets/panels/word_learning_panel.dart',
    'lib/widgets/panels/writing_task_studio.dart',
    'lib/widgets/settings/llm_provider_settings.dart',
    'lib/widgets/settings/realtime_provider_settings.dart',
    'lib/widgets/settings/settings_dialog.dart',
    'lib/widgets/settings/syntax_capability_settings.dart',
  };

  test('icon glyphs use ListenIconSize steps, not bare literals', () {
    final offenders = [
      for (final entry in _offences().entries)
        if (!knownOffenders.any(entry.key.endsWith)) ...entry.value,
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Pick the ListenIconSize step that matches the icon role '
          '(lib/theme/icon_size.dart): inline for text-flow markers, control '
          'for rows and chips, chrome for toolbars, illustration for empty '
          'states:\n${offenders.join('\n')}',
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
          'These files are registered as known offenders but no longer carry '
          'a bare icon size — delete them from knownOffenders.',
    );
  });
}
