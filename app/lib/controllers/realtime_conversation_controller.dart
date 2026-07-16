import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/practice.dart';
import '../models/realtime_conversation.dart';
import '../services/api_service.dart';
import '../services/realtime_audio_bridge.dart';
import 'speaking_task_controller.dart';

class RealtimeConversationState {
  const RealtimeConversationState({
    this.phase = 'idle',
    this.profiles = const [],
    this.selectedProfileId,
    this.providerTranscript = '',
    this.assistantTranscript = '',
    this.localTranscript = '',
    this.error,
  });
  final String phase;
  final List<RealtimeProviderProfileView> profiles;
  final String? selectedProfileId;
  final String providerTranscript;
  final String assistantTranscript;
  final String localTranscript;
  final String? error;
  RealtimeConversationState copyWith({
    String? phase,
    List<RealtimeProviderProfileView>? profiles,
    String? selectedProfileId,
    String? providerTranscript,
    String? assistantTranscript,
    String? localTranscript,
    Object? error = _unset,
  }) => RealtimeConversationState(
    phase: phase ?? this.phase,
    profiles: profiles ?? this.profiles,
    selectedProfileId: selectedProfileId ?? this.selectedProfileId,
    providerTranscript: providerTranscript ?? this.providerTranscript,
    assistantTranscript: assistantTranscript ?? this.assistantTranscript,
    localTranscript: localTranscript ?? this.localTranscript,
    error: identical(error, _unset) ? this.error : error as String?,
  );
}

const _unset = Object();

class RealtimeConversationController extends ChangeNotifier {
  RealtimeConversationController({RealtimeAudioBridge? audio})
    : _audio = audio ?? RealtimeAudioBridge();
  final RealtimeAudioBridge _audio;
  RealtimeConversationState state = const RealtimeConversationState();
  WebSocket? _socket;
  StreamSubscription? _audioSubscription;
  StreamSubscription? _socketSubscription;
  int _generation = 0;
  String? _sessionId;
  int? _sessionStartedAtMs;
  LocalApi? _activeApi;
  SpeakingTaskSource? _activeSource;
  Completer<void>? _responseDone;

  Future<void> loadProfiles(LocalApi api) async {
    try {
      final profiles = await api.realtimeProfiles();
      state = state.copyWith(
        profiles: profiles,
        selectedProfileId:
            state.selectedProfileId ??
            (profiles.isEmpty ? null : profiles.first.id),
        error: null,
      );
    } catch (error) {
      state = state.copyWith(
        error: 'Could not load realtime providers: $error',
      );
    }
    notifyListeners();
  }

  void selectProfile(String id) {
    state = state.copyWith(selectedProfileId: id);
    notifyListeners();
  }

  Future<void> registerProfile(
    LocalApi api, {
    required String displayName,
    required String adapterKind,
    required String baseUrl,
    required String modelId,
    required String voice,
    required String secret,
  }) async {
    final saved = await api.registerRealtimeProfile(
      displayName: displayName,
      adapterKind: adapterKind,
      baseUrl: baseUrl,
      modelId: modelId,
      voice: voice,
      secret: secret,
    );
    final profiles = await api.realtimeProfiles();
    state = state.copyWith(
      profiles: profiles,
      selectedProfileId: saved.id,
      error: null,
    );
    notifyListeners();
  }

