import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/learning_edition.dart';

/// LearningEdition facts: what each capability reads off an installed
/// edition, and how the wire decode keeps nullable evidence nullable.
void main() {
  LearningEdition edition({
    List<LearningEditionRendition> renditions = const [],
    List<LearningEditionResource> resources = const [],
  }) => LearningEdition(
    materialId: 'm1',
    materialRevisionId: 'r1',
    editionId: 'edition:m1',
    releaseId: 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    title: 'Lesson',
    targetLanguage: 'en',
    supportLanguages: const ['zh'],
    installedAtMs: 1,
    adoptedAtMs: 2,
    adopted: true,
    resources: resources,
    renditions: renditions,
  );

  const documentRendition = LearningEditionRendition(
    renditionId: 'd1',
    kind: 'document',
    available: true,
  );
  const mediaRendition = LearningEditionRendition(
    renditionId: 'm2',
    kind: 'media',
    available: true,
  );
  const readingResource = LearningEditionResource(
    resourceId: 'r1',
    kind: 'structured_reading',
    role: 'base',
    required: true,
    availability: 'available',
    reviewStatus: 'machine_checked',
    contentLanguage: 'en',
    supportLanguages: [],
  );
  const alignmentResource = LearningEditionResource(
    resourceId: 'r2',
    kind: 'anchor_time_alignment',
    role: 'base',
    required: true,
    availability: 'available',
    reviewStatus: 'machine_checked',
    contentLanguage: null,
    supportLanguages: [],
  );

  test('read is provided by a document rendition or a structured reading', () {
    expect(edition().providesRead, isFalse);
    expect(
      edition(renditions: const [documentRendition]).providesRead,
      isTrue,
    );
    expect(
      edition(resources: const [readingResource]).providesRead,
      isTrue,
    );
  });

  test('media availability and alignment drive listen surfaces', () {
    final plainMedia = edition(renditions: const [mediaRendition]);
    expect(plainMedia.hasAvailableMediaRendition, isTrue);
    expect(plainMedia.providesSynchronizedReadListen, isFalse);

    final synchronized = edition(
      renditions: const [mediaRendition],
      resources: const [alignmentResource],
    );
    expect(synchronized.providesSynchronizedReadListen, isTrue);
  });

  test('an unavailable media rendition is not playable', () {
    final missing = edition(
      renditions: const [
        LearningEditionRendition(
          renditionId: 'm2',
          kind: 'media',
          available: false,
        ),
      ],
    );
    expect(missing.hasAvailableMediaRendition, isFalse);
    expect(missing.providesSynchronizedReadListen, isFalse);
  });

  test('baseResourceOfKind finds the first matching resource', () {
    final subject = edition(
      resources: const [readingResource, alignmentResource],
    );
    expect(subject.baseResourceOfKind('structured_reading'), readingResource);
    expect(subject.baseResourceOfKind('anchor_time_alignment'), alignmentResource);
    expect(subject.baseResourceOfKind('absent'), isNull);
  });

  test('collection getters never expose mutable aliases', () {
    final subject = edition(
      renditions: const [mediaRendition],
      resources: const [readingResource],
    );
    expect(() => subject.supportLanguages.add('ja'), throwsUnsupportedError);
    expect(() => subject.resources.add(alignmentResource), throwsUnsupportedError);
    expect(() => subject.renditions.add(documentRendition), throwsUnsupportedError);
    expect(subject.supportLanguages, ['zh']);
    expect(subject.resources, [readingResource]);
    expect(subject.renditions, [mediaRendition]);
  });
}
