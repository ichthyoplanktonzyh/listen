import '../../models/api_failure.dart';
import '../../models/llm_provider.dart';
import '../../models/realtime_conversation.dart';
import '../../models/syntax_capability.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';

Future<T> _request<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(describeApiFailure(error), stackTrace);
  }
}

class LlmProviderDraft {
  const LlmProviderDraft({
    required this.displayName,
    required this.adapterKind,
    required this.baseUrl,
    required this.modelId,
    required this.allowedUses,
    this.secret,
  });

  final String displayName;
  final String adapterKind;
  final String baseUrl;
  final String modelId;
  final List<String> allowedUses;
  final String? secret;
}

abstract class LlmProviderRepository {
  /// Every failed operation throws an [ApiFailure], never a transport error.
  Future<List<LlmProviderProfileView>> list();
  Future<LlmProviderProfileView> register(LlmProviderDraft draft);
  Future<void> delete(String id);
  Future<LlmProbeResult> probe(String id);
}

class LocalLlmProviderRepository implements LlmProviderRepository {
  LocalLlmProviderRepository(this._api);

  final LocalApi _api;

  @override
  Future<List<LlmProviderProfileView>> list() =>
      _request(_api.listLlmProviders);

  @override
  Future<LlmProviderProfileView> register(LlmProviderDraft draft) => _request(
    () => _api.registerLlmProvider(
      displayName: draft.displayName,
      adapterKind: draft.adapterKind,
      baseUrl: draft.baseUrl,
      modelId: draft.modelId,
      allowedUses: draft.allowedUses,
      secret: draft.secret,
    ),
  );

  @override
  Future<void> delete(String id) => _request(() => _api.deleteLlmProvider(id));

  @override
  Future<LlmProbeResult> probe(String id) =>
      _request(() => _api.probeLlmProvider(id));
}

class RealtimeProviderDraft {
  const RealtimeProviderDraft({
    required this.displayName,
    required this.adapterKind,
    required this.baseUrl,
    required this.modelId,
    required this.voice,
    required this.secret,
  });

  final String displayName;
  final String adapterKind;
  final String baseUrl;
  final String modelId;
  final String voice;
  final String secret;
}

abstract class RealtimeProviderRepository {
  /// Every failed operation throws an [ApiFailure], never a transport error.
  Future<List<RealtimeProviderProfileView>> list();
  Future<RealtimeProviderProfileView> register(RealtimeProviderDraft draft);
  Future<void> delete(String id);
}

class LocalRealtimeProviderRepository implements RealtimeProviderRepository {
  LocalRealtimeProviderRepository(this._api);

  final LocalApi _api;

  @override
  Future<List<RealtimeProviderProfileView>> list() =>
      _request(_api.realtimeProfiles);

  @override
  Future<RealtimeProviderProfileView> register(RealtimeProviderDraft draft) =>
      _request(
        () => _api.registerRealtimeProfile(
          displayName: draft.displayName,
          adapterKind: draft.adapterKind,
          baseUrl: draft.baseUrl,
          modelId: draft.modelId,
          voice: draft.voice,
          secret: draft.secret,
        ),
      );

  @override
  Future<void> delete(String id) =>
      _request(() => _api.deleteRealtimeProfile(id));
}

abstract class SyntaxCapabilityRepository {
  /// Every failed operation throws an [ApiFailure], never a transport error.
  Future<SyntaxCapabilityView> readCapability();
  Future<SyntaxCapabilityView> runAction(String action);
  Future<TrackSyntaxAnalysisView> analyzeTrack(
    String trackId, {
    required bool force,
  });
}

class LocalSyntaxCapabilityRepository implements SyntaxCapabilityRepository {
  LocalSyntaxCapabilityRepository(this._api);

  final LocalApi _api;

  @override
  Future<SyntaxCapabilityView> readCapability() =>
      _request(_api.syntaxCapability);

  @override
  Future<SyntaxCapabilityView> runAction(String action) =>
      _request(() => _api.syntaxCapabilityAction(action));

  @override
  Future<TrackSyntaxAnalysisView> analyzeTrack(
    String trackId, {
    required bool force,
  }) => _request(() => _api.runTrackSyntaxAnalysis(trackId, force: force));
}

abstract class LearnerSettingsRepository {
  /// Every failed operation throws an [ApiFailure], never a transport error.
  Future<LearnerProfileView> readProfile();
  Future<LearnerProfileView> updateProfile({
    String? l1Language,
    String? uiLanguage,
  });
}

class LocalLearnerSettingsRepository implements LearnerSettingsRepository {
  LocalLearnerSettingsRepository(this._api);

  final LocalApi _api;

  @override
  Future<LearnerProfileView> readProfile() => _request(_api.learnerProfile);

  @override
  Future<LearnerProfileView> updateProfile({
    String? l1Language,
    String? uiLanguage,
  }) => _request(
    () => _api.updateLearnerProfile(
      l1Language: l1Language,
      uiLanguage: uiLanguage,
    ),
  );
}
