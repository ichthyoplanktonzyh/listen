/// File-family vocabulary for the supported Phase 1 document formats.
///
/// Pure and platform-free: extension dispatch, title derivation, and size
/// bounds. The format vocabulary itself lives in the domain models
/// (`lib/models/document_format.dart`).
library;

import '../../models/document_format.dart';

export '../../models/document_format.dart'
    show DocumentFormat, formatFromMediaType, mediaTypeOf;

/// Recognized file extensions, without the leading dot, longest first so
/// `.markdown` wins over `.md`-style prefixes (none overlap today).
const List<String> documentFormatExtensions = [
  'markdown',
  'epub',
  'txt',
  'md',
  'html',
  'htm',
  'pdf',
];

/// The format a picked file path declares through its extension, or null for
/// an unsupported extension. The declared format is later verified against the
/// bytes by the intake codec — the extension is a hint, never authority.
DocumentFormat? formatForPath(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  return formatForExtension(name.substring(dot + 1));
}

DocumentFormat? formatForExtension(String extension) =>
    switch (extension.toLowerCase()) {
      'txt' => DocumentFormat.plainText,
      'md' => DocumentFormat.markdown,
      'markdown' => DocumentFormat.markdown,
      'html' || 'htm' => DocumentFormat.html,
      'epub' => DocumentFormat.epub,
      'pdf' => DocumentFormat.pdf,
      _ => null,
    };

/// The title a picked file contributes: its basename with one trailing
/// recognized extension removed. A basename that is only an extension (e.g.
/// `.txt`) keeps it, so the caller can still reject an empty title.
String titleFromFileName(String basename) {
  final lower = basename.toLowerCase();
  for (final extension in documentFormatExtensions) {
    final suffix = '.$extension';
    if (lower.endsWith(suffix)) {
      return basename.substring(0, basename.length - suffix.length);
    }
  }
  return basename;
}

/// Upper bounds, in bytes, for source intake.
///
/// Text families stay at the historical 1 MiB plain-text reading bound.
/// Container families (EPUB/PDF) are allowed 64 MiB because their bytes are
/// preserved for the renderer rather than inlined as text.
const int maxTextDocumentBytes = 1 << 20;
const int maxContainerDocumentBytes = 1 << 26;

int maxDocumentBytesFor(DocumentFormat format) => switch (format) {
  DocumentFormat.plainText ||
  DocumentFormat.markdown ||
  DocumentFormat.html => maxTextDocumentBytes,
  DocumentFormat.epub || DocumentFormat.pdf => maxContainerDocumentBytes,
};
