/// Display hygiene for text captured from subtitles (#77 / S9 · §3.6).
///
/// A sentence pattern's source snapshot is whatever the subtitle file said, and
/// subtitle files carry their own formatting: a leading `- ` marks a speaker
/// turn in SRT, and an IME that was left in Chinese mode ends an English line
/// with a fullwidth `。`. Both reached the screen verbatim
/// (`- I need to do something。`), which is not honesty (charter P4) but
/// laziness: the stored snapshot stays immutable, only what we *render* is
/// cleaned.
///
/// Two rules, both display-only:
///
/// 1. **Leading turn markers go.** A dash at the head of a line is subtitle
///    syntax, not part of the sentence; several may stack after a merge.
/// 2. **Punctuation follows the learning language, never the UI language.**
///    AGENT.md keeps the two apart: a learner studying English sees `.` even
///    when the app is in Chinese, and a learner studying Chinese keeps `。`
///    even when the app is in English. So the decision is keyed on the
///    language the text *is in*, which for a sentence pattern is
///    `SentencePatternAssetView.language`.
///
/// Nothing here touches the learner's own writing. An attempt's
/// `response_text` is the learner's language, and rewriting a person's own
/// punctuation is a different act from cleaning a machine's residue.
library;

/// Leading markers stripped from a captured line: the dash family (ASCII
/// hyphen, the Unicode hyphens, en/em/horizontal dash, minus) plus the bullet
/// a few subtitle tools use. `*` and `>` are deliberately absent — they carry
/// meaning inside a sentence often enough that stripping them would edit
/// content rather than formatting.
const _leadingMarkers = <String>{
  '-',
  '‐', // hyphen
  '‑', // non-breaking hyphen
  '‒', // figure dash
  '–', // en dash
  '—', // em dash (破折号)
  '―', // horizontal bar
  '−', // minus sign
  '•', // bullet
};

/// Fullwidth → ASCII punctuation, applied only for a learning language that
/// does not write with fullwidth forms.
///
/// Quote marks are split on purpose: the CJK brackets 「」『』 are unambiguously
/// fullwidth punctuation, while the curly quotes “ ” ‘ ’ are ordinary English
/// typography and are left exactly as written.
const _fullwidthToAscii = <String, String>{
  '。': '.',
  '．': '.',
  '，': ',',
  '、': ',',
  '？': '?',
  '！': '!',
  '：': ':',
  '；': ';',
  '（': '(',
  '）': ')',
  '［': '[',
  '］': ']',
  '「': '"',
  '」': '"',
  '『': '"',
  '』': '"',
  '　': ' ',
};

/// Converted marks that close a clause: whitespace in front of them is dropped
/// and a single space is added behind them when a word follows immediately.
const _clauseClosers = <String>{'.', ',', '?', '!', ':', ';', ')', ']'};

/// Converted marks that open a clause — the mirror case: a space is added in
/// front of them when a word runs straight into them.
const _clauseOpeners = <String>{'(', '['};

/// Languages written with fullwidth punctuation, by base subtag. Korean is
/// absent on purpose: modern Korean typography uses the ASCII period and
/// comma, so a `。` in Korean text is the same IME residue it is in English.
const _fullwidthPunctuationLanguages = <String>{'zh', 'ja', 'yue', 'wuu', 'lzh'};

/// Whether [language] (a BCP-47-ish tag such as `zh`, `zh-Hans`, `ja_JP`)
/// writes with fullwidth punctuation, in which case punctuation is left alone.
bool usesFullwidthPunctuation(String language) {
  final base = language.split(RegExp('[-_]')).first.toLowerCase();
  return _fullwidthPunctuationLanguages.contains(base);
}

/// The display form of [raw] for a learner studying [language].
///
/// Pure and idempotent: `cleanLearningText(cleanLearningText(x)) ==
/// cleanLearningText(x)`. Returns the trimmed input unchanged when cleaning
/// would leave nothing — a line that is only dashes is odd data, and blanking
/// it would hide that rather than report it.
String cleanLearningText(String raw, {required String language}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final stripped = _stripLeadingMarkers(trimmed);
  final body = stripped.isEmpty ? trimmed : stripped;

  if (usesFullwidthPunctuation(language)) return body;
  return _normalizePunctuation(body);
}

/// Drops any run of leading turn markers and the whitespace around them, so a
/// twice-merged `— - I need…` loses both heads.
String _stripLeadingMarkers(String value) {
  var text = value.trimLeft();
  while (text.isNotEmpty && _leadingMarkers.contains(text[0])) {
    text = text.substring(1).trimLeft();
  }
  return text.trimRight();
}

/// Maps fullwidth punctuation onto its ASCII form and repairs the spacing the
/// substitution implies: a fullwidth mark carries its own advance width, so
/// `something 。yes` becomes `something. yes` rather than `something . yes`.
String _normalizePunctuation(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    final ascii = _fullwidthToAscii[char];
    if (ascii == null) {
      buffer.write(char);
      continue;
    }
    if (_clauseClosers.contains(ascii)) {
      _trimTrailingSpaces(buffer);
    } else if (_clauseOpeners.contains(ascii) && _needsSpaceBefore(buffer)) {
      buffer.write(' ');
    }
    buffer.write(ascii);
    if (!_clauseClosers.contains(ascii)) continue;
    final next = i + 1 < value.length ? value[i + 1] : null;
    if (next != null && !_isSpace(next) && !_isPunctuationAfterCloser(next)) {
      buffer.write(' ');
    }
  }
  return _collapseSpaces(buffer.toString()).trim();
}

bool _isSpace(String char) => char == ' ' || char == '\t' || char == '　';

/// Punctuation that may legitimately follow a clause closer without a space —
/// `?!`, `."`, `…)`, and the fullwidth forms that are about to become those.
bool _isPunctuationAfterCloser(String char) {
  final ascii = _fullwidthToAscii[char] ?? char;
  return _clauseClosers.contains(ascii) ||
      ascii == '"' ||
      ascii == "'" ||
      ascii == '…';
}

/// True when the text written so far ends in something a bracket should not
/// be glued to (a word, a digit, a closing mark).
bool _needsSpaceBefore(StringBuffer buffer) {
  final text = buffer.toString();
  if (text.isEmpty) return false;
  final last = text[text.length - 1];
  return !_isSpace(last) && !_clauseOpeners.contains(last);
}

void _trimTrailingSpaces(StringBuffer buffer) {
  final text = buffer.toString();
  final trimmed = text.replaceFirst(RegExp(r'[ \t　]+$'), '');
  if (trimmed.length == text.length) return;
  buffer
    ..clear()
    ..write(trimmed);
}

String _collapseSpaces(String value) => value.replaceAll(RegExp('  +'), ' ');
