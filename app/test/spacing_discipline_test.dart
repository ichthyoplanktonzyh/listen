import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spacer gaps live in `lib/theme/spacing.dart` as named steps of one ladder
/// (2·4·6·8·12·16·24·32) so the app breathes at one rhythm instead of 25
/// site-by-site values (see #26 / #32).
///
/// Only the childless form — `SizedBox(height: 8)` used as pure whitespace —
/// is policed. A `SizedBox` with a child (a 238px mini player, a 160px label
/// column) is element geometry, not spacing, and stays a literal.
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
}
