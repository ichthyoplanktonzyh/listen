import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Icon sizes live in `lib/theme/icon_size.dart` as four steps pinned to the
/// type ladder (inline 14 · control 18 · chrome 22 · illustration 48), so an
/// icon and the label beside it carry the same visual weight on every row —
/// instead of the 14 `Icon(size:)` values and 7 `iconSize:` values the app had
/// picked site by site.
///
/// The regex is deliberately narrow: only a single-line `Icon(… size: <n>)`
/// or a literal `iconSize: <n>` counts. A `size:` argument that sits alone on
/// its own line is left alone, because there it is indistinguishable from
/// `ListenLoading.inline(size:)` and other non-icon sizes. A missed offender
/// is cheap; a false one turns the gate into noise.
///
/// `Icon(` only — `IconButton(` and `ImageIcon(` do not match, and the
/// lookbehind keeps any other `…Icon(` suffix out.
final _pattern = RegExp(
  r'(?<![A-Za-z0-9_$])Icon\([^)]*\bsize:\s*[0-9]|\biconSize:\s*[0-9]',
);

/// Files under `lib/` holding at least one bare icon-size literal, mapped to
/// the offending `path:line → source` records.
Map<String, List<String>> _offences() {
  final byFile = <String, List<String>>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // The steps themselves are defined here.
    if (entity.path.endsWith('theme/icon_size.dart')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      // Docs may quote the forbidden form while explaining it.
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
    'lib/phonetic_analysis_ui.dart',
    'lib/screens/review_queue_screen.dart',
    'lib/screens/vocabulary_screen.dart',
    'lib/widgets/app_bar/player_app_bar.dart',
    'lib/widgets/common/listen_error_state.dart',
    'lib/widgets/flows/media_import_flows.dart',
    'lib/widgets/home/listening_home.dart',
    'lib/widgets/home/media_library_section.dart',
    'lib/widgets/layout/content_channel_switcher.dart',
    'lib/widgets/layout/player_stage.dart',
    'lib/widgets/layout/side_panel.dart',
    'lib/widgets/panels/cold_start_marking_sheet.dart',
    'lib/widgets/panels/content_fit_card.dart',
    'lib/widgets/panels/diagnosis_card.dart',
    'lib/widgets/panels/intensive_practice_window.dart',
    'lib/widgets/panels/listening_check_panel.dart',
    'lib/widgets/panels/listening_inbox_panel.dart',
    'lib/widgets/panels/llm_feedback_assist.dart',
    'lib/widgets/panels/llm_judgment_assist.dart',
    'lib/widgets/panels/manual_timeline_review_dialog.dart',
    'lib/widgets/panels/reading_task_sheet.dart',
    'lib/widgets/panels/reading_task_studio.dart',
    'lib/widgets/panels/reading_view.dart',
    'lib/widgets/panels/slice_playback_window.dart',
    'lib/widgets/panels/speaking_task_studio.dart',
    'lib/widgets/panels/subtitle_resource_manager_panel.dart',
    'lib/widgets/panels/timeline_resource_summary_panel.dart',
    'lib/widgets/panels/transcript_panel.dart',
    'lib/widgets/panels/word_learning_panel.dart',
    'lib/widgets/panels/writing_task_studio.dart',
    'lib/widgets/player/download_status_bar.dart',
    'lib/widgets/player/playback_controls.dart',
    'lib/widgets/settings/llm_provider_settings.dart',
    'lib/widgets/settings/realtime_provider_settings.dart',
    'lib/widgets/settings/settings_dialog.dart',
    'lib/widgets/subtitle/following_structure_viewport.dart',
    'lib/widgets/vocabulary/entry_detail_parts.dart',
    'lib/widgets/vocabulary/listening_dictionary_entry_view.dart',
  };

  test('icon glyphs use ListenIconSize steps, not bare literals', () {
    final offences = _offences();
    final offenders = [
      for (final entry in offences.entries)
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