  Future<void> start(
    LocalApi api,
    SpeakingTaskSource source, {
    required Future<void> Function() acquireAudioFocus,
  }) async {
    final profileId = state.selectedProfileId;
    if (profileId == null) {
      state = state.copyWith(
        error: 'Add and select a realtime provider first.',
      );
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(
      phase: 'connecting',
      providerTranscript: '',
      assistantTranscript: '',
      localTranscript: '',
      error: null,
    );
    notifyListeners();
    try {
      await acquireAudioFocus();
      final socket = await WebSocket.connect(
        api
            .realtimeSocketUri(
              profileId: profileId,
              language: source.language,
              instructions:
                  'Discuss the anchored source meaning naturally. Do not merely recite it. Source: ${source.transcriptSnapshot}',
            )
            .toString(),
        headers: {HttpHeaders.authorizationHeader: 'Bearer ${api.token}'},
      );
      if (generation != _generation) {
        await socket.close();
        return;
      }
      _socket = socket;
      _socketSubscription = socket.listen(
        _onSocketMessage,
        onError: (Object error) {
          unawaited(_failAndCleanup('Realtime connection failed: $error'));
        },
        onDone: () {
          if (state.phase == 'live') {
            unawaited(_failAndCleanup('Realtime provider disconnected.'));
          }
        },
      );
      await _audio.start();
      _audioSubscription = _audio.pcmInput.listen((pcm) {
        if (_socket?.readyState == WebSocket.open) _socket!.add(pcm);
      });
      final now = DateTime.now().millisecondsSinceEpoch;
      _sessionId = 'realtime-$now-${DateTime.now().microsecondsSinceEpoch}';
      _sessionStartedAtMs = now;
      _activeApi = api;
      _activeSource = source;
      await api.saveRealtimeSession(
        _sessionJson(
          source: source,
          profileId: profileId,
          status: 'active',
          startedAtMs: now,
        ),
      );
      state = state.copyWith(phase: 'live');
      notifyListeners();
    } catch (error) {
      await _cleanup(discard: true);
      state = state.copyWith(
        phase: 'failed',
        error: 'Could not start realtime conversation: $error',
      );
      notifyListeners();
    }
  }

  void _onSocketMessage(Object? message) {
    if (message is List<int>) {
      unawaited(_audio.play(Uint8List.fromList(message)));
      return;
    }
    if (message is! String) return;
    final value = jsonDecode(message) as Map<String, dynamic>;
    switch (value['type']) {
      case 'provider_transcript_preview':
        state = state.copyWith(
          providerTranscript: value['text'] as String? ?? '',
        );
      case 'provider_transcript_final':
        state = state.copyWith(
          providerTranscript: value['transcript'] as String? ?? '',
        );
      case 'assistant_transcript_delta':
        state = state.copyWith(
          assistantTranscript:
              state.assistantTranscript + (value['delta'] as String? ?? ''),
        );
      case 'assistant_transcript_final':
        state = state.copyWith(
          assistantTranscript:
              value['transcript'] as String? ?? state.assistantTranscript,
        );
      case 'speech_started':
        unawaited(_audio.stopPlayback());
        _socket?.add('cancel');
      case 'response_done':
        if (_responseDone?.isCompleted == false) _responseDone!.complete();
      case 'provider_error' || 'connection_failed':
        unawaited(_failAndCleanup(value['error'].toString()));
    }
    notifyListeners();
  }

  Future<void> finish(
    LocalApi api,
    SpeakingTaskSource source,
    String modelId,
  ) async {
    if (state.phase != 'live') return;
    state = state.copyWith(phase: 'transcribing', error: null);
    notifyListeners();
    try {
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      final captured = await _audio.stop();
      _responseDone = Completer<void>();
      _socket?.add('commit');
      await _responseDone!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
      await _socket?.close();
      _socket = null;
      await _audio.shutdown();
      final asset = await api.createRecordingAsset(
        CreateRecordingAsset(
          filePath: captured.path,
          durationMs: captured.durationMs,
          target: PracticeTarget(
            kind: 'segment',
            startMs: source.startMs,
            endMs: source.endMs,
          ),
          sourceSegment: PlayableSegment(
            mediaId: source.mediaId,
            startMs: source.startMs,
            endMs: source.endMs,
            label: 'realtime conversation source',
            subtitleSnapshot: source.transcriptSnapshot,
            availability: source.mediaId == null
                ? 'missing_media'
                : 'available',
          ),
          language: source.language,
          audio: RecordingAudioMetadata(
            container: 'wav',
            codec: 'pcm_s16le',
            sampleRateHz: 16000,
            channels: 1,
            sampleFormat: 's16',
            byteLength: captured.byteLength,
            contentSha256: captured.contentSha256,
          ),
          recorderVersion: 'macos-avfoundation-realtime-dual-pcm-v1',
        ),
      );
      var job = await api.createRecordingTranscription(
        recordingId: asset.id,
        modelId: modelId,
        language: source.language,
      );
      while (job.status != 'completed' &&
          job.status != 'failed' &&
          job.status != 'cancelled') {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        job = await api.recordingTranscriptionJob(job.id);
      }
      final local = job.status == 'completed'
          ? (job.rawTranscript?.trim() ?? '')
          : '';
      final endedAt = DateTime.now().millisecondsSinceEpoch;
      if (local.isNotEmpty &&
          _sessionId != null &&
          _sessionStartedAtMs != null) {
        await api.saveRealtimeTurn({
          'id': '${_sessionId!}-learner-1',
          'session_id': _sessionId,
          'sequence': 1,
          'role': 'learner',
          'status': 'finalized',
          'assistance': 'content_anchored',
          'provider_transcript': state.providerTranscript.isEmpty
              ? null
              : {
                  'text': state.providerTranscript,
                  'provider_item_id': null,
                  'received_at_ms': endedAt,
                },
          'local_transcript': {
            'text': local,
            'recording_asset_id': asset.id,
            'transcription_job_id': job.id,
            'completed_at_ms': endedAt,
          },
          'recording_asset_id': asset.id,
          'started_at_ms': _sessionStartedAtMs,
          'ended_at_ms': endedAt,
          'failure_kind': null,
        });
      }
      await _persistTerminalSession(
        status: local.isEmpty ? 'failed' : 'completed',
        failureKind: local.isEmpty ? 'local_transcription_failed' : null,
        endedAtMs: endedAt,
      );
      state = state.copyWith(
        phase: local.isEmpty ? 'failed' : 'done',
        localTranscript: local,
        error: local.isEmpty
            ? (job.errorMessage ??
                  'Local transcription did not produce learner text; nothing is eligible for corpus.')
            : null,
      );
    } catch (error) {
      await _persistTerminalSession(
        status: 'failed',
        failureKind: 'finalization_failed',
        endedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      state = state.copyWith(
        phase: 'failed',
        error: 'Could not finalize local learner transcript: $error',
      );
    }
    notifyListeners();
  }

  Future<void> cancel() async {
    ++_generation;
    await _cleanup(discard: true);
    await _persistTerminalSession(
      status: 'interrupted',
      failureKind: 'user_cancelled',
      endedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    state = state.copyWith(phase: 'idle', error: null);
    notifyListeners();
  }

  Map<String, dynamic> _sessionJson({
    required SpeakingTaskSource source,
    required String profileId,
    required String status,
    required int startedAtMs,
    int? endedAtMs,
    String? failureKind,
  }) => {
    'id': _sessionId,
    'profile_id': profileId,
    'language': source.language,
    'context': {
      'surface_kind': 'content_anchored_speaking',
      'content_anchor': source.mediaId == null
          ? null
          : {
              'media_id': source.mediaId,
              'start_ms': source.startMs,
              'end_ms': source.endMs,
              'source_text': source.transcriptSnapshot,
            },
    },
    'status': status,
    'started_at_ms': startedAtMs,
    'ended_at_ms': endedAtMs,
    'failure_kind': failureKind,
  };

  Future<void> _persistTerminalSession({
    required String status,
    required String? failureKind,
    required int endedAtMs,
  }) async {
    final api = _activeApi;
    final source = _activeSource;
    final startedAt = _sessionStartedAtMs;
    final profileId = state.selectedProfileId;
    if (api != null &&
        source != null &&
        _sessionId != null &&
        startedAt != null &&
        profileId != null) {
      try {
        await api.saveRealtimeSession(
          _sessionJson(
            source: source,
            profileId: profileId,
            status: status,
            startedAtMs: startedAt,
            endedAtMs: endedAtMs,
            failureKind: failureKind,
          ),
        );
      } catch (_) {
        // Audio/socket cleanup must still succeed when persistence is unavailable.
      }
    }
    _sessionId = null;
    _sessionStartedAtMs = null;
    _activeApi = null;
    _activeSource = null;
  }

  Future<void> _cleanup({required bool discard}) async {
    await _audioSubscription?.cancel();
    await _socketSubscription?.cancel();
    _audioSubscription = null;
    _socketSubscription = null;
    if (discard) await _audio.cancel();
    await _socket?.close();
    _socket = null;
  }

  Future<void> _failAndCleanup(String message) async {
    await _cleanup(discard: true);
    await _persistTerminalSession(
      status: 'failed',
      failureKind: 'provider_connection_failed',
      endedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    state = state.copyWith(phase: 'failed', error: message);
    notifyListeners();
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(_disposeActiveSession());
    super.dispose();
  }

  Future<void> _disposeActiveSession() async {
    await _cleanup(discard: true);
    await _persistTerminalSession(
      status: 'interrupted',
      failureKind: 'surface_disposed',
      endedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
