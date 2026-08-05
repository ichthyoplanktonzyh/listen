import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';

/// Generator failure codes must reach the user as sentences, not identifiers.
///
/// The real incident: a machine with no `listen-gen` configured showed
/// "资源包生成失败" followed by the bare string `generator_not_configured`, and
/// offered a generate button that could only produce the same result forever.
/// The code was honest and completely useless — it named an internal symbol,
/// said nothing about what to do, and was never localized, so
/// `cjk_literal_discipline_test.dart` could not see it either (it is not a
/// Chinese literal, and not a literal in `lib/` at all — it arrives at runtime
/// on an exception field).
///
/// Two rules, both checked here:
///
/// 1. every code `ListenGenProcessService` can emit has a localized sentence;
/// 2. that sentence exists in both `en` and `zh`.
///
/// Unknown codes still fall through to the raw code in `_failureDetail` — a
/// generator from a newer release may say something this app has never heard
/// of, and swallowing it would be worse than showing it. This test is what
/// keeps "unknown" from quietly meaning "all of them".
void main() {
  test('every generator failure code has copy in both locales', () {
    final source = File(
      'lib/services/listen_gen_process_service.dart',
    ).readAsStringSync();

    // Codes are thrown as `ListenGenProcessFailure('x')` or completed through
    // `_completeFailure('x')`; both are literal at the throw site.
    final codes =
        RegExp(r"(?:ListenGenProcessFailure|_completeFailure)\(\s*'([a-z_]+)'")
            .allMatches(source)
            .map((match) => match.group(1)!)
            .where((code) => code != 'cancelled')
            .toSet();

    expect(
      codes,
      isNotEmpty,
      reason:
          'the code scan found nothing — the throw sites moved or changed '
          'shape, so this test is no longer checking anything',
    );

    final panel = File(
      'lib/widgets/discovery/detail_panel.dart',
    ).readAsStringSync();

    final missing = <String>[];
    final untranslated = <String>[];
    for (final code in codes) {
      final entry = RegExp("'$code':\\s*'([A-Za-z]+)'").firstMatch(panel);
      if (entry == null) {
        missing.add(code);
        continue;
      }
      final key = entry.group(1)!;
      for (final locale in const ['en', 'zh']) {
        final copy = AppLocalizations(Locale(locale)).text(key);
        // `text` returns the key itself when the entry is absent.
        if (copy == key || copy.isEmpty) {
          untranslated.add('$code → $key ($locale)');
        }
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'these generator codes would be printed to the user as raw '
          'identifiers; add them to `_generatorFailureKeys` in '
          'detail_panel.dart with a sentence that says what happened:\n'
          '${missing.join('\n')}',
    );
    expect(
      untranslated,
      isEmpty,
      reason:
          'mapped to a key with no copy in one or both locales:\n'
          '${untranslated.join('\n')}',
    );
  });

  test('the unavailable state has copy in both locales', () {
    // "No generator on this machine" is an unavailable capability, not a
    // failed run, so it carries its own sentence plus a hint naming the real
    // next step. Without the hint the row is honest but still a dead end.
    for (final key in const [
      'discoveryGeneratorUnavailable',
      'discoveryGeneratorUnavailableHint',
    ]) {
      for (final locale in const ['en', 'zh']) {
        final copy = AppLocalizations(Locale(locale)).text(key);
        expect(
          copy,
          isNot(equals(key)),
          reason: '$key is missing its $locale copy',
        );
      }
    }
  });
}
