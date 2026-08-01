import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/settings_repository.dart';
import '../models/api_failure.dart';
import '../models/llm_provider.dart';
import '../models/named_failure.dart';
import '../models/realtime_conversation.dart';
import '../models/syntax_capability.dart';

enum LlmProbeStatus { probing, supported, unsupported, failed }

@immutable
class LlmProviderFormInput {
  LlmProviderFormInput({
    required this.displayName,
    required this.adapterKind,
    required this.baseUrl,
    required this.modelId,
    required List<String> allowedUses,
    required this.secret,
  }) : allowedUses = List.unmodifiable(allowedUses);

  final String displayName;
  final String adapterKind;
  final String baseUrl;
  final String modelId;
  final List<String> allowedUses;
  final String secret;
}

@immutable
class LlmProviderSettingsState {
  LlmProviderSettingsState({
    required List<LlmProviderProfileView> providers,
    required this.loading,
    required this.submitting,
    required this.failure,
    required Map<String, LlmProbeStatus> probeStatuses,
    required Set<String> deletingIds,
  }) : providers = List.unmodifiable(providers),
       probeStatuses = Map.unmodifiable(probeStatuses),
       deletingIds = Set.unmodifiable(deletingIds);

  final List<LlmProviderProfileView> providers;
  final bool loading;
  final bool submitting;
  final NamedFailure? failure;
  final Map<String, LlmProbeStatus> probeStatuses;
  final Set<String> deletingIds;
}

class LlmProviderSettingsViewModel extends ChangeNotifier {
  LlmProviderSettingsViewModel(this._repository);

  final LlmProviderRepository _repository;
  List<LlmProviderProfileView> _providers = const [];
  bool _loading = true;
  bool _submitting = false;
  NamedFailure? _failure;
  final Map<String, LlmProbeStatus> _probeStatuses = {};
  final Set<String> _deletingIds = {};
  bool _disposed = false;
  int _loadGeneration = 0;

  LlmProviderSettingsState get state => LlmProviderSettingsState(
    providers: _providers,
    loading: _loading,
    submitting: _submitting,
    failure: _failure,
    probeStatuses: _probeStatuses,
    deletingIds: _deletingIds,
  );

