/// The supported Phase 1 document family.
///
/// Pure and platform-free: the format vocabulary and its media-type mapping
/// are domain facts; extension dispatch, title derivation, and size bounds
/// live in `lib/services/document_decoding/document_format.dart`.
enum DocumentFormat { plainText, markdown, html, epub, pdf }

/// The format a stored media type declares, or null for a type outside the
/// supported family.
DocumentFormat? formatFromMediaType(String mediaType) => switch (mediaType) {
  'text/plain' => DocumentFormat.plainText,
  'text/markdown' => DocumentFormat.markdown,
  'text/html' => DocumentFormat.html,
  'application/epub+zip' => DocumentFormat.epub,
  'application/pdf' => DocumentFormat.pdf,
  _ => null,
};

/// The media type used for both the Source Asset and (where applicable) the
/// Document Rendition of a [DocumentFormat].
String mediaTypeOf(DocumentFormat format) => switch (format) {
  DocumentFormat.plainText => 'text/plain',
  DocumentFormat.markdown => 'text/markdown',
  DocumentFormat.html => 'text/html',
  DocumentFormat.epub => 'application/epub+zip',
  DocumentFormat.pdf => 'application/pdf',
};
