import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';

import 'document_decoding/document_format.dart';
import 'document_decoding/epub_decoder.dart';

/// Typed intake failure kinds. Each maps one-to-one onto a session failure
/// kind; the mapping lives in the controller because models must not depend
/// on services.
enum DocumentIntakeFailureKind {
  tooLarge,
  invalidUtf8,
  emptyDocument,
  unreadable,
  unsupported,
  corrupt,
  encrypted,
}

/// A typed intake failure ([DocumentIntakeCodec] rejects, or the file service
/// could not read).
final class DocumentIntakeFailure implements Exception {
  const DocumentIntakeFailure(this.kind);

  final DocumentIntakeFailureKind kind;
}

/// A validated document: [title] for the material, the exact byte facts of
/// the original source, and — when the format carries a readable text
/// representation — that text exactly as the source carried or extracted it.
/// [text] is null only when the source has no text layer (e.g. a scanned
/// PDF); the material then carries its Source Asset alone.
final class DocumentIntakeInput {
  const DocumentIntakeInput({
    required this.title,
    required this.mediaType,
    required this.byteLength,
    required this.sha256Digest,
    required this.format,
    this.text,
  });

  final String title;

  /// The source's media type, used for both the Source Asset and (when
  /// [text] is present) the Document Rendition.
  final String mediaType;

  /// Exact byte facts of the original source, for the Source Asset binding.
  final int byteLength;
  final String sha256Digest;
  final DocumentFormat format;

  /// The readable inline text, or null when the format carries no text layer.
  final String? text;
}

/// Pure byte-to-document validation and decoding. No platform I/O, so every
/// rule — BOM, strict UTF-8, size limits, ZIP/PDF container facts — is
/// unit-testable against raw bytes. PDF text-layer extraction is the one
/// platform-dependent step and is injected (see [PdfTextExtractor]).
abstract interface class DocumentIntakeCodec {
  Future<DocumentIntakeInput> decodeDocument({
    required List<int> bytes,
    required String title,
    required DocumentFormat format,
  });
}

/// Extracts the text layer of a PDF, or null when the PDF is scanned and has
/// no extractable text. Platform-dependent (pdfium); tests inject a fake.
abstract interface class PdfTextExtractor {
  Future<String?> extractText(List<int> bytes);
}

final class LocalDocumentIntakeCodec implements DocumentIntakeCodec {
  LocalDocumentIntakeCodec({PdfTextExtractor? pdfTextExtractor})
    : _pdfTextExtractor = pdfTextExtractor ?? const _NoopPdfTextExtractor();

  final PdfTextExtractor _pdfTextExtractor;

  @override
  Future<DocumentIntakeInput> decodeDocument({
    required List<int> bytes,
    required String title,
    required DocumentFormat format,
  }) async {
    final limit = maxDocumentBytesFor(format);
    if (bytes.length > limit) {
      throw DocumentIntakeFailure(DocumentIntakeFailureKind.tooLarge);
    }
    final mediaType = mediaTypeOf(format);
    return switch (format) {
      DocumentFormat.plainText ||
      DocumentFormat.markdown =>
        _decodeText(bytes, title, mediaType, format),
      DocumentFormat.html => _decodeHtml(bytes, title, mediaType),
      DocumentFormat.epub => _decodeEpub(bytes, title, mediaType),
      DocumentFormat.pdf => await _decodePdf(bytes, title, mediaType),
    };
  }

  static DocumentIntakeInput _decodeText(
    List<int> bytes,
    String title,
    String mediaType,
    DocumentFormat format,
  ) {
    final text = _decodeUtf8Strict(bytes);
    if (text.trim().isEmpty) {
      throw const DocumentIntakeFailure(DocumentIntakeFailureKind.emptyDocument);
    }
    return _input(title, mediaType, bytes, format, text: text);
  }

  static DocumentIntakeInput _decodeHtml(
    List<int> bytes,
    String title,
    String mediaType,
  ) {
    final text = _decodeUtf8Strict(bytes);
    // HTML with only markup is an empty document; the stored text stays the
    // exact source bytes.
    if (htmlToPlainText(text).trim().isEmpty) {
      throw const DocumentIntakeFailure(DocumentIntakeFailureKind.emptyDocument);
    }
    return _input(
      title,
      mediaType,
      bytes,
      DocumentFormat.html,
      text: text,
    );
  }

  static DocumentIntakeInput _decodeEpub(
    List<int> bytes,
    String title,
    String mediaType,
  ) {
    final EpubDocument document;
    try {
      document = const EpubDecoder().decode(bytes);
    } on EpubDecodeFailure {
      throw const DocumentIntakeFailure(DocumentIntakeFailureKind.corrupt);
    }
    final text = EpubDecoder.spineText(document);
    if (text.trim().isEmpty) {
      throw const DocumentIntakeFailure(DocumentIntakeFailureKind.emptyDocument);
    }
    return _input(title, mediaType, bytes, DocumentFormat.epub, text: text);
  }

