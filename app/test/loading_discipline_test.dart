import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The charter forbids decorative spinners; the unified waiting language is
/// `ListenLoading` — the mutual-wave mark breathing at the ambient tempo
/// (#46, `widgets/common/listen_loading.dart`). A bare
/// `CircularProgressIndicator` reinvents waiting outside that language, so
/// none may appear in `lib/`. Exemptions, if one ever becomes necessary,
/// must be listed here with a written reason.
void main() {
  test('waiting is ListenLoading, never a bare CircularProgressIndicator', () {
    // No exemptions today. Format: path → why the site cannot use
    // ListenLoading.
    const exemptions = <String>{};

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (exemptions.contains(entity.path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        // Doc comments may name the forbidden widget (the loading widget's
        // own docs explain what it replaces); only code counts.
        if (line.startsWith('//')) continue;
        if (line.contains('CircularProgressIndicator')) {
          offenders.add('${entity.path}:${i + 1} → $line');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use ListenLoading (panel) or ListenLoading.inline (control) from '
          'widgets/common/listen_loading.dart instead:\n'
          '${offenders.join('\n')}',
    );
  });
}
