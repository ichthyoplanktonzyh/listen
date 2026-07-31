/// UI language and learning language are separate (AGENT.md). A sentence
/// welded into `lib/` picks one of them for everybody.
///
/// The field report that opened this rule: 我的表达 shipped with 65 Chinese
/// literals and one `l.text` call, while the realtime conversation panel and
/// the manual timeline dialog shipped entirely in English with zero. An `en`
/// learner opened 我的表达 to a screen of Chinese; a `zh` learner opened the
/// conversation to a screen of English. Switching the interface language did
/// nothing to either.
///
/// Unlike colour, i18n had **no source-level invariant** — `theme_palette_
/// discipline_test.dart` turns red the moment a pale constant reaches the
/// chrome, and nothing did the equivalent here, so a whole new surface could
/// merge without ever touching `AppLocalizations`.
///
/// ## Why Han ideographs, and only those
///
/// The gate is deliberately one-sided: it can catch a Chinese literal, and it
/// cannot catch an English one. That asymmetry is not laziness, it is the only
/// half a textual scan can decide. `'Recent conversations'` and
/// `'qwen3.5-omni-plus-realtime'` are the same thing to a regular expression —
/// letters — so a gate that tried to flag English copy would either drown in
/// identifiers, keys, MIME types and provider names, or need an exemption list
/// longer than the code it guards. A Han ideograph in a string literal has no
/// such ambiguity: this repository has no Chinese identifiers and no Chinese
/// wire values, so every match is prose.
///
/// The practical consequence is that the gate holds one direction of the rule
/// permanently (Chinese copy cannot re-enter `lib/`) and the other direction —
/// English copy — stays the reviewer's job, backed by the widget tests that
/// pump a specific `AppLocalizations` and assert on what renders.
///
/// The scan reads **string literals only** ([stringLiteralsOnly]), which is the
/// opposite of what the token gates want. Most of this repository's own
/// documentation is written in Chinese, including the doc comments on the very
/// widgets being migrated: a gate that read comments would flag 「门厅」 in a
/// class doc and be switched off within a week.
///
/// ## Known limits, so nobody reads this gate as total coverage
///
/// A Chinese sentence assembled from a `String` variable, loaded from a
/// fixture, or returned by a helper is invisible to it, as is any English
/// hardcoding. It stops the regression that actually happened — a new surface
/// merging with its copy welded in — it does not prove the absence of the
/// class.
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/dart_source.dart';

/// CJK Unified Ideographs and Extension A. Punctuation (`，。！？`) is
/// deliberately *not* matched: `lib/utils/learning_text_hygiene.dart`
/// normalises fullwidth punctuation as data, and such a table is the opposite
/// of a hardcoded sentence.
final _han = RegExp(r'[一-鿿㐀-䶿]');

/// Chinese text that stays Chinese in an English interface, because it is not
/// interface copy at all. Each entry is a proper name, and the reasons are
/// recorded once in `docs/development/ui-terminology.md`:
///
/// - a language names itself in its own script, in every locale (`中文` in an
///   `en` menu of subtitle languages is correct, not a missed translation);
/// - 百炼 is Alibaba Cloud Model Studio's Chinese product name, which is how
///   its own console spells it — translating it would send a learner looking
///   for a console page that does not exist.
///
/// Stripped from the literal before the check, so a line that mixes a proper
/// name with real copy still fails on the copy.
const _properNames = {'中文', '日本語', '한국어', '百炼'};

/// A statement allowed to contain Han, because it matches text rather than
/// displaying it.
///
/// `RegExp(r'^\d{4}年\d{1,2}月')` in `lib/utils/media_title.dart` reads a date
/// out of a downloaded filename. That is the *learning content* side of the
/// AGENT.md split — data arriving from the world — and a pattern that has to
/// recognise `年` cannot be translated without ceasing to work.
final _matchingStatement = RegExp(r'\bRegExp\(');

/// Files under `lib/` carrying a Han ideograph inside a string literal, mapped
/// to the offending `path:line → source` records.
Map<String, List<String>> _offences() {
  final byFile = <String, List<String>>{};
  for (final file in libDartFiles()) {
    // The translation table is where the Chinese belongs.
    if (file.path.endsWith('lib/localization.dart')) continue;
    final source = file.readAsStringSync();
    // Comments are blanked and literals kept — the inverse of the token gates.
    // This repository documents itself in Chinese; only the copy is in scope.
    final prose = stringLiteralsOnly(source);
    final code = maskNonCode(source);

    // One record per line, not per ideograph: a sentence has many of them and
    // they are one offence. The *first* match on the line is what the
    // statement check runs from, exactly as in `error_leak_discipline_test`.
    for (final match in _han.allMatches(prose)) {
      final line = lineNumberAt(prose, match.start);
      final records = byFile[file.path] ??= [];
      final record = '${file.path}:$line → ${lineAt(source, line)}';
      if (records.contains(record)) continue;
      if (!_han.hasMatch(_withoutProperNames(lineAt(prose, line)))) continue;
      if (_matchingStatement.hasMatch(statementAt(code, match.start))) continue;
      records.add(record);
    }
    if (byFile[file.path]?.isEmpty ?? false) byFile.remove(file.path);
  }
  return byFile;
}

String _withoutProperNames(String text) =>
    _properNames.fold(text, (stripped, name) => stripped.replaceAll(name, ''));

void main() {
  // Every file that still welds Chinese copy into `lib/`, at the moment this
  // rule was written (S6 · #7). The migration is done when this set is empty;
  // no new entry may be added.
  //
  // File-path granularity on purpose — line numbers drift with every unrelated
  // edit, so a line-level list would cost more to maintain than the debt it
  // tracks. Same shape as `icon_size_discipline_test.dart` and
  // `error_leak_discipline_test.dart`.
  //
  // S6 cleared 我的表达 (62 literals) and the manual timing dialog, leaving
  // three files outside its domain to whoever next touched them. S2 then took
  // two of the three: the studios slice picked up `reading_view` (its single
  // 保存到我的表达 tooltip now reads the `expressionSaveTitle` key both tables
  // already carried), and the panels slice picked up `learning_assets_ui`
  // (whose two literals likewise duplicated existing keys). One file left.
  const knownOffenders = <String>{
    // 当前来源切片 / 暂停 / 播放 / 跟一下 on the dictionary clip player.
    'lib/widgets/vocabulary/dictionary_inline_clip_player.dart',
  };

  test('user-visible copy lives in localization.dart, not in a literal', () {
    final offenders = [
      for (final entry in _offences().entries)
        if (!knownOffenders.any(entry.key.endsWith)) ...entry.value,
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Move the sentence into both tables in lib/localization.dart and '
          'read it through AppLocalizations.text — UI language and learning '
          'language are separate (AGENT.md):\n${offenders.join('\n')}',
    );
  });

  test('the known-offender list only shrinks', () {
    // A registered file that no longer offends must leave the list, so the
    // count stays an honest measure of the remaining debt — and so the list
    // cannot be padded to force green.
    final offendingPaths = _offences().keys;
    final stale = knownOffenders.where(
      (known) => !offendingPaths.any((path) => path.endsWith(known)),
    );

    expect(
      stale,
      isEmpty,
      reason:
          'These files are registered as known offenders but no longer hold a '
          'Chinese literal — delete them from knownOffenders.',
    );
  });
}
