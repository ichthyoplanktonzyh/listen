import '../data/repositories/transcription_repository.dart';
import '../models/api_failure.dart';

sealed class RealtimeTranscriptionModelOutcome {
  const RealtimeTranscriptionModelOutcome();
}

final class RealtimeTranscriptionModelSelected
    extends RealtimeTranscriptionModelOutcome {
  const RealtimeTranscriptionModelSelected(this.modelId);

  final String modelId;
}

final class RealtimeTranscriptionModelUnavailable
    extends RealtimeTranscriptionModelOutcome {
  const RealtimeTranscriptionModelUnavailable();
}

final class RealtimeTranscriptionModelFailure
    extends RealtimeTranscriptionModelOutcome {
  const RealtimeTranscriptionModelFailure(this.failure);

  final ApiFailure failure;
}

final class RealtimeTranscriptionModelController {
  const RealtimeTranscriptionModelController(this._repository);

  final TranscriptionRepository _repository;

  Future<RealtimeTranscriptionModelOutcome> selectForLanguage(
    String language,
  ) async {
    try {
      final models = await _repository.models();
      for (final model in models) {
        final installed = model.state == 'installed' || model.state == 'custom';
        if (installed && (language == 'en' || !model.englishOnly)) {
          return RealtimeTranscriptionModelSelected(model.id);
        }
      }
      return const RealtimeTranscriptionModelUnavailable();
    } catch (error) {
      return RealtimeTranscriptionModelFailure(
        _repository.failureDetail(error),
      );
    }
  }
}
