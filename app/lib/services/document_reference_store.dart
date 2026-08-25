import 'dart:convert';
import 'dart:io';

/// The App-owned mapping from Source Asset reference keys (the asset's
/// lowercase SHA-256 digest) to the original file locations the learner chose
/// to Reference in Place.
///
/// Core stores only the opaque reference key and never dereferences it; this
/// file is the App's own side table, kept out of every model and wire DTO. The
/// mapping is content-addressed: the same bytes resolve to the same key, and
/// the App can always recompute the key from the digest it already knows.
class DocumentReferenceStore {
  DocumentReferenceStore({required this.file});

  /// The persisted mapping file (Application Support/document-references.json
  /// in production).
  final File file;

  static File fileFor(String supportPath) => File(
    '$supportPath${Platform.pathSeparator}document-references.json',
  );

  /// The recorded original location for [referenceKey], or null when unknown.
  Future<String?> resolve(String referenceKey) async {
    final map = await _read();
    return map[referenceKey];
  }

  /// Records (or updates) the original location for [referenceKey]. The
  /// stored value is a location, never a wire field.
  Future<void> save(String referenceKey, String path) async {
    final map = await _read();
    map[referenceKey] = path;
    await _write(map);
  }

  /// Drops the mapping for [referenceKey]. Kept for a future explicit
  /// "stop referencing" intent; the direct view never calls it.
  Future<void> remove(String referenceKey) async {
    final map = await _read();
    if (map.remove(referenceKey) == null) return;
    await _write(map);
  }

  Future<Map<String, String>> _read() async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return <String, String>{};
      final map = <String, String>{};
      for (final entry in decoded.entries) {
        if (entry.value is String) {
          map[entry.key as String] = entry.value as String;
        }
      }
      return map;
    } on FileSystemException {
      return <String, String>{};
    } on FormatException {
      // A corrupt side table is treated as empty; it is never a crash or a
      // wire-facing failure.
      return <String, String>{};
    }
  }

  Future<void> _write(Map<String, String> map) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(map), flush: true);
  }
}
