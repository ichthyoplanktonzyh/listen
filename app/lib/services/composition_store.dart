import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// One sentence of the adopted composition's reading structure, with its
/// character offsets into the document text.
class CompositionSentence {
  const CompositionSentence({
    required this.id,
    required this.index,
    required this.text,
    required this.startChar,
    required this.endChar,
  });

  final String id;
  final int index;
  final String text;
  final int startChar;
  final int endChar;
}

/// One anchor of the structured reading: a block or a sentence, addressed by
/// byte offsets into the document text.
class CompositionAnchor {
  const CompositionAnchor({
    required this.anchorId,
    required this.kind,
    required this.startOffset,
    required this.endOffset,
  });

  final String anchorId;

  /// 'block' | 'sentence'.
  final String kind;
  final int startOffset;
  final int endOffset;
}

/// The learner-facing content of one adopted Composition: the exact derived
/// reading structure, its audio (when the composition carries a derived media
/// rendition), and the anchor-to-time alignment.
class ResolvedComposition {
  ResolvedComposition({
    required this.releaseId,
    required this.documentText,
    required List<CompositionSentence> sentences,
    required List<CompositionAnchor> anchors,
    required this.alignments,
    this.derivedMediaPath,
  }) : _sentences = List.unmodifiable(sentences),
       _anchors = List.unmodifiable(anchors);

  final String releaseId;
  final String documentText;
  final List<CompositionSentence> _sentences;
  List<CompositionSentence> get sentences => List.unmodifiable(_sentences);
  final List<CompositionAnchor> _anchors;
  List<CompositionAnchor> get anchors => List.unmodifiable(_anchors);

  /// anchor id → media time in milliseconds.
  final Map<String, int> alignments;

  /// Local path of the extracted derived audio, when the composition carries
  /// one.
  final String? derivedMediaPath;
}

/// Owns the retained Content Package v3 carriers for adopted compositions and
/// resolves their learner content. Carriers are stored under the app's data
/// directory, keyed by material and release id, and are never treated as
/// sources of truth for adoption — the Core adoption record is.
final class CompositionStore {
  CompositionStore({String? root}) : _root = root ?? _defaultRoot();

  final String _root;

  static String _defaultRoot() {
    final home = Platform.environment['HOME'] ?? '.';
    return '$home/Library/Application Support/listen/compositions';
  }

  String _carrierPath(String materialId, String releaseId) =>
      '$_root$Platform.pathSeparator$materialId$Platform.pathSeparator$releaseId.zip';

  bool hasCarrier(String materialId, String releaseId) =>
      File(_carrierPath(materialId, releaseId)).existsSync();

  /// Retains the produced carrier next to the adopted composition. The Gen
  /// staging directory is caller-owned; the carrier here is the app's copy.
  Future<void> save({
    required String materialId,
    required String releaseId,
    required String packagePath,
  }) async {
    final directory = Directory(
      '$_root$Platform.pathSeparator$materialId',
    );
    await directory.create(recursive: true);
    final target = File(_carrierPath(materialId, releaseId));
    await File(packagePath).copy(target.path);
  }

  /// Resolves the adopted composition's learner content from the retained
  /// carrier, or null when no carrier is retained.
  Future<ResolvedComposition?> resolve({
    required String materialId,
    required String releaseId,
  }) async {
    final file = File(_carrierPath(materialId, releaseId));
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return _parseCarrier(bytes, releaseId);
  }

