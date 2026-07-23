import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Colors in [ListenColors] that only make sense under one brightness. Reading
/// them straight from a widget pins that widget to the light theme, which is
/// how dark mode grows white patches and unreadable text.
const _brightnessBound = [
  'fog',
  'surface',
  'sidebar',
  'primary',
  'primaryPressed',
  'selected',
  'text',
  'muted',
  'outline',
  'border',
  'accent',
  'error',
  'info',
  'infoSurface',
  'disabled',
  // Verdict shades (#22) go through the ListenSchemeShades getters.
  'verdictCovered',
  'verdictPartial',
  'darkVerdictCovered',
  'darkVerdictPartial',
];

/// Files exempt from the rule:
/// - `theme/` defines the palette and both schemes.
/// - `widgets/subtitle/` renders over arbitrary video frames, so it owns a
///   deliberately brightness-independent dark overlay vocabulary and must not
///   follow the app theme (see #12 Slice 4, requirement 3).
bool _exempt(String path) =>
    path.contains('lib/theme/') || path.contains('lib/widgets/subtitle/');

void main() {
  test('app chrome reads brightness-bound colors off the theme, not the '
      'palette', () {
    final pattern = RegExp(
      r'ListenColors\.(' + _brightnessBound.join('|') + r')\b',
    );
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (_exempt(entity.path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final match = pattern.firstMatch(lines[i]);
        if (match != null) {
          offenders.add('${entity.path}:${i + 1} → ${match.group(0)}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use Theme.of(context).colorScheme (or ListenSchemeShades) so these '
          'sites follow the active brightness:\n${offenders.join('\n')}',
    );
  });

  // #22: the first gate only guarded `ListenColors.*`; `Colors.green.shade700`
  // and `Color(0xff…)` literals walked straight past it. This gate closes that
  // hole. Exempt files carry a written reason and a pinned line count, so a
  // new hard-coded color in an exempt file still fails until it is justified
  // here.
  test('app chrome takes no colors from the Material palette or hex literals '
      'either', () {
    // `Colors.transparent` is brightness-free; everything else on `Colors`
    // pins a hue that ignores the active scheme. `Color(0x…)` literals are
    // the same smell without the name. The lookbehind keeps `ListenColors.*`
    // reads out — named palette constants are the first test's business.
    final pattern = RegExp(
      r'(?<![A-Za-z_$])Colors\.(?!transparent\b)[a-z]|Color\(0x',
    );

    const exemptFiles = <String, ({String reason, int lines})>{
      'lib/widgets/listen_wordmark.dart': (
        reason: 'brand mark constants are never theme-flipped (#32)',
        lines: 2,
      ),
      'lib/widgets/layout/player_stage.dart': (
        reason:
            'the video stage itself: letterbox black plus furniture floating '
            'over arbitrary video frames — brightness-independent by design, '
            'same rationale as widgets/subtitle/',
        lines: 8,
      ),
      'lib/widgets/settings/settings_dialog.dart': (
        reason:
            'subtitle color swatches are user content rendered over video, '
            'not chrome (#22)',
        lines: 5,
      ),
    };

    final offenders = <String>[];
    final exemptCounts = <String, int>{};

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (_exempt(entity.path)) continue;
      final exemptKey = exemptFiles.keys.firstWhere(
        entity.path.endsWith,
        orElse: () => '',
      );
      final lines = entity.readAsLinesSync();
      var hits = 0;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        final match = pattern.firstMatch(lines[i]);
        if (match == null) continue;
        hits++;
        if (exemptKey.isEmpty) {
          offenders.add('${entity.path}:${i + 1} → ${lines[i].trim()}');
        }
      }
      if (exemptKey.isNotEmpty) exemptCounts[exemptKey] = hits;
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Colors must come from the active ColorScheme (or a named '
          'ListenColors constant when genuinely brightness-independent):\n'
          '${offenders.join('\n')}',
    );

    for (final entry in exemptFiles.entries) {
      expect(
        exemptCounts[entry.key] ?? 0,
        lessThanOrEqualTo(entry.value.lines),
        reason:
            '${entry.key} is exempt for exactly ${entry.value.lines} '
            'hard-coded color(s) (${entry.value.reason}); a new one needs its '
            'own justification here.',
      );
    }
  });
}
