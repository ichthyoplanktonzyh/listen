import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/personal_library.dart';
import 'package:llplayer_next/models/types.dart';

import 'support/learning_material_fixtures.dart';

/// [PersonalLibraryEntry]: a pure immutable projection of a retained material
/// over its current revision, joined with the registered-media rows whose ids
/// the revision mentions.
void main() {
  test('joins only the media rows whose ids occur in the current revision', () {
    final entry = PersonalLibraryEntry(
      details: _details(
        mediaRenditions: [
          _rendition('r1', 'media-1'),
          _rendition('r2', 'media-2'),
        ],
      ),
      mediaEntries: [
        _mediaEntry('media-1'),
        _mediaEntry('media-2'),
        _mediaEntry('media-3'),
      ],
    );

    expect(entry.mediaEntries.map((e) => e.media.id), ['media-1', 'media-2']);
    expect(entry.mediaEntries.where((e) => e.media.id == 'media-3'), isEmpty);
  });

  test('orders joined rows by first appearance in the revision', () {
    final entry = PersonalLibraryEntry(
      details: _details(
        mediaRenditions: [
          _rendition('r1', 'media-2'),
          _rendition('r2', 'media-1'),
        ],
      ),
      mediaEntries: [_mediaEntry('media-1'), _mediaEntry('media-2')],
    );

    expect(entry.mediaEntries.map((e) => e.media.id), ['media-2', 'media-1']);
  });

  test('includes text-only materials with no media rows', () {
    final entry = PersonalLibraryEntry(
      details: _details(
        title: 'Reading text',
        shape: MaterialShape.text,
        documentRenditions: [_textAsset('Hello')],
      ),
      mediaEntries: [_mediaEntry('media-1')],
    );

    expect(entry.title, 'Reading text');
    expect(entry.shape, MaterialShape.text);
    expect(entry.mediaEntries, isEmpty);
    expect(entry.primaryMedia, isNull);
    expect(entry.documentRenditions.single.text, 'Hello');
  });

  test('projects title, shape, updated time and document assets', () {
    final entry = PersonalLibraryEntry(
      details: _details(
        title: 'Episode 5',
        updatedAtMs: 4242,
        documentRenditions: [_textAsset('A'), _textAsset('B')],
      ),
      mediaEntries: const [],
    );

    expect(entry.materialId, 'material-1');
    expect(entry.currentRevisionId, 'revision-1');
    expect(entry.title, 'Episode 5');
    expect(entry.shape, MaterialShape.mixed);
    expect(entry.updatedAtMs, 4242);
    expect(entry.isRetained, isTrue);
    expect(entry.documentRenditions.map((asset) => asset.text), ['A', 'B']);
  });

  test('chooses the first usable rendition in revision order', () {
    final entry = PersonalLibraryEntry(
      details: _details(
        mediaRenditions: [
          _rendition(
            'r1',
            'media-1',
            availability: MediaRenditionAvailability.archived,
          ),
          _rendition('r2', 'media-2'),
          _rendition('r3', 'media-3'),
        ],
      ),
      mediaEntries: [
        _mediaEntry('media-1'),
        _mediaEntry('media-2'),
        _mediaEntry('media-3'),
      ],
    );

    expect(entry.primaryMedia?.media.id, 'media-2');
  });

  test('skips renditions that have no joined registered-media row', () {
    final entry = PersonalLibraryEntry(
      details: _details(
        mediaRenditions: [
          _rendition('r1', 'media-unlisted'),
          _rendition('r2', 'media-2'),
        ],
      ),
      mediaEntries: [_mediaEntry('media-2')],
    );

    expect(entry.primaryMedia?.media.id, 'media-2');
  });

  test('advances past joined rows whose media availability is missing', () {
    final entry = PersonalLibraryEntry(
      details: _details(
        mediaRenditions: [
          _rendition('r1', 'media-1'),
          _rendition('r2', 'media-2'),
        ],
      ),
      mediaEntries: [
        _mediaEntry('media-1', availability: 'missing'),
        _mediaEntry('media-2'),
      ],
    );

    expect(entry.primaryMedia?.media.id, 'media-2');
  });

  test('has no primary media when every rendition is unusable', () {
    final entry = PersonalLibraryEntry(
      details: _details(
        mediaRenditions: [
          _rendition(
            'r1',
            'media-1',
            availability: MediaRenditionAvailability.missing,
          ),
          _rendition(
            'r2',
            'media-2',
            availability: MediaRenditionAvailability.archived,
          ),
        ],
      ),
      mediaEntries: [_mediaEntry('media-1'), _mediaEntry('media-2')],
    );

    expect(entry.primaryMedia, isNull);
    expect(entry.triageIntent, isNull);
    expect(entry.familiarMaterial, isFalse);
  });

  test('delegates triage facts to the primary media', () {
    final entry = PersonalLibraryEntry(
      details: _details(mediaRenditions: [_rendition('r1', 'media-1')]),
      mediaEntries: [_mediaEntry('media-1', triageIntent: 'pin_intensive')],
    );

    expect(entry.triageIntent, 'pin_intensive');
    expect(entry.media?.id, 'media-1');
    expect(entry.isGoldenTarget, isFalse);
  });

  test('exposes unmodifiable collections', () {
    final entry = PersonalLibraryEntry(
      details: _details(
        mediaRenditions: [_rendition('r1', 'media-1')],
        documentRenditions: [_textAsset('Hello')],
      ),
      mediaEntries: [_mediaEntry('media-1')],
    );

    expect(entry.mediaEntries.clear, throwsUnsupportedError);
    expect(
      () => entry.mediaEntries.add(_mediaEntry('media-9')),
      throwsUnsupportedError,
    );
    expect(
      () => entry.mediaEntries[0] = _mediaEntry('media-9'),
      throwsUnsupportedError,
    );
    expect(entry.documentRenditions.clear, throwsUnsupportedError);
    expect(
      () => entry.documentRenditions.add(_textAsset('More')),
      throwsUnsupportedError,
    );
    expect(
      () => entry.documentRenditions[0] = _textAsset('Other'),
      throwsUnsupportedError,
    );
    expect(
      () => entry.mediaRenditions[0] = _rendition('r9', 'media-9'),
      throwsUnsupportedError,
    );
  });

  test('defensively copies constructor collections', () {
    final rows = [_mediaEntry('media-1')];
    final entry = PersonalLibraryEntry(
      details: _details(mediaRenditions: [_rendition('r1', 'media-1')]),
      mediaEntries: rows,
    );

    rows.clear();

    expect(entry.mediaEntries, hasLength(1));
  });

  test('withMediaEntry replaces the matching joined row immutably', () {
    final entry = PersonalLibraryEntry(
      details: _details(mediaRenditions: [_rendition('r1', 'media-1')]),
      mediaEntries: [_mediaEntry('media-1')],
    );

    final updated = entry.withMediaEntry(
      _mediaEntry('media-1', triageIntent: 'defer'),
    );

    expect(entry.triageIntent, isNull);
    expect(updated.triageIntent, 'defer');
    expect(updated.materialId, entry.materialId);
    expect(entry.mediaEntries, isNot(same(updated.mediaEntries)));
  });

  test('withMediaEntry returns the same row when nothing matches', () {
    final entry = PersonalLibraryEntry(
      details: _details(mediaRenditions: [_rendition('r1', 'media-1')]),
      mediaEntries: [_mediaEntry('media-1')],
    );

    expect(
      identical(entry.withMediaEntry(_mediaEntry('media-9')), entry),
      isTrue,
    );
  });
}

