import '../../models/llm_provider.dart';
import '../../models/realtime_conversation.dart';
import '../../models/syntax_capability.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';

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
  Future<List<LlmProviderProfileView>> list();
  Future<LlmProviderProfileView> register(LlmProviderDraft draft);
  Future<void> delete(String id);
  Future<LlmProbeResult> probe(String id);
}

class LocalLlmProviderRepository implements LlmProviderRepository {
  LocalLlmProviderRepository(this._api);

  final LocalApi _api;

  @override
  Future<List<LlmProviderProfileView>> list() => _api.listLlmProviders();

  @override
  Future<LlmProviderProfileView> register(LlmProviderDraft draft) =>
      _api.registerLlmProvider(
        displayName: draft.displayName,
        adapterKind: draft.adapterKind,
        baseUrl: draft.baseUrl,
        modelId: draft.modelId,
        allowedUses: draft.allowedUses,
        secret: draft.secret,
      );

  @override
  Future<void> delete(String id) => _api.deleteLlmProvider(id);

  @override
  Future<LlmProbeResult> probe(String id) => _api.probeLlmProvider(id);
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
  Future<List<RealtimeProviderProfileView>> list();
  Future<RealtimeProviderProfileView> register(RealtimeProviderDraft draft);
  Future<void> delete(String id);
}

class LocalRealtimeProviderRepository implements RealtimeProviderRepository {
  LocalRealtimeProviderRepository(this._api);

  final LocalApi _api;

  @override
  Future<List<RealtimeProviderProfileView>> list() => _api.realtimeProfiles();

  @override
  Future<RealtimeProviderProfileView> register(RealtimeProviderDraft draft) =>
      _api.registerRealtimeProfile(
        displayName: draft.displayName,
        adapterKind: draft.adapterKind,
        baseUrl: draft.baseUrl,
        modelId: draft.modelId,
        voice: draft.voice,
        secret: draft.secret,
      );

  @override
  Future<void> delete(String id) => _api.deleteRealtimeProfile(id);
}

abstract class SyntaxCapabilityRepository {
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
  Future<SyntaxCapabilityView> readCapability() => _api.syntaxCapability();

  @override
  Future<SyntaxCapabilityView> runAction(String action) =>
      _api.syntaxCapabilityAction(action);

  @override
  Future<TrackSyntaxAnalysisView> analyzeTrack(
    String trackId, {
    required bool force,
  }) => _api.runTrackSyntaxAnalysis(trackId, force: force);
}

abstract class LearnerSettingsRepository {
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
  Future<LearnerProfileView> readProfile() => _api.learnerProfile();

  @override
  Future<LearnerProfileView> updateProfile({
    String? l1Language,
    String? uiLanguage,
  }) =>
      _api.updateLearnerProfile(l1Language: l1Language, uiLanguage: uiLanguage);
}
