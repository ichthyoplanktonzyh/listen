import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/dart_source.dart';

/// Spacer gaps live in `lib/theme/spacing.dart` as named steps of one ladder
/// (2·4·6·8·12·16·24·32) so the app breathes at one rhythm instead of 25
/// site-by-site values (see #26 / #32).
///
/// Only the childless form — `SizedBox(height: 8)` used as pure whitespace —
/// is policed. A `SizedBox` with a child (a 238px mini player, a 160px label
/// column) is element geometry, not spacing, and stays a literal.
///
/// The second test extends the same rhythm to container padding, which the
/// first one never reached: `SizedBox` was the only shape it matched, so 143
/// of the app's 340 `EdgeInsets` drifted off-ladder unchecked (10 appearing 45
/// times, then 14, 20, 18, and a tail of 1/3/5/7/9/22/28).
///
/// Padding values come from `ListenPadding`'s five container roles; the raw
/// numbers those roles are built from are the `ListenSpacing` ladder, so the
/// gate is stated in ladder terms — an `EdgeInsets` whose numbers are all on
/// the ladder is at worst an un-named role, while one carrying a 10 or an 18
/// is off the system entirely.
final _spacingLadder = <double>{0, 2, 4, 6, 8, 12, 16, 24, 32};

/// An `EdgeInsets` constructor call and its argument list, read over the whole
/// file so a wrapped call counts like an inline one. An earlier line-based
/// version missed 19 calls for no better reason than `dart format` having
/// broken them across lines — and since wrapping follows argument count, those
/// were the elaborate insets most likely to be off-ladder.
///
/// The argument list is walked with [balancedArgUnit], which cannot cross the
/// call's own closing paren, so one `EdgeInsets` never absorbs the next.
final _edgeInsets = RegExp(
  r'\bEdgeInsets(?:Directional)?\.(?:all|symmetric|only|fromLTRB)\('
  '($balancedArgUnit*)'
  r'\)',
);

/// Identifiers are stripped before numbers are read, so `ListenSpacing.gap12`
/// contributes no `12` of its own and a named constant never counts as a
/// literal.
final _identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');
final _number = RegExp(r'[0-9]+(?:\.[0-9]+)?');

/// Files under `lib/` with an off-ladder `EdgeInsets`, mapped to their
/// `path:line → source` records, reported at the line the call starts on.
///
/// `EdgeInsets.zero` is not a constructor call and never matches; an inset
/// built entirely from named constants matches but yields no numbers, so it
/// never offends. Comments and string literals are blanked before matching.
Map<String, List<String>> _paddingOffences() {
  final byFile = <String, List<String>>{};
  for (final file in libDartFiles()) {
    // The roles themselves are defined here.
    if (file.path.endsWith('theme/spacing.dart')) continue;
    final source = file.readAsStringSync();
    for (final match in _edgeInsets.allMatches(maskNonCode(source))) {
      final args = match.group(1)!.replaceAll(_identifier, '');
      final values = _number
          .allMatches(args)
          .map((m) => double.parse(m.group(0)!));
      if (values.any((value) => !_spacingLadder.contains(value))) {
        final line = lineNumberAt(source, match.start);
        (byFile[file.path] ??= []).add(
          '${file.path}:$line → ${lineAt(source, line)}',
        );
      }
    }
  }
  return byFile;
}

void main() {
  test('spacer SizedBoxes use ListenSpacing steps, not bare literals', () {
    // The closing parenthesis right after the number is what makes it a
    // childless spacer; `SizedBox(width: 160, child: …)` is geometry.
    final pattern = RegExp(r'SizedBox\((height|width):\s*[0-9.]+\)');
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final match = pattern.firstMatch(lines[i]);
        if (match != null) {
          offenders.add('${entity.path}:${i + 1} → ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use the nearest ListenSpacing step (lib/theme/spacing.dart) — or, '
          'if this SizedBox is element geometry rather than a gap, give it a '
          'child or an explicit shape so it stops looking like a spacer:\n'
          '${offenders.join('\n')}',
    );
  });

  // Existing violations at the moment this rule was written (S1). The S2
  // migration slice is done when this set is empty; no new entry may be
  // added. File-path granularity on purpose — line numbers drift with every
  // unrelated edit, so a line-level list would cost more to maintain than the
  // debt it tracks.
  const knownOffenders = <String>{
    'lib/phonetic_analysis_ui.dart',
    'lib/screens/review_queue_screen.dart',
    'lib/widgets/home/listening_home.dart',
    'lib/widgets/home/media_library_section.dart',
    'lib/widgets/panels/conversation_debrief.dart',
    'lib/widgets/panels/reading_diff_panel.dart',
    'lib/widgets/panels/reading_task_sheet.dart',
    'lib/widgets/panels/reading_task_studio.dart',
    'lib/widgets/panels/reading_view.dart',
    'lib/widgets/panels/realtime_conversation_panel.dart',
    'lib/widgets/panels/speaking_task_studio.dart',
    'lib/widgets/panels/word_learning_panel.dart',
    'lib/widgets/panels/writing_task_studio.dart',
    'lib/widgets/player/shortcut_cheat_sheet.dart',
    'lib/widgets/settings/llm_provider_settings.dart',
    'lib/widgets/settings/realtime_provider_settings.dart',
    'lib/widgets/subtitle/connected_speech_reference_ribbon.dart',
    'lib/widgets/subtitle/expected_pronunciation_reference.dart',
    'lib/widgets/subtitle/phoneme_ribbon.dart',
    'lib/widgets/subtitle/rhythm_frame_ribbon.dart',
    'lib/widgets/subtitle/token_line.dart',
  };

  test('container padding uses ListenPadding roles, not off-ladder insets', () {
    final offences = _paddingOffences();
    final offenders = [
      for (final entry in offences.entries)
        if (!knownOffenders.any(entry.key.endsWith)) ...entry.value,
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Pick the ListenPadding role that matches the container '
          '(lib/theme/spacing.dart): tight for a dense control, row for a '
          'list/panel row, card for a card or dialog body, pageCompact/page '
          'for a page or sheet:\n${offenders.join('\n')}',
    );
  });

  test('the known padding offenders only shrink', () {
    // A registered file that no longer offends must leave the list, so the
    // count stays an honest measure of the remaining debt.
    final offendingPaths = _paddingOffences().keys;
    final stale = knownOffenders.where(
      (known) => !offendingPaths.any((path) => path.endsWith(known)),
    );

    expect(
      stale,
      isEmpty,
      reason:
          'These files are registered as known offenders but no longer carry '
          'an off-ladder EdgeInsets — delete them from knownOffenders.',
    );
  });
}
