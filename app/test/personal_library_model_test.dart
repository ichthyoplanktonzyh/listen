import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/personal_library.dart';
import 'package:llplayer_next/models/types.dart';

/// [PersonalLibraryEntry]: a pure immutable projection of a retained material
/// over its current revision, joined with the registered-media rows whose ids
/// the revision mentions.
void main() {
  test('joins only the media rows whose ids occur in the current revision', () {
    final entry = PersonalLibraryEntry(
      details: _details(
        assets: [_rendition('r1', 'media-1'), _rendition('r2', 'media-2')],
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
        assets: [_rendition('r1', 'media-2'), _rendition('r2', 'media-1')],
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
        assets: [_textAsset('Hello')],
      ),
      mediaEntries: [_mediaEntry('media-1')],
    );

    expect(entry.title, 'Reading text');
    expect(entry.shape, MaterialShape.text);
    expect(entry.mediaEntries, isEmpty);
    expect(entry.primaryMedia, isNull);
    expect(entry.documentAssets.single.text, 'Hello');
  });

  test('projects title, shape, updated time and document assets', () {
    final entry = PersonalLibraryEntry(
      details: _details(
        title: 'Episode 5',
        updatedAtMs: 4242,
        assets: [_textAsset('A'), _textAsset('B')],
      ),
      mediaEntries: const [],
    );

    expect(entry.materialId, 'material-1');
    expect(entry.currentRevisionId, 'revision-1');
    expect(entry.title, 'Episode 5');
    expect(entry.shape, MaterialShape.mixed);
    expect(entry.updatedAtMs, 4242);
    expect(entry.isRetained, isTrue);
    expect(entry.documentAssets.map((asset) => asset.text), ['A', 'B']);
  });

  test('chooses the first usable rendition in revision order', () {
    final entry = PersonalLibraryEntry(
      details: _details(
        assets: [
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
        assets: [
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
        assets: [_rendition('r1', 'media-1'), _rendition('r2', 'media-2')],
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
        assets: [
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
      details: _details(assets: [_rendition('r1', 'media-1')]),
      mediaEntries: [_mediaEntry('media-1', triageIntent: 'pin_intensive')],
    );

    expect(entry.triageIntent, 'pin_intensive');
    expect(entry.media?.id, 'media-1');
    expect(entry.isGoldenTarget, isFalse);
  });

  test('exposes unmodifiable collections', () {
    final entry = PersonalLibraryEntry(
      details: _details(
        assets: [_rendition('r1', 'media-1'), _textAsset('Hello')],
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
    expect(entry.documentAssets.clear, throwsUnsupportedError);
    expect(
      () => entry.documentAssets.add(_textAsset('More')),
      throwsUnsupportedError,
    );
    expect(
      () => entry.documentAssets[0] = _textAsset('Other'),
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
      details: _details(assets: [_rendition('r1', 'media-1')]),
      mediaEntries: rows,
    );

    rows.clear();

    expect(entry.mediaEntries, hasLength(1));
  });

  test('withMediaEntry replaces the matching joined row immutably', () {
    final entry = PersonalLibraryEntry(
      details: _details(assets: [_rendition('r1', 'media-1')]),
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
      details: _details(assets: [_rendition('r1', 'media-1')]),
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

MediaRenditionMaterialAsset _rendition(
  String id,
  String mediaId, {
  MediaRenditionAvailability availability =
      MediaRenditionAvailability.available,
}) => MediaRenditionMaterialAsset(
  id: id,
  mediaId: mediaId,
  mediaKind: MediaRenditionKind.audio,
  fingerprint: 'fp',
  availability: availability,
);

DocumentTextMaterialAsset _textAsset(String text) => DocumentTextMaterialAsset(
  id: 'text-$text',
  text: text,
  sha256Digest:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  byteSize: text.length,
  language: null,
);

MaterialDetails _details({
  String materialId = 'material-1',
  String title = 'Sample',
  int updatedAtMs = 100,
  MaterialShape shape = MaterialShape.mixed,
  List<MaterialAsset> assets = const [],
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
    assets: assets,
    createdAtMs: 1,
  ),
  shape: shape,
);
