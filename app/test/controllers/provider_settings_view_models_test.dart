import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/provider_settings_view_models.dart';
import 'package:llplayer_next/data/repositories/settings_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/llm_provider.dart';
import 'package:llplayer_next/models/realtime_conversation.dart';
import 'package:llplayer_next/models/syntax_capability.dart';

void main() {
  group('LlmProviderSettingsViewModel', () {
    test(
      'ignores an older load that completes after the latest load',
      () async {
        final repository = _LlmRepository();
        final first = Completer<List<LlmProviderProfileView>>();
        final second = Completer<List<LlmProviderProfileView>>();
        repository.loads.addAll([first, second]);
        final viewModel = LlmProviderSettingsViewModel(repository);

        final firstLoad = viewModel.load();
        final secondLoad = viewModel.load();
        second.complete([_llmProvider('new')]);
        await secondLoad;
        first.complete([_llmProvider('old')]);
        await firstLoad;

        expect(viewModel.providers.single.id, 'new');
        expect(
          () => viewModel.providers.add(_llmProvider('extra')),
          throwsA(isA<UnsupportedError>()),
        );
        viewModel.dispose();
      },
    );

    test('register reloads providers and never retains the secret', () async {
      final repository = _LlmRepository()
        ..immediateLoad = [_llmProvider('saved')];
      final viewModel = LlmProviderSettingsViewModel(repository);
      const draft = LlmProviderDraft(
        displayName: 'Provider',
        adapterKind: 'openai_chat_completions',
        baseUrl: 'https://example.test/v1',
        modelId: 'model',
        allowedUses: ['semantic_judgment'],
        secret: 'write-only',
      );

      expect(await viewModel.register(draft), isTrue);
      expect(viewModel.providers.single.id, 'saved');
      expect(repository.registered, same(draft));
      expect(viewModel.submitting, isFalse);
      viewModel.dispose();
    });
  });

  test('realtime provider failure is exposed as a named state', () async {
    final repository = _RealtimeRepository()
      ..loadError = const ApiFailure(
        raw: 'down',
        code: 'temporarily_unavailable',
      );
    final viewModel = RealtimeProviderSettingsViewModel(repository);

    await viewModel.load();

    expect(viewModel.loading, isFalse);
    expect(viewModel.failure?.messageKey, 'realtimeProvidersLoadFailed');
    expect(viewModel.failure?.detail?.code, 'temporarily_unavailable');
    viewModel.dispose();
  });

  test('ready syntax capability analyzes the current track once', () async {
    final repository = _SyntaxRepository();
    final viewModel = SyntaxCapabilitySettingsViewModel(
      repository,
      currentTrackId: 'track-1',
    );

    await viewModel.refresh();

    expect(repository.analyzedTracks, ['track-1']);
    expect(viewModel.track?.analyzedSentenceCount, 2);
    expect(viewModel.busy, isFalse);
    viewModel.dispose();
  });
}

LlmProviderProfileView _llmProvider(String id) => LlmProviderProfileView(
  id: id,
  displayName: id,
  adapterKind: 'openai_chat_completions',
  baseUrl: 'https://example.test/v1',
  modelId: 'model',
  hasCredential: true,
  timeoutMs: 1000,
  maxRetries: 0,
  retention: 'unknown',
  allowedUses: const ['semantic_judgment'],
  capability: const LlmProviderCapability(
    structuredOutput: LlmCapabilityClaim(state: 'unknown'),
    streaming: LlmCapabilityClaim(state: 'unknown'),
    multilingual: LlmCapabilityClaim(state: 'unknown'),
    audioInput: LlmCapabilityClaim(state: 'unknown'),
  ),
  createdAtMs: 1,
);

class _LlmRepository implements LlmProviderRepository {
  final List<Completer<List<LlmProviderProfileView>>> loads = [];
  List<LlmProviderProfileView>? immediateLoad;
  LlmProviderDraft? registered;

  @override
  Future<List<LlmProviderProfileView>> list() {
    if (loads.isNotEmpty) return loads.removeAt(0).future;
    return Future.value(immediateLoad ?? const []);
  }

  @override
  Future<LlmProviderProfileView> register(LlmProviderDraft draft) async {
    registered = draft;
    return _llmProvider('saved');
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<LlmProbeResult> probe(String id) async => const LlmProbeResult(
    structuredOutput: LlmCapabilityClaim(state: 'probed', supported: true),
  );
}

class _RealtimeRepository implements RealtimeProviderRepository {
  Object? loadError;

  @override
  Future<List<RealtimeProviderProfileView>> list() async {
    if (loadError case final error?) throw error;
    return const [];
  }

  @override
  Future<RealtimeProviderProfileView> register(RealtimeProviderDraft draft) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) async {}
}

class _SyntaxRepository implements SyntaxCapabilityRepository {
  final List<String> analyzedTracks = [];

  @override
  Future<SyntaxCapabilityView> readCapability() async => _readyCapability;

  @override
  Future<SyntaxCapabilityView> runAction(String action) async =>
      _readyCapability;

  @override
  Future<TrackSyntaxAnalysisView> analyzeTrack(
    String trackId, {
    required bool force,
  }) async {
    analyzedTracks.add(trackId);
    return const TrackSyntaxAnalysisView(
      status: 'ready',
      fingerprint: 'fingerprint',
      cacheHit: false,
      sentenceCount: 2,
      analyzedSentenceCount: 2,
      fallbackSentenceCount: 0,
    );
  }
}

const _readyCapability = SyntaxCapabilityView(
  status: 'ready',
  progress: 1,
  enabled: true,
  runtimeVersion: '3.8.13',
  providerVersion: 'jsonl-v2',
  modelVersion: '3.8.0',
  modelChecksumSha256: 'model',
  expectedInstallBytes: 1,
  deliveryChecksumSha256: 'delivery',
  installedBytes: 1,
  error: null,
);
