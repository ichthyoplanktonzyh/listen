import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Layout breakpoints live in `lib/theme/breakpoints.dart` as named constants
/// so the shape of the app at a given width is readable in one place instead
/// of being spread across a dozen `LayoutBuilder` bodies (see #12 Slice 5).
void main() {
  test('layout width thresholds come from ListenBreakpoints, not literals', () {
    // `constraints.maxWidth < 820`, `maxWidth >= 900`, and the reversed form.
    // Three digits or more, so degenerate-constraint guards such as
    // `maxWidth <= 0` are not mistaken for breakpoints.
    final pattern = RegExp(
      r'(maxWidth\s*[<>]=?\s*\d{3,}|\d{3,}\s*[<>]=?\s*constraints\.maxWidth)',
    );
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
          'Add a named constant to ListenBreakpoints and reference it here:\n'
          '${offenders.join('\n')}',
    );
  });
}