  /// Parses one Content Package v3 carrier into its learner content. Pure
  /// over bytes so tests can drive it without the store.
  static ResolvedComposition _parseCarrier(List<int> bytes, String releaseId) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entries = <String, List<int>>{
      for (final file in archive.files)
        if (file.isFile) file.name: file.content as List<int>,
    };
    final releaseJson = entries['release.json'];
    if (releaseJson == null) {
      throw const FormatException('content package is missing release.json');
    }
    final release = jsonDecode(utf8.decode(releaseJson)) as Map<String, dynamic>;
    final resources = (release['resources'] as List<dynamic>? ?? const [])
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList(growable: false);
    final mediaRenditions =
        (release['media_renditions'] as List<dynamic>? ?? const [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList(growable: false);

    String? documentText;
    final segments = <Map<String, dynamic>>[];
    var anchors = <Map<String, dynamic>>[];
    final alignments = <String, int>{};
    String? derivedMediaPath;

    for (final resource in resources) {
      final descriptor = Map<String, dynamic>.from(
        resource['descriptor'] as Map,
      );
      final kind = descriptor['kind'] as String;
      final payloadBlob = Map<String, dynamic>.from(
        descriptor['payload_blob'] as Map,
      );
      final payload = _readBlob(entries, payloadBlob);
      switch (kind) {
        case 'document_text':
          final decoded = payload == null
              ? null
              : jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
          if (decoded != null) {
            documentText = decoded['text'] as String;
            segments.addAll(
              (decoded['segments'] as List<dynamic>).map(
                (value) => Map<String, dynamic>.from(value as Map),
              ),
            );
          }
        case 'structured_reading':
          final decoded = payload == null
              ? null
              : jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
          if (decoded != null) {
            anchors = (decoded['anchors'] as List<dynamic>)
                .map((value) => Map<String, dynamic>.from(value as Map))
                .toList(growable: false);
          }
        case 'anchor_time_alignment':
          final decoded = payload == null
              ? null
              : jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
          if (decoded != null) {
            for (final entry
                in (decoded['alignments'] as List<dynamic>? ?? const [])) {
              final map = Map<String, dynamic>.from(entry as Map);
              alignments[map['anchor_id'] as String] =
                  map['media_time_ms'] as int;
            }
          }
      }
    }

    final text = documentText ?? '';
    final sentences = <CompositionSentence>[
      for (final segment in segments)
        CompositionSentence(
          id: segment['id'] as String,
          index: segment['index'] as int,
          text: _slice(text, segment['start_char'] as int, segment['end_char'] as int),
          startChar: segment['start_char'] as int,
          endChar: segment['end_char'] as int,
        ),
    ];
    final parsedAnchors = <CompositionAnchor>[
      for (final anchor in anchors)
        CompositionAnchor(
          anchorId: anchor['anchor_id'] as String,
          kind: anchor['kind'] as String,
          startOffset: anchor['start_offset'] as int,
          endOffset: anchor['end_offset'] as int,
        ),
    ];

    // A derived audio rendition's embedded blob is extracted so the player
    // can play the produced speech.
    for (final rendition in mediaRenditions) {
      if (rendition['origin'] != 'derived') continue;
      final mediaBlob = Map<String, dynamic>.from(rendition['media_blob'] as Map);
      final blob = _readBlob(entries, mediaBlob);
      if (blob == null) continue;
      derivedMediaPath = _writeMediaBlob(
        releaseId,
        rendition['rendition_id'] as String,
        blob,
        rendition['media_type'] as String,
      );
    }

    return ResolvedComposition(
      releaseId: releaseId,
      documentText: text,
      sentences: sentences,
      anchors: parsedAnchors,
      alignments: alignments,
      derivedMediaPath: derivedMediaPath,
    );
  }

  static List<int>? _readBlob(
    Map<String, List<int>> entries,
    Map<String, dynamic> blob,
  ) {
    final digest = blob['digest'] as String;
    final hex = digest.startsWith('sha256:')
        ? digest.substring('sha256:'.length)
        : digest;
    return entries['blobs/sha256/$hex'];
  }

  static String _slice(String text, int start, int end) {
    final runes = text.runes.toList(growable: false);
    final safeStart = start.clamp(0, runes.length);
    final safeEnd = end.clamp(safeStart, runes.length);
    return String.fromCharCodes(runes.sublist(safeStart, safeEnd));
  }

  static String _writeMediaBlob(
    String releaseId,
    String renditionId,
    List<int> bytes,
    String mediaType,
  ) {
    final extension = switch (mediaType) {
      'audio/mp4' => 'm4a',
      'audio/mpeg' => 'mp3',
      'audio/wav' => 'wav',
      final other when other.startsWith('audio/') =>
        other.substring('audio/'.length),
      _ => 'bin',
    };
    final directory = Directory(
      '${Directory.systemTemp.path}/listen-composition-media/'
      '${_safeName(releaseId)}',
    );
    directory.createSync(recursive: true);
    final path = '${directory.path}/${_safeName(renditionId)}.$extension';
    File(path).writeAsBytesSync(bytes, flush: true);
    return path;
  }

  static String _safeName(String value) {
    final digest = sha256.convert(utf8.encode(value)).toString();
    return '${value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}-$digest';
  }
}
