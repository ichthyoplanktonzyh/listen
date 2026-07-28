import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/theme/breakpoints.dart';

/// Content-column caps live in `lib/theme/breakpoints.dart` as a named
/// vocabulary (form 560 · card 680 · content 780 · wide 960), because "how
/// wide may a column grow" is one product decision, not nineteen. Nineteen is
/// what the app had: `BoxConstraints(maxWidth:)` literals at 200/360/400/440/
/// 520/560/620/760/900/920, several of them a few pixels apart for no reason
/// anyone could name.
///
/// Only `maxWidth` is policed. `maxHeight` is not a column measure — it is
/// almost always a viewport or overlay budget — and `minWidth` is a floor,
/// which is element geometry.
final _pattern = RegExp(r'\bmaxWidth:\s*[0-9]');

/// Files under `lib/` with a hard-coded `maxWidth`, mapped to their
/// `path:line → source` records.
Map<String, List<String>> _offences() {
  final byFile = <String, List<String>>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // The column vocabulary itself is defined here.
    if (entity.path.endsWith('theme/breakpoints.dart')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('//')) continue;
      if (_pattern.hasMatch(line)) {
        (byFile[entity.path] ??= []).add('${entity.path}:${i + 1} → $line');
      }
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
    'lib/widgets/common/capability_viz.dart',
    'lib/widgets/flows/content_speaking_activity_dialog.dart',
    'lib/widgets/home/listening_home.dart',
    'lib/widgets/layout/side_panel.dart',
    'lib/widgets/panels/cold_start_marking_sheet.dart',
    'lib/widgets/panels/conversation_afterglow_caption.dart',
    'lib/widgets/panels/hunting_prompt_card.dart',
    'lib/widgets/panels/reading_diff_panel.dart',
    'lib/widgets/panels/reading_view.dart',
    'lib/widgets/panels/realtime_conversation_panel.dart',
    'lib/widgets/panels/speaking_task_studio.dart',
    'lib/widgets/panels/transcript_panel.dart',
    'lib/widgets/panels/writing_task_studio.dart',
    'lib/widgets/player/playback_controls.dart',
  };

  test('column caps use ListenBreakpoints widths, not maxWidth literals', () {
    final offences = _offences();
    final offenders = [
      for (final entry in offences.entries)
        if (!knownOffenders.any(entry.key.endsWith)) ...entry.value,
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Pick the ListenBreakpoints column cap that matches the content '
          '(lib/theme/breakpoints.dart): formColumnMax for a form, '
          'cardColumnMax for a single card, contentColumnMax for a reading '
          'column, wideColumnMax for two-column or media pages:\n'
          '${offenders.join('\n')}',
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
          'a hard-coded maxWidth — delete them from knownOffenders.',
    );
  });

  test('the column vocabulary stays ordered form < card < content < wide', () {
    // The four caps are only a vocabulary if each step is visibly wider than
    // the last; two caps within a few pixels would put the choice back on the
    // call site, which is the drift this replaces.
    expect(
      ListenBreakpoints.formColumnMax,
      lessThan(ListenBreakpoints.cardColumnMax),
    );
    expect(
      ListenBreakpoints.cardColumnMax,
      lessThan(ListenBreakpoints.contentColumnMax),
    );
    expect(
      ListenBreakpoints.contentColumnMax,
      lessThan(ListenBreakpoints.wideColumnMax),
    );
    // A wide content page still fits inside the supported minimum window's
    // growth path rather than assuming a maximised display.
    expect(
      ListenBreakpoints.wideColumnMax,
      greaterThan(ListenBreakpoints.minWindowWidth),
    );
  });
}
