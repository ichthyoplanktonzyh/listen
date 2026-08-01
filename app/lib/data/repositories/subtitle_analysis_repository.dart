import '../../models/runtime_resources.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';

/// Data boundary for optional subtitle-derived analysis capabilities.
abstract interface class SubtitleAnalysisRepository {
  bool get isAvailable;

  Future<bool> syntaxReady();

  Future<void> analyzeTrackSyntax(String trackId);

  Future<PronunciationAnalysis> analyzePronunciation(String sentenceId);

  Future<String> startPhoneticAnalysis({
    required String trackId,
    required String? sentenceId,
    required String preferredModelId,
  });
}

class LocalSubtitleAnalysisRepository implements SubtitleAnalysisRepository {
  LocalSubtitleAnalysisRepository(this._getApi);

  final LocalApi? Function() _getApi;

  LocalApi get _api =>
      _getApi() ?? (throw StateError('Subtitle analysis API is unavailable'));

  @override
  bool get isAvailable => _getApi() != null;

  @override
  Future<bool> syntaxReady() async => (await _api.syntaxCapability()).isReady;

  @override
  Future<void> analyzeTrackSyntax(String trackId) async {
    await _api.runTrackSyntaxAnalysis(trackId);
  }

  @override
  Future<PronunciationAnalysis> analyzePronunciation(String sentenceId) =>
      _api.analyzePronunciation(sentenceId);

  @override
  Future<String> startPhoneticAnalysis({
    required String trackId,
    required String? sentenceId,
    required String preferredModelId,
  }) async {
    final models = await _api.phoneticAnalysisModels();
    final model = models.cast<PhoneticModelView?>().firstWhere(
      (value) =>
          value != null &&
          (value.id == preferredModelId ||
              (preferredModelId.isEmpty &&
                  (value.state == 'installed' || value.state == 'custom'))),
      orElse: () => null,
    );
    if (model == null) {
      throw StateError('No compatible phonetic analysis model is available');
    }
    final job = await _api.createPhoneticAnalysisJob(
      trackId: trackId,
      sentenceId: sentenceId,
      modelId: model.id,
    );
    return job.status;
  }
}
