import '../../models/api_failure.dart';
import '../../models/practice.dart';
import '../../services/api_service.dart';

class HuntingRepositoryFailure implements Exception {
  const HuntingRepositoryFailure(this.detail);
  final ApiFailure detail;
}

abstract interface class HuntingRepository {
  bool get isAvailable;
  Future<List<HuntingTarget>> targets();
  Future<List<HuntingCandidate>> candidates();
  Future<HuntingTarget> createTarget({
    required String lexicalEntryId,
    required String sourceKind,
    String? sourceId,
  });
  Future<void> archiveTarget(String id);
  Future<HuntingOccurrenceQueryResult> occurrences({
    required String mediaId,
    String? trackId,
  });
  Future<void> submitCheck({
    required String sessionId,
    required String targetId,
    required String occurrenceId,
    required String answer,
  });
  Future<int> reindexCorpus();
}

class LocalHuntingRepository implements HuntingRepository {
  LocalHuntingRepository(this._getApi);
  final LocalApi? Function() _getApi;

  LocalApi get _api =>
      _getApi() ?? (throw StateError('Hunting API is unavailable'));

  @override
  bool get isAvailable => _getApi() != null;

  Future<T> _request<T>(Future<T> Function(LocalApi api) request) async {
    try {
      return await request(_api);
    } catch (error) {
      throw HuntingRepositoryFailure(describeApiFailure(error));
    }
  }

  @override
  Future<List<HuntingTarget>> targets() =>
      _request((api) => api.huntingTargets());
  @override
  Future<List<HuntingCandidate>> candidates() =>
      _request((api) => api.huntingCandidates());
  @override
  Future<HuntingTarget> createTarget({
    required String lexicalEntryId,
    required String sourceKind,
    String? sourceId,
  }) => _request(
    (api) => api.createHuntingTarget(
      lexicalEntryId: lexicalEntryId,
      sourceKind: sourceKind,
      sourceId: sourceId,
    ),
  );
  @override
  Future<void> archiveTarget(String id) async {
    await _request((api) => api.archiveHuntingTarget(id));
  }

  @override
  Future<HuntingOccurrenceQueryResult> occurrences({
    required String mediaId,
    String? trackId,
  }) => _request(
    (api) => api.huntingOccurrences(mediaId: mediaId, trackId: trackId),
  );
  @override
  Future<void> submitCheck({
    required String sessionId,
    required String targetId,
    required String occurrenceId,
    required String answer,
  }) async {
    await _request(
      (api) => api.submitHuntingCheck(
        sessionId: sessionId,
        targetId: targetId,
        occurrenceId: occurrenceId,
        answer: answer,
      ),
    );
  }

  @override
  Future<int> reindexCorpus() => _request((api) => api.reindexCorpus());
}

class UnavailableHuntingRepository implements HuntingRepository {
  const UnavailableHuntingRepository();
  Never _unavailable() => throw StateError('Hunting repository unavailable');
  @override
  bool get isAvailable => false;
  @override
  Future<void> archiveTarget(String id) => _unavailable();
  @override
  Future<List<HuntingCandidate>> candidates() => _unavailable();
  @override
  Future<HuntingTarget> createTarget({
    required String lexicalEntryId,
    required String sourceKind,
    String? sourceId,
  }) => _unavailable();
  @override
  Future<HuntingOccurrenceQueryResult> occurrences({
    required String mediaId,
    String? trackId,
  }) => _unavailable();
  @override
  Future<int> reindexCorpus() => _unavailable();
  @override
  Future<void> submitCheck({
    required String sessionId,
    required String targetId,
    required String occurrenceId,
    required String answer,
  }) => _unavailable();
  @override
  Future<List<HuntingTarget>> targets() => _unavailable();
}

ApiFailure? huntingFailureDetail(Object error) =>
    error is HuntingRepositoryFailure ? error.detail : null;
