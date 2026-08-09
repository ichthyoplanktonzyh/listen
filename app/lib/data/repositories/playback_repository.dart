import '../../models/api_failure.dart';
import '../../models/types.dart';
import '../../models/vocabulary_transfer.dart';
import '../../services/api_service.dart';
import 'occurrence_media_repository.dart';

abstract interface class PlaybackRepository
    implements OccurrenceMediaRepository {
  bool get isAvailable;
  ApiFailure failureDetail(Object error);
  Future<void> updatePhoneticFindingFeedback({
    required String findingId,
    required String value,
  });
  Future<VocabularyExportBundle> exportVocabulary();
  Future<void> importVocabulary(Map<String, dynamic> bundle);
  Future<void> archiveMedia(String mediaId);
}

class UnavailablePlaybackRepository implements PlaybackRepository {
  const UnavailablePlaybackRepository();
  Never _unavailable() =>
      throw StateError('Playback repository is unavailable');
  @override
  bool get isAvailable => false;
  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);
  @override
  Future<void> archiveMedia(String mediaId) => _unavailable();
  @override
  Future<VocabularyExportBundle> exportVocabulary() => _unavailable();
  @override
  Future<String> fingerprintFile(String path) => _unavailable();
  @override
  Future<void> importVocabulary(Map<String, dynamic> bundle) => _unavailable();
  @override
  Future<MediaItem> readMedia(String mediaId) => _unavailable();
  @override
  Future<void> registerMedia(String path) => _unavailable();
  @override
  Future<void> updatePhoneticFindingFeedback({
    required String findingId,
    required String value,
  }) => _unavailable();
}

class LocalPlaybackRepository implements PlaybackRepository {
  LocalPlaybackRepository(this._getApi);
  final LocalApi? Function() _getApi;
  LocalApi get _api =>
      _getApi() ?? (throw StateError('Playback API is unavailable'));
  @override
  bool get isAvailable => _getApi() != null;
  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);
  @override
  Future<MediaItem> readMedia(String mediaId) => _api.readMedia(mediaId);
  @override
  Future<String> fingerprintFile(String path) => _api.fingerprintFile(path);
  @override
  /// Playback/relinking only attaches a usable source to existing learning
  /// state. It is not an explicit Keep, so a newly registered file stays
  /// Temporary Material.
  Future<void> registerMedia(String path) async =>
      _api.registerMedia(path, retain: false);
  @override
  Future<void> updatePhoneticFindingFeedback({
    required String findingId,
    required String value,
  }) => _api.updatePhoneticFindingFeedback(findingId: findingId, value: value);
  @override
  Future<VocabularyExportBundle> exportVocabulary() => _api.exportVocabulary();
  @override
  Future<void> importVocabulary(Map<String, dynamic> bundle) =>
      _api.importVocabulary(bundle);
  @override
  Future<void> archiveMedia(String mediaId) =>
      _api.setMediaAvailability(mediaId, 'archived');
}
