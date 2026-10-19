/// Turns a media *file name* into the title a learner should read (§3.7).
///
/// The player opens local files, and a downloaded file name is a packaging
/// artefact rather than a title:
///
///     How a cell phone ban has transformed this Brooklyn middle school｜June 9, 2026 [9FFSOYLiFxc].mp4
///
/// Three of those four parts — the container extension, the provider id in
/// brackets, and the publication date the downloader appended — say nothing a
/// learner needs while watching, yet they are what survives when the header
/// ellipsises. Stripping them is presentation only: the caller keeps the raw
/// name and shows it in a tooltip, so nothing is hidden, only demoted.
///
/// The rules are deliberately conservative — a title that loses a real word is
/// worse than one that keeps a stray token, so every rule below refuses when
/// the match is ambiguous, and [displayMediaTitle] falls back to the input
/// whenever cleaning would leave nothing to read.
library;

/// Path separators, so the helper accepts a full path as readily as a name.
final _pathSeparator = RegExp(r'[\\/]');

/// A trailing container/subtitle extension: a dot, then a short run of letters
/// and digits with no space in it. The no-space rule is what keeps `Ep. 12`
/// and `Vol. 3` intact while `.mp4`, `.srt` and the `.en.vtt` pair go.
final _extension = RegExp(r'\.[A-Za-z0-9]{1,5}$');

/// A bracketed provider id — `[9FFSOYLiFxc]`. Eight characters minimum, and no
/// spaces, so an authored bracket like `[Part 2]` or `[HD]` is left alone.
final _bracketedId = RegExp(r'\[[A-Za-z0-9_-]{8,}\]');

/// Separators a downloader puts between a title and its trailing metadata,
/// including the full-width forms that show up in CJK-sourced names.
/// The hyphen is escaped because these characters are spliced straight into a
/// character class, where a bare `-` between two others reads as a range.
const _separators = r'|｜\-–—~〜·・:：/';

/// `2026-06-09`, `2026/6/9`, `2026.06.09`.
final _isoDate = RegExp(r'^\d{4}[-/.]\d{1,2}[-/.]\d{1,2}$');

/// `09-06-2026`, `6/9/2026`.
final _numericDate = RegExp(r'^\d{1,2}[-/.]\d{1,2}[-/.]\d{4}$');

/// `2026年6月9日`, `2026年6月`.
final _cjkDate = RegExp(r'^\d{4}年\d{1,2}月(\d{1,2}日)?$');

const _monthNames =
    r'(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?';

/// `June 9, 2026`, `Jun 9 2026`, `June 9th, 2026`.
final _monthFirstDate = RegExp(
  '^$_monthNames'
  r'\s+\d{1,2}(st|nd|rd|th)?,?\s+\d{4}$',
  caseSensitive: false,
);

/// `9 June 2026`, `9th Jun, 2026`.
final _dayFirstDate = RegExp(
  r'^\d{1,2}(st|nd|rd|th)?\s+'
  '$_monthNames'
  r',?\s+\d{4}$',
  caseSensitive: false,
);

/// Whether [value] reads as a complete calendar date. A bare year is not a
/// date here: a title may well end in one ("... in 2026") and losing that word
/// would change what the title says.
bool _isDate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  return _isoDate.hasMatch(trimmed) ||
      _numericDate.hasMatch(trimmed) ||
      _cjkDate.hasMatch(trimmed) ||
      _monthFirstDate.hasMatch(trimmed) ||
      _dayFirstDate.hasMatch(trimmed);
}

/// Drops the trailing extensions. Repeated so `lecture.en.vtt` loses both, and
/// guarded so the stem never becomes empty (`.hidden` keeps its name).
String _stripExtensions(String value) {
  var result = value;
  for (var pass = 0; pass < 3; pass += 1) {
    final match = _extension.firstMatch(result);
    if (match == null) break;
    final stem = result.substring(0, match.start).trim();
    if (stem.isEmpty) break;
    result = stem;
  }
  return result;
}

/// Drops a trailing date, whether it hangs off a separator (`…｜June 9, 2026`)
/// or simply off the last words (`… 2026-06-09`). Runs twice so a name
/// carrying both a written and a numeric date loses both.
String _stripTrailingDate(String value) {
  var result = value;
  for (var pass = 0; pass < 2; pass += 1) {
    final next = _stripOneTrailingDate(result);
    if (next == result) break;
    result = next;
  }
  return result;
}

String _stripOneTrailingDate(String value) {
  final trimmed = value.trimRight();

  // Separator form: everything after the last separator is metadata if it
  // reads as a date.
  final separatorIndex = trimmed.lastIndexOf(RegExp('[$_separators]'));
  if (separatorIndex > 0 && _isDate(trimmed.substring(separatorIndex + 1))) {
    return trimmed.substring(0, separatorIndex);
  }

  // Bare form: try the last three, two, then one whitespace-separated tokens,
  // longest first, so `9 June 2026` is recognised before `2026` alone is
  // considered (and rejected).
  final words = trimmed.split(RegExp(r'\s+'));
  for (var take = 3; take >= 1; take -= 1) {
    if (words.length <= take) continue;
    final tail = words.sublist(words.length - take).join(' ');
    if (_isDate(tail)) {
      return words.sublist(0, words.length - take).join(' ');
    }
  }
  return value;
}

/// Trims separators and whitespace left dangling once metadata is removed, and
/// collapses runs of whitespace so the result reads as one line.
String _tidy(String value) => value
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp('^[$_separators\\s]+'), '')
    .replaceAll(RegExp('[$_separators\\s]+\$'), '')
    .trim();

/// The reading title for [fileNameOrPath].
///
/// Returns the input's own file name unchanged when there is nothing to strip,
/// and — importantly — also when stripping would leave the title empty: a name
/// that is *only* an id (`[9FFSOYLiFxc].mp4`) still has to be identifiable, so
/// it keeps its raw form rather than becoming a blank header.
String displayMediaTitle(String fileNameOrPath) {
  final name = fileNameOrPath.split(_pathSeparator).last.trim();
  if (name.isEmpty) return fileNameOrPath.trim();

  var result = _stripExtensions(name);
  result = result.replaceAll(_bracketedId, ' ');
  result = _tidy(result);
  result = _tidy(_stripTrailingDate(result));

  return result.isEmpty ? name : result;
}
