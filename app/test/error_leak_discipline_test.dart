/// A caught exception is diagnostics. It is never copy.
///
/// The field report that opened this rule: a learner's own transcript slot
/// rendered
///
///     Could not process learner turn: HttpException: {"code":"validation_error",
///     "message":"…","correlation_id":"api-853"}, uri = http://127.0.0.1:62645/v1/recordings
///
/// One string, and it leaked an internal error code, a correlation id, the
/// sidecar's loopback port and an internal route. The charter's P4 asks for an
/// honest instrument, **not debug output**. The shape that produced it —
/// `catch (error) { … '$error' … }` — appeared at ~126 sites across ~30 files,
/// so the leak is a pattern, not an incident.
///
/// ## What counts as a violation
///
/// Two forms, both of which put an exception's own text into a value that a
/// widget can render:
///
/// 1. an **interpolation of a caught exception inside a string literal** —
///    `'…: $error'`, `'${error}'`, `'${error.toString()}'`;
/// 2. a bare **`error.toString()` in code**, which is the same move with the
///    string built one line later (`_setSnapshot(Snapshot.failed(e.toString()))`).
///
/// ## What does not count: the diagnostic channel
///
/// Exception detail is not forbidden — *rendering* it is. It has one sanctioned
/// home, [ApiFailure.raw], which is documented as never being rendered even in
/// an expanded disclosure, and which `describeApiFailure` fills by design. So a
/// match is exempt when its statement is one of:
///
/// - an `ApiFailure(` construction — the diagnostic type itself;
/// - a `debugPrint(` / `print(` / `log(` call — a log line, not a screen;
/// - a `throw` — re-raising with context hands the value to the next `catch`,
///   which is where this rule applies again, one layer up.
///
/// Anything else is treated as reachable by the UI, because a `String` on a
/// state object is exactly what widgets render: every leak this repo has
/// actually shipped travelled that way.
///
/// ## Known limits, so nobody reads this gate as total coverage
///
/// It is textual. An exception assigned to a local first (`final m = '$error';`
/// then `error: m`) is caught, but one laundered through a helper
/// (`error: _describe(error)`) is not; nor is a non-standard catch variable
/// name outside the list below; nor is `error` passed as a bare argument to
/// something whose parameter is a `String`. Those need types, which is what
/// `ApiFailure` and the named-kind states are for — this gate stops the
/// regression, it does not prove the absence of the class.
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/dart_source.dart';

/// Form 1, matched against the *contents of string literals only*
/// ([stringLiteralsOnly]).
///
/// Any identifier *ending* in error/exception/failure counts, on any use:
/// `${error.message}` leaks as much as `$error`, and the first thing found
/// when this rule was widened was `'{error}', '$coreError'` — the same
/// exception, laundered through a differently named local one `catch` block
/// away. `err` is spelled out because it does not end in one of those words.
///
/// The one-letter `e` is narrower — it is also the conventional name for a map
/// entry or an element, and `'${e.key}=${e.value}'` is not a failure at all —
/// so it counts only when interpolated whole, or via its own `toString()`.
const _caught = r'(?:\w*(?:[Ee]rror|[Ee]xception|[Ff]ailure)|err)';

/// Form 1, matched against the *contents of string literals only*
/// ([stringLiteralsOnly]).
final _interpolated = RegExp(
  r'\$\{?'
  '$_caught'
  r'\b'
  r'|\$\{?e(?![A-Za-z0-9_$])(?!\.(?!toString\(\)))',
);

/// Form 2, matched against code with comments and literals blanked out.
final _stringified = RegExp(
  r'\b(?:'
  '$_caught'
  r'|e)\.toString\(\)',
);

/// Statements that are allowed to carry exception text, because none of them
/// can reach a widget.
final _diagnosticStatement = RegExp(
  r'\bApiFailure\(|\bdebugPrint\(|(?<![A-Za-z0-9_$.])print\(|\blog\(|\bthrow\b',
);

/// Files under `lib/` that put a caught exception where a widget can render
/// it, mapped to the offending `path:line → source` records.
Map<String, List<String>> _offences() {
  final byFile = <String, List<String>>{};
  for (final file in libDartFiles()) {
    final source = file.readAsStringSync();
    final code = maskNonCode(source);
    final prose = stringLiteralsOnly(source);

    void record(int offset) {
      if (_diagnosticStatement.hasMatch(statementAt(code, offset))) return;
      final line = lineNumberAt(source, offset);
      (byFile[file.path] ??= []).add(
        '${file.path}:$line → ${lineAt(source, line)}',
      );
    }

    for (final match in _interpolated.allMatches(prose)) {
      record(match.start);
    }
    for (final match in _stringified.allMatches(code)) {
      record(match.start);
    }
  }
  return byFile;
}

void main() {
  // Every file that already leaks, at the moment this rule was written. The
  // migration is done when this set is empty; no new entry may be added.
  //
  // File-path granularity on purpose — line numbers drift with every unrelated
  // edit, so a line-level list would cost more to maintain than the debt it
  // tracks. Same shape as the token gates in `icon_size_discipline_test.dart`.
  const knownOffenders = <String>{
    'lib/controllers/download_controller.dart',
    'lib/main.dart',
    'lib/phonetic_analysis_ui.dart',
    'lib/player_adapter.dart',
    'lib/screens/personal_expression_screen.dart',
    'lib/screens/vocabulary_screen.dart',
    'lib/widgets/coach/coach_dashboard_screen.dart',
    'lib/widgets/flows/manual_review_flow.dart',
    'lib/widgets/flows/media_import_flows.dart',
    'lib/widgets/settings/llm_provider_settings.dart',
    'lib/widgets/settings/realtime_provider_settings.dart',
    'lib/widgets/settings/syntax_capability_settings.dart',
    'lib/widgets/vocabulary/semantic_search_dialog.dart',
  };

  test('a caught exception never reaches a user-visible string', () {
    final offenders = [
      for (final entry in _offences().entries)
        if (!knownOffenders.any(entry.key.endsWith)) ...entry.value,
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Give the failure a name the UI can speak, and hand the exception to '
          'describeApiFailure so its detail lives on ApiFailure instead of in '
          'a sentence:\n${offenders.join('\n')}',
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
          'These files are registered as known offenders but no longer put a '
          'caught exception in a user-visible string — delete them from '
          'knownOffenders.',
    );
  });
}
