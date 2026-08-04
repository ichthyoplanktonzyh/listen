import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/theme/breakpoints.dart';

import 'support/dart_source.dart';

/// Content-column caps live in `lib/theme/breakpoints.dart` as a named
/// vocabulary (notice 360 · form 560 · card 680 · content 780 · wide 960),
/// because "how wide may a column grow" is one product decision, not nineteen.
/// Nineteen is what the app had: `BoxConstraints(maxWidth:)` literals at
/// 200/360/400/440/520/560/620/760/900/920, several of them a few pixels apart
/// for no reason anyone could name.
///
/// `notice` was added by the migration (S2, 决策 2) rather than by the original
/// vocabulary: the centred empty/failed states cap at 360, and forcing them onto
/// `form` — the narrowest cap that existed — would have widened a two-line
/// sentence by 200pt. Adding a rung is the right answer when a real measure has
/// no name; picking the nearest existing rung is how a vocabulary stops meaning
/// anything.
///
/// Only `maxWidth` is policed. `maxHeight` is not a column measure — it is
/// almost always a viewport or overlay budget — and `minWidth` is a floor,
/// which is element geometry.
///
/// Matching runs over the whole file, with comments and string literals
/// blanked, so a constraint whose value `dart format` wrapped onto the next
/// line still counts.
final _pattern = RegExp(r'\bmaxWidth:\s*[0-9]');

/// Files under `lib/` with a hard-coded `maxWidth`, mapped to their
/// `path:line → source` records.
Map<String, List<String>> _offences() {
  final byFile = <String, List<String>>{};
  for (final file in libDartFiles()) {
    // The column vocabulary itself is defined here.
    if (file.path.endsWith('theme/breakpoints.dart')) continue;
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
  const knownOffenders = <String>{};

  test('column caps use ListenBreakpoints widths, not maxWidth literals', () {
    final offenders = [
      for (final entry in _offences().entries)
        if (!knownOffenders.any(entry.key.endsWith)) ...entry.value,
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Pick the ListenBreakpoints column cap that matches the content '
          '(lib/theme/breakpoints.dart): noticeColumnMax for a centred block '
          'of short copy, formColumnMax for a form, cardColumnMax for a single '
          'card, contentColumnMax for a reading column, wideColumnMax for '
          'two-column or media pages. If the value is the fixed size of a '
          'graphic rather than a cap on text, it is element geometry — name it '
          'on the widget instead:\n'
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

  test('the column vocabulary stays ordered notice < form < card < content < '
      'wide', () {
    // The caps are only a vocabulary if each step is visibly wider than the
    // last; two caps within a few pixels would put the choice back on the call
    // site, which is the drift this replaces.
    expect(
      ListenBreakpoints.noticeColumnMax,
      lessThan(ListenBreakpoints.formColumnMax),
    );
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
