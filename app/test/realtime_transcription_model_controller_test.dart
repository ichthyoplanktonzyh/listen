import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/realtime_transcription_model_controller.dart';
import 'package:llplayer_next/data/repositories/transcription_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/runtime_resources.dart';

void main() {
  test('selects an installed model compatible with the language', () async {
    final controller = RealtimeTranscriptionModelController(
      _Repository([
        model('english', englishOnly: true),
        model('multilingual', englishOnly: false),
      ]),
    );

    final outcome = await controller.selectForLanguage('zh');

    expect(outcome, isA<RealtimeTranscriptionModelSelected>());
    expect(
      (outcome as RealtimeTranscriptionModelSelected).modelId,
      'multilingual',
    );
  });

  test('returns typed unavailable and failure outcomes', () async {
    final unavailable = RealtimeTranscriptionModelController(
      _Repository([model('pending', state: 'available')]),
    );
    final failed = RealtimeTranscriptionModelController(
      _Repository(const [], error: StateError('offline')),
    );

    expect(
      await unavailable.selectForLanguage('en'),
      isA<RealtimeTranscriptionModelUnavailable>(),
    );
    final failure = await failed.selectForLanguage('en');
    expect(failure, isA<RealtimeTranscriptionModelFailure>());
    expect(
      (failure as RealtimeTranscriptionModelFailure).failure,
      isA<ApiFailure>(),
    );
    expect(failure.failure.raw, contains('offline'));
  });
}

TranscriptionModelView model(
  String id, {
  bool englishOnly = false,
  String state = 'installed',
}) => TranscriptionModelView(
  id: id,
  displayName: id,
  revision: '1',
  sizeBytes: 1,
  quality: 'balanced',
  englishOnly: englishOnly,
  state: state,
  installedBytes: 1,
  license: 'test',
);

final class _Repository implements TranscriptionRepository {
  const _Repository(this.values, {this.error});

  final List<TranscriptionModelView> values;
  final Object? error;

  @override
  Future<List<TranscriptionModelView>> models() async {
    if (error case final error?) throw error;
    return values;
  }

  @override
  ApiFailure failureDetail(Object error) => ApiFailure(raw: '$error');
  @override
  Future<List<TranscriptionProviderView>> providers() async => const [];
  @override
  Future<void> registerCustomModel(String path) async {}
  @override
  Future<void> installModel(String id) async {}
  @override
  Future<void> cancelModelInstall(String id) async {}
  @override
  Future<void> deleteModel(String id) async {}
}
