import '../../models/types.dart';
import '../../services/api_service.dart';

/// Data boundary for the quick cold-start vocabulary marking flow.
abstract interface class ColdStartMarkingRepository {
  Future<List<ColdStartWordCandidate>> loadCandidates(String trackId);

  Future<void> saveMark({
    required ColdStartWordCandidate candidate,
    required String status,
    required String language,
  });
}

/// [LocalApi]-backed implementation kept out of the presentation layer.
class LocalColdStartMarkingRepository implements ColdStartMarkingRepository {
  LocalColdStartMarkingRepository(this._api);

  final LocalApi _api;

  @override
  Future<List<ColdStartWordCandidate>> loadCandidates(String trackId) =>
      _api.coldStartWords(trackId);

  @override
  Future<void> saveMark({
    required ColdStartWordCandidate candidate,
    required String status,
    required String language,
  }) async {
    await _api.upsertWordLexicalEntry(
      candidate.displayForm,
      candidate.displayForm,
      status,
      language: language,
    );
  }
}
