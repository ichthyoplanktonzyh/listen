import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/services/api_service.dart';

/// Wire decoding of the Core 4.0 capability + package-lifecycle responses.
/// Decode functions stay honest: absent nullable fields decode to null and
/// unknown enum values fail parsing instead of degrading.
void main() {
  test('decodeLearningEdition maps every required and nullable field', () {
    final edition = decodeLearningEdition({
      'material_id': 'material-1',
      'material_revision_id': 'revision-1',
      'edition_id': 'edition:material-1',
      'release_id': 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'title': 'Lesson',
      'target_language': 'en',
      'support_languages': ['zh'],
      'installed_at_ms': 100,
      'adopted_at_ms': 200,
      'adopted': true,
      'resources': [
        {
          'resource_id': 'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          'kind': 'structured_reading',
          'role': 'base',
          'required': true,
          'availability': 'available',
          'review_status': 'machine_checked',
          'content_language': 'en',
          'support_languages': <String>[],
        },
      ],
      'renditions': [
        {
          'rendition_id': 'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          'kind': 'document',
          'available': true,
        },
      ],
    });

    expect(edition.materialId, 'material-1');
    expect(edition.adoptedAtMs, 200);
    expect(edition.adopted, isTrue);
    expect(edition.resources.single.kind, 'structured_reading');
    expect(edition.renditions.single.kind, 'document');
    expect(edition.providesRead, isTrue);
  });

  test('an unadopted edition keeps adoptedAtMs null', () {
    final edition = decodeLearningEdition({
      'material_id': 'm',
      'material_revision_id': 'r',
      'edition_id': 'e',
      'release_id': 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'title': 'T',
      'target_language': 'en',
      'support_languages': <String>[],
      'installed_at_ms': 100,
      'adopted_at_ms': null,
      'adopted': false,
      'resources': <Object>[],
      'renditions': <Object>[],
    });
    expect(edition.adopted, isFalse);
    expect(edition.adoptedAtMs, isNull);
  });

  test('decodeCapabilityAttempt keeps failure and producer evidence nullable',
      () {
    final running = decodeCapabilityAttempt({
      'attempt_id': 'attempt-1',
      'status': 'running',
      'started_at_ms': 1,
      'finished_at_ms': null,
      'failure_reason': null,
      'producer_tool_id': null,
      'producer_tool_version': null,
    });
    expect(running.status, 'running');
    expect(running.finishedAtMs, isNull);

    final succeeded = decodeCapabilityAttempt({
      'attempt_id': 'attempt-1',
      'status': 'succeeded',
      'started_at_ms': 1,
      'finished_at_ms': 2,
      'failure_reason': null,
      'producer_tool_id': 'listen-gen',
      'producer_tool_version': '0.5.0',
    });
    expect(succeeded.status, 'succeeded');
    expect(succeeded.producerToolId, 'listen-gen');
    expect(succeeded.producerToolVersion, '0.5.0');

    final failed = decodeCapabilityAttempt({
      'attempt_id': 'attempt-1',
      'status': 'failed',
      'started_at_ms': 1,
      'finished_at_ms': 2,
      'failure_reason': 'provider_timeout',
      'producer_tool_id': null,
      'producer_tool_version': null,
    });
    expect(failed.failureReason, 'provider_timeout');
  });

  test('decodeMaterialCapabilityProjection maps statuses and latest attempt',
      () {
    final projection = decodeMaterialCapabilityProjection({
      'capability': 'read',
      'status': 'failed_attempt',
      'latest_attempt': {
        'attempt_id': 'attempt-1',
        'status': 'failed',
        'started_at_ms': 1,
        'finished_at_ms': 2,
        'failure_reason': 'provider_timeout',
        'producer_tool_id': null,
        'producer_tool_version': null,
      },
    });
    expect(projection.capability, MaterialCapability.read);
    expect(projection.status, MaterialCapabilityStatus.failedAttempt);
    expect(projection.latestAttempt?.failureReason, 'provider_timeout');

    final withoutAttempt = decodeMaterialCapabilityProjection({
      'capability': 'listen',
      'status': 'derivable',
      'latest_attempt': null,
    });
    expect(withoutAttempt.latestAttempt, isNull);
  });

  test('unknown enum values fail decoding instead of degrading', () {
    expect(
      () => decodeMaterialCapabilityProjection({
        'capability': 'read',
        'status': 'mystery',
        'latest_attempt': null,
      }),
      throwsFormatException,
    );
    expect(
      () => decodeMaterialCapability('mystery'),
      throwsFormatException,
    );
  });
}