MediaLibraryEntry _mediaEntry(
  String id, {
  String? triageIntent,
  bool familiarMaterial = false,
  String availability = 'available',
}) => MediaLibraryEntry(
  media: MediaItem(
    id: id,
    path: '/media/$id.mp4',
    fingerprint: 'fp',
    title: 'Media $id',
    kind: 'video',
    durationMs: 1000,
    availability: availability,
    createdAtMs: 0,
    updatedAtMs: 0,
  ),
  primaryTrackId: null,
  fit: null,
  triageIntent: triageIntent,
  familiarMaterial: familiarMaterial,
);

MediaRendition _rendition(
  String id,
  String mediaId, {
  MediaRenditionAvailability availability =
      MediaRenditionAvailability.available,
}) => mediaRendition(
  id: id,
  mediaId: mediaId,
  kind: MediaRenditionKind.audio,
  fingerprint: 'fp',
  availability: availability,
);

DocumentRendition _textAsset(String text) => documentRendition(
  id: 'text-$text',
  text: text,
);

MaterialDetails _details({
  String materialId = 'material-1',
  String title = 'Sample',
  int updatedAtMs = 100,
  MaterialShape shape = MaterialShape.mixed,
  List<SourceAsset> sourceAssets = const [],
  List<DocumentRendition> documentRenditions = const [],
  List<MediaRendition> mediaRenditions = const [],
}) => MaterialDetails(
  material: LearningMaterial(
    id: materialId,
    currentRevisionId: 'revision-1',
    retainedAtMs: 7,
    createdAtMs: 1,
    updatedAtMs: updatedAtMs,
  ),
  currentRevision: MaterialRevision(
    id: 'revision-1',
    materialId: materialId,
    title: title,
    sourceAssets: sourceAssets,
    documentRenditions: documentRenditions,
    mediaRenditions: mediaRenditions,
    createdAtMs: 1,
  ),
  shape: shape,
);
