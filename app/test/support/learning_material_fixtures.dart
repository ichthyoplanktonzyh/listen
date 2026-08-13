/// Shared Core 4.0 material fixtures for tests. Every constructor is small and
/// explicit so a test can build exactly the revision shape it needs without
/// repeating the surrounding boilerplate.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/personal_library.dart';

/// A Source Document Rendition carrying [text]: the digest is the exact
/// UTF-8 byte digest of the text, as Core binds a Source rendition to its
/// Source Asset bytes.
DocumentRendition documentRenditionForText(
  String text, {
  String id = 'document-1',
  String mediaType = 'text/plain',
  String? language,
  String? sourceAssetId = 'source-1',
}) => documentRendition(
  id: id,
  mediaType: mediaType,
  digest: sha256.convert(utf8.encode(text)).toString(),
  byteSize: utf8.encode(text).length,
  language: language,
  sourceAssetId: sourceAssetId,
);

SourceAsset sourceAsset({
  String id = 'source-1',
  String mediaType = 'text/plain',
  int byteLength = 11,
  String sha256Digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  SourceAssetBinding binding = const SourceAssetBinding(
    type: SourceAssetBindingType.managed,
  ),
  SourceAssetAvailability availability = const SourceAssetAvailability(
    state: SourceAssetAvailabilityState.available,
  ),
}) => SourceAsset(
  id: id,
  mediaType: mediaType,
  byteLength: byteLength,
  sha256Digest: sha256Digest,
  binding: binding,
  availability: availability,
  createdAtMs: 1,
);

DocumentRendition documentRendition({
  String id = 'document-1',
  String mediaType = 'text/plain',
  String digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  int byteSize = 11,
  String? language,
  String? sourceAssetId = 'source-1',
  RenditionOrigin origin = RenditionOrigin.source,
}) => DocumentRendition(
  id: id,
  origin: origin,
  mediaType: mediaType,
  language: language,
  digest: digest,
  byteSize: byteSize,
  sourceAssetId: sourceAssetId,
);

MediaRendition mediaRendition({
  String id = 'media-1',
  RenditionOrigin origin = RenditionOrigin.source,
  MediaRenditionKind kind = MediaRenditionKind.audio,
  String mediaType = 'audio/mpeg',
  String fingerprint = 'fp-1',
  MediaRenditionAvailability availability =
      MediaRenditionAvailability.available,
  String? mediaId = 'media-1',
}) => MediaRendition(
  id: id,
  origin: origin,
  kind: kind,
  mediaType: mediaType,
  fingerprint: fingerprint,
  availability: availability,
  mediaId: mediaId,
  mediaSha256: null,
  mediaByteSize: null,
);

MaterialDetails materialDetails({
  String materialId = 'material-1',
  String revisionId = 'revision-1',
  String title = 'Sample',
  List<SourceAsset>? sourceAssets,
  List<DocumentRendition>? documentRenditions,
  List<MediaRendition>? mediaRenditions,
  int? retainedAtMs = 42,
  MaterialShape shape = MaterialShape.text,
  int createdAtMs = 1,
}) => MaterialDetails(
  material: LearningMaterial(
    id: materialId,
    currentRevisionId: revisionId,
    retainedAtMs: retainedAtMs,
    createdAtMs: createdAtMs,
    updatedAtMs: createdAtMs,
  ),
  currentRevision: MaterialRevision(
    id: revisionId,
    materialId: materialId,
    title: title,
    sourceAssets: sourceAssets ?? [sourceAsset()],
    documentRenditions: documentRenditions ?? [documentRendition()],
    mediaRenditions: mediaRenditions ?? const [],
    createdAtMs: createdAtMs,
  ),
  shape: shape,
);

/// A text-only library entry (document rendition, managed source asset).
PersonalLibraryEntry textLibraryEntry({
  String materialId = 'material-1',
  String title = 'Sample',
  String digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  int byteSize = 11,
  int? retainedAtMs = 42,
}) => PersonalLibraryEntry(
  details: materialDetails(
    materialId: materialId,
    title: title,
    documentRenditions: [documentRendition(digest: digest, byteSize: byteSize)],
    retainedAtMs: retainedAtMs,
  ),
  mediaEntries: const [],
);

/// A media library entry with an audio rendition (Listen projection).
PersonalLibraryEntry audioLibraryEntry({
  String materialId = 'material-1',
  String title = 'Sample audio',
  int? retainedAtMs = 42,
}) => PersonalLibraryEntry(
  details: materialDetails(
    materialId: materialId,
    title: title,
    documentRenditions: const [],
    mediaRenditions: [mediaRendition()],
    shape: MaterialShape.audio,
    retainedAtMs: retainedAtMs,
  ),
  mediaEntries: const [],
);
