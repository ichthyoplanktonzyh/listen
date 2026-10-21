/// Shared material fixtures for App tests.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/personal_library.dart';
import 'package:llplayer_next/models/types.dart';

MediaRendition mediaRendition({
  String id = 'media-rendition-1',
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

SourceAsset sourceAsset({
  String? id,
  String mediaType = 'text/plain',
  int byteLength = 4,
  String? sha256Digest,
  SourceAssetBinding binding = const SourceAssetBinding(
    type: SourceAssetBindingType.managed,
  ),
  SourceAssetAvailability availability = const SourceAssetAvailability(
    state: SourceAssetAvailabilityState.available,
  ),
  int createdAtMs = 1,
}) {
  final digest = sha256Digest ?? 'a' * 64;
  return SourceAsset(
    id: id ?? digest,
    mediaType: mediaType,
    byteLength: byteLength,
    sha256Digest: digest,
    binding: binding,
    availability: availability,
    createdAtMs: createdAtMs,
  );
}

DocumentRendition documentRendition({
  String id = 'document-rendition-1',
  RenditionOrigin origin = RenditionOrigin.source,
  String mediaType = 'text/plain',
  String? language = 'en',
  String digest =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  int byteSize = 4,
  String? sourceAssetId =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) => DocumentRendition(
  id: id,
  origin: origin,
  mediaType: mediaType,
  language: language,
  digest: digest,
  byteSize: byteSize,
  sourceAssetId: sourceAssetId,
);

DocumentRendition documentRenditionForText(
  String text, {
  String id = 'document-rendition-1',
  String? language = 'en',
  String mediaType = 'text/plain',
  String? sourceAssetId,
}) {
  final bytes = utf8.encode(text);
  final digest = sha256.convert(bytes).toString();
  return DocumentRendition(
    id: id,
    origin: RenditionOrigin.source,
    mediaType: mediaType,
    language: language,
    digest: digest,
    byteSize: bytes.length,
    sourceAssetId: sourceAssetId ?? digest,
  );
}

MaterialDetails materialDetails({
  String materialId = 'material-1',
  String revisionId = 'revision-1',
  String title = 'Sample',
  List<MediaRendition>? mediaRenditions,
  List<SourceAsset> sourceAssets = const [],
  List<DocumentRendition> documentRenditions = const [],
  int? retainedAtMs = 42,
  MaterialShape shape = MaterialShape.audio,
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
    sourceAssets: sourceAssets,
    documentRenditions: documentRenditions,
    mediaRenditions: mediaRenditions ?? [mediaRendition()],
    createdAtMs: createdAtMs,
  ),
  shape: shape,
);

/// A media library entry joined to its current media-only material revision.
PersonalLibraryEntry audioLibraryEntry({
  String materialId = 'material-1',
  String title = 'Sample audio',
  int? retainedAtMs = 42,
  String mediaId = 'media-1',
  MediaRenditionKind kind = MediaRenditionKind.audio,
}) {
  final entry = MediaLibraryEntry(
    media: MediaItem(
      id: mediaId,
      path: '/media/$mediaId',
      fingerprint: 'fp-1',
      title: title,
      kind: kind == MediaRenditionKind.audio ? 'audio' : 'video',
      durationMs: 1000,
      availability: 'available',
      createdAtMs: 1,
      updatedAtMs: 1,
    ),
    primaryTrackId: null,
    triageIntent: null,
  );
  return PersonalLibraryEntry(
    details: materialDetails(
      materialId: materialId,
      title: title,
      mediaRenditions: [
        mediaRendition(
          mediaId: mediaId,
          kind: kind,
          mediaType: kind == MediaRenditionKind.audio
              ? 'audio/mpeg'
              : 'video/mp4',
        ),
      ],
      shape: kind == MediaRenditionKind.audio
          ? MaterialShape.audio
          : MaterialShape.video,
      retainedAtMs: retainedAtMs,
    ),
    mediaEntries: [entry],
  );
}
