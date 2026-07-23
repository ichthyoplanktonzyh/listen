import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Corner radii live in `lib/theme/radii.dart` as four tiers plus the capsule
/// (tight 4 · control 8 · surface 12 · panel 16 · pill) so corners on one
/// screen agree instead of coming in 13 site-picked sizes (see #26 / #32).
void main() {
  test('corners use ListenRadii tiers, not circular() literals', () {
    // Matches both `BorderRadius.circular(8)` and `Radius.circular(8)`.
    final pattern = RegExp(r'Radius\.circular\(\s*[0-9]');
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // The tiers themselves are defined here.
      if (entity.path.endsWith('theme/radii.dart')) continue;
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
          'Pick the ListenRadii tier that matches the element role '
          '(lib/theme/radii.dart):\n${offenders.join('\n')}',
    );
  });
}
