import 'dart:convert';

import 'package:csv/csv.dart';

/// Parse a plain-text (one word per line) or CSV word list.
///
/// Plain text: each non-empty line becomes `{'word': line, 'status': null}`.
/// CSV: must contain a `word` column; optional `status` column is validated
/// against the known statuses.
List<Map<String, dynamic>> parseExternalWordList(
  String content, {
  required bool csv,
}) {
  if (!csv) {
    return const LineSplitter()
        .convert(content)
        .where((line) => line.trim().isNotEmpty)
        .map((line) => <String, dynamic>{'word': line.trim(), 'status': null})
        .toList(growable: false);
  }
  final rows = const CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  ).convert(content.replaceAll('\r\n', '\n'));
  if (rows.isEmpty) return const [];
  final headers = rows.first
      .map((value) => value.toString().trim().toLowerCase())
      .toList();
  final wordIndex = headers.indexOf('word');
  final statusIndex = headers.indexOf('status');
  if (wordIndex < 0) {
    throw const FormatException('CSV must contain a word column');
  }
  const statuses = {
    'unknown_meaning',
    'known_not_recognized',
    'known_recognized',
  };
  return rows
      .skip(1)
      .where((row) => wordIndex < row.length)
      .map((row) {
        final importedStatus = statusIndex >= 0 && statusIndex < row.length
            ? row[statusIndex].toString().trim()
            : '';
        return <String, dynamic>{
          'word': row[wordIndex].toString(),
          'status': statuses.contains(importedStatus) ? importedStatus : null,
        };
      })
      .toList(growable: false);
}