  Future<void> load() async {
    final generation = ++_loadGeneration;
    _loading = true;
    _failure = null;
    _notify();
    try {
      final providers = await _repository.list();
      if (_disposed || generation != _loadGeneration) return;
      _providers = List.unmodifiable(providers);
    } on ApiFailure catch (failure) {
      if (_disposed || generation != _loadGeneration) return;
      _failure = NamedFailure('llmProvidersLoadFailed', detail: failure);
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<bool> register(LlmProviderFormInput input) async {
    if (_submitting) return false;
    _submitting = true;
    _failure = null;
    _notify();
    try {
      await _repository.register(
        LlmProviderDraft(
          displayName: input.displayName,
          adapterKind: input.adapterKind,
          baseUrl: input.baseUrl,
          modelId: input.modelId,
          allowedUses: List.unmodifiable(input.allowedUses),
          secret: input.secret,
        ),
      );
      if (_disposed) return false;
      await load();
      return true;
    } on ApiFailure catch (failure) {
      if (_disposed) return false;
      _failure = NamedFailure('llmProviderSaveFailed', detail: failure);
      return false;
    } finally {
      if (!_disposed) {
        _submitting = false;
        _notify();
      }
    }
  }

  Future<void> delete(String id) async {
    if (!_deletingIds.add(id)) return;
    _failure = null;
    _notify();
    try {
      await _repository.delete(id);
      if (_disposed) return;
      await load();
    } on ApiFailure catch (failure) {
      if (_disposed) return;
      _failure = NamedFailure('llmProviderRemoveFailed', detail: failure);
    } finally {
      _deletingIds.remove(id);
      _notify();
    }
  }

  Future<void> probe(String id) async {
    if (_probeStatuses[id] == LlmProbeStatus.probing) return;
    _probeStatuses[id] = LlmProbeStatus.probing;
    _notify();
    try {
      final result = await _repository.probe(id);
      if (_disposed) return;
      _probeStatuses[id] = result.structuredOutput.isProbedSupported
          ? LlmProbeStatus.supported
          : LlmProbeStatus.unsupported;
    } catch (_) {
      _probeStatuses[id] = LlmProbeStatus.failed;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

@immutable
class RealtimeProviderFormInput {
  const RealtimeProviderFormInput({
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

@immutable
class RealtimeProviderSettingsState {
  RealtimeProviderSettingsState({
    required List<RealtimeProviderProfileView> profiles,
    required this.loading,
    required this.submitting,
    required this.failure,
    required Set<String> deletingIds,
  }) : profiles = List.unmodifiable(profiles),
       deletingIds = Set.unmodifiable(deletingIds);

  final List<RealtimeProviderProfileView> profiles;
  final bool loading;
  final bool submitting;
  final NamedFailure? failure;
  final Set<String> deletingIds;
}

class RealtimeProviderSettingsViewModel extends ChangeNotifier {
  RealtimeProviderSettingsViewModel(this._repository);

  final RealtimeProviderRepository _repository;
  List<RealtimeProviderProfileView> _profiles = const [];
  bool _loading = true;
  bool _submitting = false;
  NamedFailure? _failure;
  final Set<String> _deletingIds = {};
  bool _disposed = false;
  int _loadGeneration = 0;

  RealtimeProviderSettingsState get state => RealtimeProviderSettingsState(
    profiles: _profiles,
    loading: _loading,
    submitting: _submitting,
    failure: _failure,
    deletingIds: _deletingIds,
  );

  Future<void> load() async {
    final generation = ++_loadGeneration;
    _loading = true;
    _failure = null;
    _notify();
    try {
      final profiles = await _repository.list();
      if (_disposed || generation != _loadGeneration) return;
      _profiles = List.unmodifiable(profiles);
    } on ApiFailure catch (failure) {
      if (_disposed || generation != _loadGeneration) return;
      _failure = NamedFailure('realtimeProvidersLoadFailed', detail: failure);
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<bool> register(RealtimeProviderFormInput input) async {
    if (_submitting) return false;
    _submitting = true;
    _failure = null;
    _notify();
    try {
      await _repository.register(
        RealtimeProviderDraft(
          displayName: input.displayName,
          adapterKind: input.adapterKind,
          baseUrl: input.baseUrl,
          modelId: input.modelId,
          voice: input.voice,
          secret: input.secret,
        ),
      );
      if (_disposed) return false;
      await load();
      return true;
    } on ApiFailure catch (failure) {
      if (_disposed) return false;
      _failure = NamedFailure('realtimeProviderSaveFailed', detail: failure);
      return false;
    } finally {
      if (!_disposed) {
        _submitting = false;
        _notify();
      }
    }
  }

  Future<void> delete(String id) async {
    if (!_deletingIds.add(id)) return;
    _failure = null;
    _notify();
    try {
      await _repository.delete(id);
      if (_disposed) return;
      await load();
    } on ApiFailure catch (failure) {
      if (_disposed) return;
      _failure = NamedFailure('realtimeProviderRemoveFailed', detail: failure);
    } finally {
      _deletingIds.remove(id);
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

@immutable
class SyntaxCapabilitySettingsState {
  const SyntaxCapabilitySettingsState({
    required this.capability,
    required this.track,
    required this.failure,
    required this.busy,
  });

  final SyntaxCapabilityView? capability;
  final TrackSyntaxAnalysisView? track;
  final NamedFailure? failure;
  final bool busy;
}

class SyntaxCapabilitySettingsViewModel extends ChangeNotifier {
  SyntaxCapabilitySettingsViewModel(
    this._repository, {
    this.currentTrackId,
    this.pollInterval = const Duration(seconds: 1),
  });

  final SyntaxCapabilityRepository _repository;
  final String? currentTrackId;
  final Duration pollInterval;
  SyntaxCapabilityView? _capability;
  TrackSyntaxAnalysisView? _track;
  NamedFailure? _failure;
  bool _busy = false;
  Timer? _poller;
  bool _disposed = false;
  int _refreshGeneration = 0;

  SyntaxCapabilitySettingsState get state => SyntaxCapabilitySettingsState(
    capability: _capability,
    track: _track,
    failure: _failure,
    busy: _busy,
  );

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    try {
      final next = await _repository.readCapability();
      if (_disposed || generation != _refreshGeneration) return;
      final becameReady = _capability?.isReady != true && next.isReady;
      _capability = next;
      _failure = null;
      _syncPoller(next);
      _notify();
      if (becameReady && currentTrackId != null) {
        await analyze(force: false);
      }
    } on ApiFailure catch (failure) {
      if (_disposed || generation != _refreshGeneration) return;
      _failure = NamedFailure('syntaxCapabilityLoadFailed', detail: failure);
      _notify();
    }
  }

  Future<void> runAction(String action) async {
    if (_busy) return;
    _refreshGeneration++;
    _busy = true;
    _failure = null;
    _notify();
    try {
      final capability = await _repository.runAction(action);
      if (_disposed) return;
      _capability = capability;
      _busy = false;
      _notify();
      await refresh();
    } on ApiFailure catch (failure) {
      if (_disposed) return;
      _busy = false;
      _failure = NamedFailure('syntaxCapabilityActionFailed', detail: failure);
      _notify();
    }
  }

  Future<void> analyze({required bool force}) async {
    final trackId = currentTrackId;
    if (trackId == null || _busy) return;
    _busy = true;
    _failure = null;
    _notify();
    try {
      final track = await _repository.analyzeTrack(trackId, force: force);
      if (_disposed) return;
      _track = track;
      _busy = false;
      _notify();
    } on ApiFailure catch (failure) {
      if (_disposed) return;
      _busy = false;
      _failure = NamedFailure('syntaxTrackAnalysisFailed', detail: failure);
      _notify();
    }
  }

  void _syncPoller(SyntaxCapabilityView capability) {
    if (capability.isDownloading) {
      _poller ??= Timer.periodic(pollInterval, (_) => unawaited(refresh()));
    } else {
      _poller?.cancel();
      _poller = null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poller?.cancel();
    super.dispose();
  }
}

@immutable
class LearnerSettingsState {
  const LearnerSettingsState({required this.l1Language});

  final String l1Language;
}

class LearnerSettingsViewModel extends ChangeNotifier {
  LearnerSettingsViewModel(this._repository);

  final LearnerSettingsRepository _repository;
  String _l1Language = '';
  bool _disposed = false;

  LearnerSettingsState get state =>
      LearnerSettingsState(l1Language: _l1Language);

  /// Profile settings are optional when the sidecar is unavailable. The
  /// dialog still opens with an unset language, preserving the existing
  /// best-effort behavior.
  Future<void> load() async {
    try {
      final profile = await _repository.readProfile();
      if (_disposed) return;
      _l1Language = profile.l1Language ?? '';
      notifyListeners();
    } catch (_) {
      // Deliberately degrade to the empty value.
    }
  }

  Future<void> updateL1Language(String value, {required String uiLanguage}) =>
      _repository.updateProfile(
        l1Language: value.isEmpty ? null : value,
        uiLanguage: uiLanguage == 'system' ? null : uiLanguage,
      );

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
