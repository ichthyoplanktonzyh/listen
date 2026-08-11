import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// Upper bound for both file and pasted-text intake, in UTF-8 bytes.
const int maxDocumentBytes = 1 << 20;

/// Typed intake failure kinds. Each maps one-to-one onto a session failure
/// kind; the mapping lives in the controller because models must not depend
/// on services.
enum DocumentIntakeFailureKind {
  tooLarge,
  invalidUtf8,
  emptyDocument,
  unreadable,
}

/// A typed intake failure ([DocumentIntakeCodec] rejects, or the file service
/// could not read).
final class DocumentIntakeFailure implements Exception {
  const DocumentIntakeFailure(this.kind);

  final DocumentIntakeFailureKind kind;
}

/// A validated document: [title] for the material, [text] exactly as the
/// source carried it (BOM removed, newlines and trailing spaces preserved;
/// never stored trimmed).
final class DocumentIntakeInput {
  const DocumentIntakeInput({required this.title, required this.text});

  final String title;
  final String text;
}

/// Pure byte-to-document validation. No platform I/O, so every rule — BOM,
/// strict UTF-8, the 1 MiB limit, whitespace-only rejection — is unit-testable
/// against raw bytes.
abstract interface class DocumentIntakeCodec {
  /// Decodes [bytes] into a validated document. Throws
  /// [DocumentIntakeFailure] for too-large, invalid UTF-8, or empty input.
  DocumentIntakeInput decodeDocumentText({
    required List<int> bytes,
    required String title,
  });
}

final class LocalDocumentIntakeCodec implements DocumentIntakeCodec {
  const LocalDocumentIntakeCodec();

  @override
  DocumentIntakeInput decodeDocumentText({
    required List<int> bytes,
    required String title,
  }) {
    if (bytes.length > maxDocumentBytes) {
      throw const DocumentIntakeFailure(DocumentIntakeFailureKind.tooLarge);
    }
    var data = bytes;
    // One UTF-8 BOM is stripped; nothing else is touched.
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      data = data.sublist(3);
    }
    late String text;
    try {
      text = utf8.decode(data, allowMalformed: false);
    } on FormatException {
      throw const DocumentIntakeFailure(DocumentIntakeFailureKind.invalidUtf8);
    }
    // Whitespace-only check only — the stored text keeps its exact bytes.
    if (text.trim().isEmpty) {
      throw const DocumentIntakeFailure(
        DocumentIntakeFailureKind.emptyDocument,
      );
    }
    return DocumentIntakeInput(title: title, text: text);
  }
}

/// The title a picked file contributes: its basename with one trailing `.txt`
/// suffix removed.
String titleFromFileName(String basename) {
  if (basename.toLowerCase().endsWith('.txt')) {
    return basename.substring(0, basename.length - 4);
  }
  return basename;
}

/// Outcome of a picker round-trip. A cancelled picker is a normal result:
/// the session stays idle, shows no error, and creates no material.
///
/// Abstract, not sealed, so tests may define their own gate subclasses.
abstract class DocumentFileRead {
  const DocumentFileRead();
}

final class DocumentFileCancelled extends DocumentFileRead {
  const DocumentFileCancelled();
}

final class DocumentFileData extends DocumentFileRead {
  const DocumentFileData({required this.path, required this.bytes});

  /// The picked file's location. The intake path uses it only to derive the
  /// title; it is never written into UI, models, logs, or failure prose.
  final String path;
  final List<int> bytes;
}

final class DocumentFileFailure extends DocumentFileRead {
  const DocumentFileFailure(this.failure);

  final DocumentIntakeFailure failure;
}

/// The platform half of file intake: pick a `.txt` file, and read it only
/// after its length passed the 1 MiB cap.
abstract interface class DocumentIntakeFileService {
  Future<DocumentFileRead> pickAndReadTextFile();

  String basename(String path);
}

final class LocalDocumentIntakeFileService
    implements DocumentIntakeFileService {
  const LocalDocumentIntakeFileService();

  @override
  Future<DocumentFileRead> pickAndReadTextFile() async {
    const group = XTypeGroup(label: 'text', extensions: ['txt']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return const DocumentFileCancelled();
    try {
      final length = await file.length();
      if (length > maxDocumentBytes) {
        return const DocumentFileFailure(
          DocumentIntakeFailure(DocumentIntakeFailureKind.tooLarge),
        );
      }
      final bytes = await file.readAsBytes();
      return DocumentFileData(path: file.path, bytes: bytes);
    } on FileSystemException {
      return const DocumentFileFailure(
        DocumentIntakeFailure(DocumentIntakeFailureKind.unreadable),
      );
    }
  }

  @override
  String basename(String path) => path.split(Platform.pathSeparator).last;
}
