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
}
