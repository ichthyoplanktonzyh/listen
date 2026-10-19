/// Typed envelope for the vocabulary transfer document.
///
/// The document is intentionally open-ended: newer cores may add fields that
/// an older client must preserve when it writes the export to disk. Known
/// metadata has typed accessors, while [toJson] returns the complete original
/// document, including unknown extensions.
class VocabularyExportBundle {
  VocabularyExportBundle._(Map<String, Object?> document)
    : _document = Map.unmodifiable(document);

  factory VocabularyExportBundle.fromJson(Map<String, dynamic> json) =>
      VocabularyExportBundle._(Map<String, Object?>.from(json));

  final Map<String, Object?> _document;

  int? get version => (_document['version'] as num?)?.toInt();
  int? get exportedAtMs => (_document['exported_at_ms'] as num?)?.toInt();

  List<Object?> get lexicalEntries {
    final entries = _document['lexical_entries'];
    return entries is List<Object?> ? List.unmodifiable(entries) : const [];
  }

  Object? operator [](String key) => _document[key];

  Map<String, Object?> toJson() => Map.unmodifiable(_document);
}
