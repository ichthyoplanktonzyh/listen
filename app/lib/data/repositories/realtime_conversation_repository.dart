import '../../models/practice.dart';
import '../../models/realtime_conversation.dart';
import '../../models/runtime_resources.dart';
import '../../services/api_service.dart';

class RealtimeConnectionRequest {
  const RealtimeConnectionRequest({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, dynamic> headers;
}

abstract interface class RealtimeConversationRepository {
  Future<List<RealtimeProviderProfileView>> profiles();
  Future<RealtimeProviderProfileView> registerProfile({
    required String displayName,
    required String adapterKind,
    required String baseUrl,
    required String modelId,
    required String voice,
    required String secret,
  });
  Future<List<RealtimeConversationSessionView>> sessions();
  Future<List<RealtimeConversationItem>> turns(String sessionId);
  RealtimeConnectionRequest connectionRequest({
    required String profileId,
    required String language,
    required String instructions,
  });
  Future<void> saveSession(Map<String, dynamic> session);
  Future<void> saveTurn(Map<String, dynamic> turn);
  Future<RecordingAsset> createRecordingAsset(CreateRecordingAsset input);
  Future<void> deleteRecordingAsset(String id);
  Future<RecordingTranscriptionJobView> createTranscription({
    required String recordingId,
    required String modelId,
    required String language,
  });
  Future<RecordingTranscriptionJobView> transcriptionJob(String id);
}

class LocalRealtimeConversationRepository
    implements RealtimeConversationRepository {
  LocalRealtimeConversationRepository(this._getApi);

  final LocalApi Function() _getApi;
  LocalApi get _api => _getApi();

  @override
  Future<List<RealtimeProviderProfileView>> profiles() =>
      _api.realtimeProfiles();

  @override
  Future<RealtimeProviderProfileView> registerProfile({
    required String displayName,
    required String adapterKind,
    required String baseUrl,
    required String modelId,
    required String voice,
    required String secret,
  }) => _api.registerRealtimeProfile(
    displayName: displayName,
    adapterKind: adapterKind,
    baseUrl: baseUrl,
    modelId: modelId,
    voice: voice,
    secret: secret,
  );

  @override
  Future<List<RealtimeConversationSessionView>> sessions() =>
      _api.realtimeSessions();

  @override
  Future<List<RealtimeConversationItem>> turns(String sessionId) =>
      _api.realtimeTurns(sessionId);

  @override
  RealtimeConnectionRequest connectionRequest({
    required String profileId,
    required String language,
    required String instructions,
  }) => RealtimeConnectionRequest(
    uri: _api.realtimeSocketUri(
      profileId: profileId,
      language: language,
      instructions: instructions,
    ),
    headers: {'Authorization': 'Bearer ${_api.token}'},
  );

  @override
  Future<void> saveSession(Map<String, dynamic> session) =>
      _api.saveRealtimeSession(session);

  @override
  Future<void> saveTurn(Map<String, dynamic> turn) =>
      _api.saveRealtimeTurn(turn);

  @override
  Future<RecordingAsset> createRecordingAsset(CreateRecordingAsset input) =>
      _api.createRecordingAsset(input);

  @override
  Future<void> deleteRecordingAsset(String id) async {
    await _api.deleteRecordingAsset(id);
  }

  @override
  Future<RecordingTranscriptionJobView> createTranscription({
    required String recordingId,
    required String modelId,
    required String language,
  }) => _api.createRecordingTranscription(
    recordingId: recordingId,
    modelId: modelId,
    language: language,
  );

  @override
  Future<RecordingTranscriptionJobView> transcriptionJob(String id) =>
      _api.recordingTranscriptionJob(id);
}

class UnavailableRealtimeConversationRepository
    implements RealtimeConversationRepository {
  const UnavailableRealtimeConversationRepository();

  Never _unavailable() =>
      throw StateError('Realtime conversation repository is unavailable');

  @override
  RealtimeConnectionRequest connectionRequest({
    required String profileId,
    required String language,
    required String instructions,
  }) => _unavailable();
  @override
  Future<RecordingAsset> createRecordingAsset(CreateRecordingAsset input) =>
      _unavailable();
  @override
  Future<RecordingTranscriptionJobView> createTranscription({
    required String recordingId,
    required String modelId,
    required String language,
  }) => _unavailable();
  @override
  Future<void> deleteRecordingAsset(String id) => _unavailable();
  @override
  Future<List<RealtimeProviderProfileView>> profiles() => _unavailable();
  @override
  Future<RealtimeProviderProfileView> registerProfile({
    required String displayName,
    required String adapterKind,
    required String baseUrl,
    required String modelId,
    required String voice,
    required String secret,
  }) => _unavailable();
  @override
  Future<void> saveSession(Map<String, dynamic> session) => _unavailable();
  @override
  Future<void> saveTurn(Map<String, dynamic> turn) => _unavailable();
  @override
  Future<List<RealtimeConversationSessionView>> sessions() => _unavailable();
  @override
  Future<RecordingTranscriptionJobView> transcriptionJob(String id) =>
      _unavailable();
  @override
  Future<List<RealtimeConversationItem>> turns(String sessionId) =>
      _unavailable();
}
