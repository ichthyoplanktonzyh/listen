import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/learning_edition.dart';

/// LearningEdition facts: what each capability reads off an installed
/// edition, and how the wire decode keeps nullable evidence nullable.
void main() {
  LearningEdition edition({
    List<LearningEditionRendition> renditions = const [],
    List<LearningEditionResource> resources = const [],
    List<String> availableCapabilities = const [],
  }) => LearningEdition(
    materialId: 'm1',
    materialRevisionId: 'r1',
    editionId: 'edition:m1',
    releaseId:
        'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    title: 'Lesson',
    targetLanguage: 'en',
    supportLanguages: const ['zh'],
    installedAtMs: 1,
    adoptedAtMs: 2,
    adopted: true,
    availableCapabilities: availableCapabilities,
    resources: resources,
    renditions: renditions,
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

  test('Core available capabilities, not resource kinds, drive read', () {
    expect(edition().providesRead, isFalse);
    expect(
      edition(resources: const [readingResource]).providesRead,
      isFalse,
      reason: 'the App must not infer read from a resource kind',
    );
    expect(edition(availableCapabilities: const ['read']).providesRead, isTrue);
  });

  test('Core capability facts and media availability stay distinct', () {
    final plainMedia = edition(renditions: const [mediaRendition]);
    expect(plainMedia.hasAvailableMediaRendition, isTrue);
    expect(plainMedia.providesSynchronizedReadListen, isFalse);

    final synchronized = edition(
      renditions: const [mediaRendition],
      resources: const [alignmentResource],
      availableCapabilities: const ['synchronized_read_listen'],
    );
    expect(synchronized.providesSynchronizedReadListen, isTrue);
    expect(
      edition(
        renditions: const [mediaRendition],
        resources: const [alignmentResource],
      ).providesSynchronizedReadListen,
      isFalse,
      reason: 'the App must trust Core instead of inferring from alignment',
    );
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
    expect(
      subject.baseResourceOfKind('anchor_time_alignment'),
      alignmentResource,
    );
    expect(subject.baseResourceOfKind('absent'), isNull);
  });

  test('collection getters never expose mutable aliases', () {
    final subject = edition(
      renditions: const [mediaRendition],
      resources: const [readingResource],
      availableCapabilities: const ['read'],
    );
    expect(() => subject.supportLanguages.add('ja'), throwsUnsupportedError);
    expect(
      () => subject.availableCapabilities.add('listen'),
      throwsUnsupportedError,
    );
    expect(
      () => subject.resources.add(alignmentResource),
      throwsUnsupportedError,
    );
    expect(
      () => subject.renditions.add(
        const LearningEditionRendition(
          renditionId: 'm3',
          kind: 'media',
          available: true,
        ),
      ),
      throwsUnsupportedError,
    );
    expect(subject.supportLanguages, ['zh']);
    expect(subject.resources, [readingResource]);
    expect(subject.renditions, [mediaRendition]);
  });
}
