import '../../models/speech_synthesis.dart';
import '../../services/api_service.dart';

abstract interface class SpeechSynthesisRepository {
  Future<SpeechSynthesisAssetView> synthesize({
    required String text,
    required String language,
    required String purpose,
  });
}

/// Resolves the current API lazily so reconnecting the local core does not
/// require rebuilding the controller that owns auxiliary playback.
final class LocalSpeechSynthesisRepository
    implements SpeechSynthesisRepository {
  const LocalSpeechSynthesisRepository(this._api);

  final LocalApi? Function() _api;

  @override
  Future<SpeechSynthesisAssetView> synthesize({
    required String text,
    required String language,
    required String purpose,
  }) {
    final api = _api();
    if (api == null) {
      throw StateError('Local core is unavailable');
    }
    return api.synthesizeSpeech(
      text: text,
      language: language,
      purpose: purpose,
    );
  }
}

/// Safe default for controller instances that only play remote provider audio.
final class UnavailableSpeechSynthesisRepository
    implements SpeechSynthesisRepository {
  const UnavailableSpeechSynthesisRepository();

  @override
  Future<SpeechSynthesisAssetView> synthesize({
    required String text,
    required String language,
    required String purpose,
  }) => Future.error(StateError('Speech synthesis is unavailable'));
}
