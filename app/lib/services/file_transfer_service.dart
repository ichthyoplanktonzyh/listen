import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../utils/word_list_parser.dart';

/// Persists a personal-expression export document to a user-selected path.
///
/// Path selection remains a presentation concern. Encoding and file-system
/// access live behind this boundary so views can use a test double.
abstract interface class PersonalExpressionExportFileService {
  Future<String?> write({
    required String suggestedName,
    required Map<String, dynamic> document,
  });
}

final class LocalPersonalExpressionExportFileService
    implements PersonalExpressionExportFileService {
  const LocalPersonalExpressionExportFileService();

  @override
  Future<String?> write({
    required String suggestedName,
    required Map<String, dynamic> document,
  }) async {
    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location == null) return null;
    await File(
      location.path,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(document));
    return location.path;
  }

  Future<void> writeToPath({
    required String path,
    required Map<String, dynamic> document,
  }) => File(
    path,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(document));
}

/// The result of loading and parsing one external vocabulary file.
sealed class ExternalWordListReadResult {
  const ExternalWordListReadResult();
}

final class ExternalWordListReadSuccess extends ExternalWordListReadResult {
  ExternalWordListReadSuccess(Iterable<Map<String, dynamic>> entries)
    : entries = List.unmodifiable(
        entries.map(Map<String, dynamic>.unmodifiable),
      );

  final List<Map<String, dynamic>> entries;
}

final class ExternalWordListFormatFailure extends ExternalWordListReadResult {
  const ExternalWordListFormatFailure(this.message);

  final String message;
}

/// Loads and parses a word list selected by the presentation layer.
abstract interface class ExternalWordListFileService {
  Future<ExternalWordListReadResult?> pickAndRead();

  Future<ExternalWordListReadResult> read(String path);
}

final class LocalExternalWordListFileService
    implements ExternalWordListFileService {
  const LocalExternalWordListFileService();

  @override
  Future<ExternalWordListReadResult?> pickAndRead() async {
    const group = XTypeGroup(label: 'word list', extensions: ['txt', 'csv']);
    final file = await openFile(acceptedTypeGroups: [group]);
    return file == null ? null : read(file.path);
  }

  @override
  Future<ExternalWordListReadResult> read(String path) async {
    final content = await File(path).readAsString();
    try {
      return ExternalWordListReadSuccess(
        parseExternalWordList(
          content,
          csv: path.toLowerCase().endsWith('.csv'),
        ),
      );
    } on FormatException catch (error) {
      return ExternalWordListFormatFailure(error.message);
    }
  }
}
