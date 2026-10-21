import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../utils/word_list_parser.dart';

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