  Future<DocumentIntakeInput> _decodePdf(
    List<int> bytes,
    String title,
    String mediaType,
  ) async {
    final header = _pdfHeader(bytes);
    if (header == null) {
      throw const DocumentIntakeFailure(DocumentIntakeFailureKind.corrupt);
    }
    // `%%EOF` marker within the final kilobyte; PDFs may carry trailing
    // whitespace or a damaged xref trailer appended after it.
    final tailStart = bytes.length > 1024 ? bytes.length - 1024 : 0;
    final tail = String.fromCharCodes(bytes.sublist(tailStart));
    if (!tail.contains('%%EOF')) {
      throw const DocumentIntakeFailure(DocumentIntakeFailureKind.corrupt);
    }
    if (_contains(bytes, '/Encrypt')) {
      throw const DocumentIntakeFailure(DocumentIntakeFailureKind.encrypted);
    }
    final text = await _pdfTextExtractor.extractText(bytes);
    return _input(title, mediaType, bytes, DocumentFormat.pdf, text: text);
  }

  static DocumentIntakeInput _input(
    String title,
    String mediaType,
    List<int> bytes,
    DocumentFormat format, {
    String? text,
  }) => DocumentIntakeInput(
    title: title,
    mediaType: mediaType,
    byteLength: bytes.length,
    sha256Digest: sha256.convert(bytes).toString(),
    format: format,
    text: text,
  );

  /// One UTF-8 BOM is stripped; everything else is kept exactly.
  static String _decodeUtf8Strict(List<int> bytes) {
    var data = bytes;
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      data = data.sublist(3);
    }
    try {
      return utf8.decode(data, allowMalformed: false);
    } on FormatException {
      throw const DocumentIntakeFailure(DocumentIntakeFailureKind.invalidUtf8);
    }
  }

  /// The `%PDF-x.y` header, or null when the bytes are not a PDF.
  static String? _pdfHeader(List<int> bytes) {
    if (bytes.length < 8) return null;
    final header = String.fromCharCodes(bytes.sublist(0, 8));
    if (!header.startsWith('%PDF-')) return null;
    final version = header.substring(5);
    final match = RegExp(r'^(\d)\.(\d)$').firstMatch(version);
    if (match == null) return null;
    final major = int.parse(match.group(1)!);
    if (major < 1 || major > 2) return null;
    return version;
  }

  static bool _contains(List<int> bytes, String needle) {
    final ascii = String.fromCharCodes(bytes.take(1 << 20));
    return ascii.contains(needle);
  }
}

/// Default PDF text extractor that reports no text layer. The real pdfium
/// extractor (PdfRxPdfTextExtractor) is wired at the composition root; this
/// keeps the codec pure and deterministic in tests.
final class _NoopPdfTextExtractor implements PdfTextExtractor {
  const _NoopPdfTextExtractor();

  @override
  Future<String?> extractText(List<int> bytes) async => null;
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
  /// title and declared format; it is never written into UI, models, logs, or
  /// failure prose.
  final String path;
  final List<int> bytes;
}

final class DocumentFileFailure extends DocumentFileRead {
  const DocumentFileFailure(this.failure);

  final DocumentIntakeFailure failure;
}

/// The platform half of file intake: pick a supported document file, and read
/// it only after its length passed the format's cap.
abstract interface class DocumentIntakeFileService {
  Future<DocumentFileRead> pickAndReadDocumentFile();

  /// Reads an already-known document file (e.g. a downloaded article page),
  /// with the same size cap and the same typed read failures as the picker
  /// path. A path with no supported extension fails as unsupported.
  Future<DocumentFileRead> readDocumentFile(String path);

  String basename(String path);
}

final class LocalDocumentIntakeFileService
    implements DocumentIntakeFileService {
  const LocalDocumentIntakeFileService();

  @override
  Future<DocumentFileRead> pickAndReadDocumentFile() async {
    const group = XTypeGroup(
      label: 'documents',
      extensions: [
        'txt',
        'md',
        'markdown',
        'html',
        'htm',
        'epub',
        'pdf',
      ],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return const DocumentFileCancelled();
    return _read(file.path, file.length, file.readAsBytes);
  }

  @override
  Future<DocumentFileRead> readDocumentFile(String path) async {
    if (!File(path).existsSync()) {
      return const DocumentFileFailure(
        DocumentIntakeFailure(DocumentIntakeFailureKind.unreadable),
      );
    }
    return _read(
      path,
      () => File(path).length(),
      () => File(path).readAsBytes(),
    );
  }

  Future<DocumentFileRead> _read(
    String path,
    Future<int> Function() length,
    Future<List<int>> Function() readAsBytes,
  ) async {
    try {
      final format = formatForPath(path);
      final limit = format == null
          ? maxTextDocumentBytes
          : maxDocumentBytesFor(format);
      final size = await length();
      if (size > limit) {
        return const DocumentFileFailure(
          DocumentIntakeFailure(DocumentIntakeFailureKind.tooLarge),
        );
      }
      final bytes = await readAsBytes();
      return DocumentFileData(path: path, bytes: bytes);
    } on FileSystemException {
      return const DocumentFileFailure(
        DocumentIntakeFailure(DocumentIntakeFailureKind.unreadable),
      );
    }
  }

  @override
  String basename(String path) => path.split(Platform.pathSeparator).last;
}
