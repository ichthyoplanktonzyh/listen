import 'dart:io';

/// Shared scanning support for the design-token discipline gates
/// (`icon_size_discipline_test.dart`, `spacing_discipline_test.dart`,
/// `typography_slot_discipline_test.dart`,
/// `column_width_discipline_test.dart`).
///
/// The gates originally matched line by line, which silently exempted every
/// call `dart format` had wrapped — and wrapping is driven by argument count,
/// so exactly the busiest, most drift-prone call sites escaped. Matching over
/// the whole file fixes that, but only if the scan can still tell code from
/// commentary: a doc comment that quotes the forbidden form must not count,
/// and neither must a string literal that happens to contain one.
///
/// [maskNonCode] is that separation. Everything else here exists so a
/// whole-file match can still report a `path:line` the way the line-based
/// gates did.

/// Every `.dart` file under `lib/`, in directory order.
Iterable<File> libDartFiles() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

/// Replaces the contents of comments and string literals with spaces, leaving
/// every other character — and every newline — exactly where it was.
///
/// The result is the same length as [source] and has the same line structure,
/// so a match offset in the masked text maps straight back onto the original
/// via [lineNumberAt] and [lineAt]. Blanking rather than deleting is what
/// makes that possible.
///
/// Masking string literals matters as much as masking comments: it keeps a
/// `//` inside a URL from swallowing the rest of its line, and keeps any
/// parenthesis inside a string (including one in a `${…}` interpolation) from
/// unbalancing the paren-counting the gates rely on.
String maskNonCode(String source) {
  final out = StringBuffer();
  var i = 0;

  void blank(int count) {
    for (var n = 0; n < count; n++) {
      out.write(source[i + n] == '\n' ? '\n' : ' ');
    }
    i += count;
  }

  bool startsWith(String text, int at) =>
      at + text.length <= source.length && source.startsWith(text, at);

  while (i < source.length) {
    final char = source[i];

    if (startsWith('//', i)) {
      var end = source.indexOf('\n', i);
      if (end < 0) end = source.length;
      blank(end - i);
      continue;
    }

    if (startsWith('/*', i)) {
      var end = source.indexOf('*/', i + 2);
      end = end < 0 ? source.length : end + 2;
      blank(end - i);
      continue;
    }

    if (char == "'" || char == '"') {
      // A raw string disables backslash escapes; the `r` has already been
      // written out as ordinary code, so look back for it.
      final raw =
          i > 0 &&
          source[i - 1] == 'r' &&
          (i < 2 || !RegExp(r'[A-Za-z0-9_$]').hasMatch(source[i - 2]));
      final quote = startsWith(char * 3, i) ? char * 3 : char;

      out.write(quote);
      i += quote.length;
      while (i < source.length) {
        if (!raw && source[i] == r'\' && i + 1 < source.length) {
          blank(2);
          continue;
        }
        if (startsWith(quote, i)) break;
        blank(1);
      }
      if (i < source.length) {
        out.write(quote);
        i += quote.length;
      }
      continue;
    }

    out.write(char);
    i++;
  }

  return out.toString();
}

/// The 1-based line number containing [offset].
int lineNumberAt(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < source.length; i++) {
    if (source[i] == '\n') line++;
  }
  return line;
}

/// The trimmed text of the 1-based [line] of [source], for offender records.
/// A wrapped call is reported at the line it starts on.
String lineAt(String source, int line) {
  final lines = source.split('\n');
  return line <= lines.length ? lines[line - 1].trim() : '';
}

/// One character of an argument list, or one whole parenthesised group nested
/// inside it — balanced up to two levels. Repeat it (`'$balancedArgUnit*?'`)
/// to walk an argument list without ever crossing the closing paren of the
/// call it started in: the unit matches no unbalanced `)`, so the repetition
/// stops there on its own. That bound is what lets these gates match across
/// the line breaks `dart format` inserts without one call's match spilling
/// into the next.
///
/// Two levels covers real call sites (`Icon(_iconFor(state), size: 18)` and
/// `Icon(_iconFor(state.copyWith(x)), size: 18)`); a third level of nesting
/// before the argument being matched is rare enough to accept as a miss.
const balancedArgUnit = r'(?:[^()]|\((?:[^()]|\([^()]*\))*\))';
