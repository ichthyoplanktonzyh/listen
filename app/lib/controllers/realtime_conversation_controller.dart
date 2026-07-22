import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/practice.dart';
import '../models/realtime_conversation.dart';
import '../services/api_service.dart';
import '../services/realtime_audio_bridge.dart';
import '../services/shadowing_recorder.dart';
import 'realtime_turn_assembler.dart';

abstract interface class RealtimeConnection {
  Stream<Object?> get messages;
  bool get isOpen;
  void send(Object data);
  Future<void> close();
}

typedef RealtimeConnectionFactory =
    Future<RealtimeConnection> Function(Uri uri, Map<String, dynamic> headers);

class _IoRealtimeConnection implements RealtimeConnection {
  _IoRealtimeConnection(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get messages => _socket;

  @override
  bool get isOpen => _socket.readyState == WebSocket.open;

  @override
  void send(Object data) => _socket.add(data);

  @override
  Future<void> close() async {
    await _socket.close();
  }
}

Future<RealtimeConnection> _connectRealtime(
  Uri uri,
  Map<String, dynamic> headers,
) async => _IoRealtimeConnection(
  await WebSocket.connect(uri.toString(), headers: headers),
);

class RealtimeConversationLaunch {
  const RealtimeConversationLaunch({
    required this.mode,
    required this.language,
    required this.modelId,
    this.anchor,
  });

  factory RealtimeConversationLaunch.topic({
    required RealtimeConversationAnchor anchor,
    required String modelId,
  }) => RealtimeConversationLaunch(
    mode: RealtimeConversationMode.topicAnchored,
    language: anchor.language,
    modelId: modelId,
    anchor: anchor,
  );

  factory RealtimeConversationLaunch.free({
    required String language,
    required String modelId,
  }) => RealtimeConversationLaunch(
    mode: RealtimeConversationMode.free,
    language: language,
    modelId: modelId,
  );

  final RealtimeConversationMode mode;
  final String language;
  final String modelId;
  final RealtimeConversationAnchor? anchor;
}

/// Explicit bounded context for a topic-anchored conversation.
///
/// This type deliberately belongs to Realtime rather than Speaking: selecting
/// content may launch either a retelling task or a conversation, but neither
/// activity owns the other's prompt type.
class RealtimeConversationAnchor {
  const RealtimeConversationAnchor({
    required this.language,
    required this.text,
    this.mediaId,
    this.startMs = 0,
    this.endMs = 0,
  });

  final String language;
  final String text;
  final String? mediaId;
  final int startMs;
  final int endMs;
}

enum RealtimeConversationPhase {
  idle,
  connecting,
  live,
  draining,
  postProcessing,
  done,
  failed,
}

enum RealtimeConversationActivity {
  inactive,
  listening,
  learnerSpeaking,
  thinking,
  assistantSpeaking,
}

class RealtimeConversationState {
  const RealtimeConversationState({
    this.phase = RealtimeConversationPhase.idle,
    this.activity = RealtimeConversationActivity.inactive,
    this.profiles = const [],
    this.selectedProfileId,
    this.mode = RealtimeConversationMode.topicAnchored,
    this.items = const [],
    this.postProcessingCount = 0,
    this.historySessions = const [],
    this.historyItems = const [],
    this.selectedHistorySessionId,
    this.historyLoading = false,
    this.historyError,
    this.error,
  });

  final RealtimeConversationPhase phase;
  final RealtimeConversationActivity activity;
  final List<RealtimeProviderProfileView> profiles;
  final String? selectedProfileId;
  final RealtimeConversationMode mode;
  final List<RealtimeConversationItem> items;
  final int postProcessingCount;
  final List<RealtimeConversationSessionView> historySessions;
  final List<RealtimeConversationItem> historyItems;
  final String? selectedHistorySessionId;
  final bool historyLoading;
  final String? historyError;
  final String? error;

  bool get canConfigure =>
      phase == RealtimeConversationPhase.idle ||
      phase == RealtimeConversationPhase.done ||
      phase == RealtimeConversationPhase.failed;

  bool get canCancel =>
      phase == RealtimeConversationPhase.connecting ||
      phase == RealtimeConversationPhase.live;

  bool get isWorking =>
      phase == RealtimeConversationPhase.connecting ||
      phase == RealtimeConversationPhase.draining ||
      phase == RealtimeConversationPhase.postProcessing;

  String get providerTranscript => items
      .where((item) => item.role == 'learner')
      .map((item) => item.providerText)
      .where((text) => text.isNotEmpty)
      .join('\n');

  String get assistantTranscript => items
      .where((item) => item.role == 'assistant')
      .map((item) => item.providerText)
      .where((text) => text.isNotEmpty)
      .join('\n');

  String get localTranscript => items
      .where((item) => item.role == 'learner')
      .map((item) => item.localText)
      .where((text) => text.isNotEmpty)
      .join('\n');

  RealtimeConversationState copyWith({
    RealtimeConversationPhase? phase,
    RealtimeConversationActivity? activity,
    List<RealtimeProviderProfileView>? profiles,
    Object? selectedProfileId = _unset,
    RealtimeConversationMode? mode,
    List<RealtimeConversationItem>? items,
    int? postProcessingCount,
    List<RealtimeConversationSessionView>? historySessions,
    List<RealtimeConversationItem>? historyItems,
    Object? selectedHistorySessionId = _unset,
    bool? historyLoading,
    Object? historyError = _unset,
    Object? error = _unset,
  }) => RealtimeConversationState(
    phase: phase ?? this.phase,
    activity: activity ?? this.activity,
    profiles: profiles ?? this.profiles,
    selectedProfileId: identical(selectedProfileId, _unset)
        ? this.selectedProfileId
        : selectedProfileId as String?,
    mode: mode ?? this.mode,
    items: items ?? this.items,
    postProcessingCount: postProcessingCount ?? this.postProcessingCount,
    historySessions: historySessions ?? this.historySessions,
    historyItems: historyItems ?? this.historyItems,
    selectedHistorySessionId: identical(selectedHistorySessionId, _unset)
        ? this.selectedHistorySessionId
        : selectedHistorySessionId as String?,
    historyLoading: historyLoading ?? this.historyLoading,
    historyError: identical(historyError, _unset)
        ? this.historyError
        : historyError as String?,
    error: identical(error, _unset) ? this.error : error as String?,
  );
}

const _unset = Object();

class RealtimeConversationController extends ChangeNotifier {
  RealtimeConversationController({
    RealtimeAudioSession? audio,
    RealtimeConnectionFactory? connect,
    Future<void> Function(Duration)? delay,
    int Function()? nowMs,
  }) : _audio = audio ?? RealtimeAudioBridge(),
       _connect = connect ?? _connectRealtime,
       _delay = delay ?? Future<void>.delayed,
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final RealtimeAudioSession _audio;
  final RealtimeConnectionFactory _connect;
  final Future<void> Function(Duration) _delay;
  final int Function() _nowMs;

  RealtimeConversationState state = const RealtimeConversationState();
  RealtimeConnection? _connection;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<Object?>? _connectionSubscription;
  int _generation = 0;
  String? _sessionId;
  int? _sessionStartedAtMs;
  LocalApi? _activeApi;
  RealtimeConversationLaunch? _launch;
  Completer<void>? _responseDone;
  bool _providerResponseActive = false;
  final RealtimeTurnAssembler _turns = RealtimeTurnAssembler();
  final List<Future<void>> _postProcessing = [];
  final Map<int, String> _recordingAssetIds = {};

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

  Future<void> loadHistory(LocalApi api) async {
    state = state.copyWith(historyLoading: true, historyError: null);
    notifyListeners();
    try {
      final sessions = await api.realtimeSessions();
      final sessionsWithTurns = await Future.wait(
        sessions.map((session) async {
          try {
            return session.withTurns(await api.realtimeTurns(session.id));
          } catch (_) {
            return session;
          }
        }),
      );
      state = state.copyWith(
        historySessions: sessionsWithTurns,
        historyLoading: false,
        historyError: null,
      );
    } catch (error) {
      state = state.copyWith(
        historyLoading: false,
        historyError: 'Could not load conversation history: $error',
      );
    }
    notifyListeners();
  }

  Future<void> openHistorySession(LocalApi api, String sessionId) async {
    state = state.copyWith(
      selectedHistorySessionId: sessionId,
      historyItems: const [],
      historyLoading: true,
      historyError: null,
    );
    notifyListeners();
    try {
      final items = await api.realtimeTurns(sessionId);
      state = state.copyWith(
        historyItems: items,
        historyLoading: false,
        historyError: null,
      );
    } catch (error) {
      state = state.copyWith(
        historyLoading: false,
        historyError: 'Could not load conversation turns: $error',
      );
    }
    notifyListeners();
  }

  void closeHistorySession() {
    state = state.copyWith(
      selectedHistorySessionId: null,
      historyItems: const [],
      historyError: null,
    );
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
    RealtimeConversationLaunch launch, {
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
    if (launch.mode == RealtimeConversationMode.topicAnchored &&
        launch.anchor == null) {
      state = state.copyWith(error: 'Choose a topic before starting.');
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    _resetConversationState();
    state = state.copyWith(
      phase: RealtimeConversationPhase.connecting,
      activity: RealtimeConversationActivity.inactive,
      mode: launch.mode,
      items: const [],
      postProcessingCount: 0,
      error: null,
    );
    notifyListeners();
    try {
      final selectedProfile = state.profiles.firstWhere(
        (profile) => profile.id == profileId,
      );
      await acquireAudioFocus();
      // Native start owns permission acquisition. Do not open a billable/provider
      // socket until the microphone is actually available.
      await _audio.start(
        inputSampleRateHz: selectedProfile.adapterKind == 'qwen_omni_realtime'
            ? 16000
            : 24000,
      );
      final connection = await _connect(
        api.realtimeSocketUri(
          profileId: profileId,
          language: launch.language,
          instructions: _instructions(launch),
        ),
        {HttpHeaders.authorizationHeader: 'Bearer ${api.token}'},
      );
      if (generation != _generation) {
        await connection.close();
        return;
      }
      _connection = connection;
      _connectionSubscription = connection.messages.listen(
        _onConnectionMessage,
        onError: (Object error) {
          unawaited(_failAndCleanup('Realtime connection failed: $error'));
        },
        onDone: () {
          if (state.phase == RealtimeConversationPhase.live ||
              state.phase == RealtimeConversationPhase.draining) {
            unawaited(_failAndCleanup('Realtime provider disconnected.'));
          }
        },
      );
      _audioSubscription = _audio.pcmInput.listen((pcm) {
        if (_connection?.isOpen == true) {
          _connection!.send(pcm);
        }
      });
      final now = _nowMs();
      _sessionId = 'realtime-$now-${DateTime.now().microsecondsSinceEpoch}';
      _sessionStartedAtMs = now;
      _activeApi = api;
      _launch = launch;
      await api.saveRealtimeSession(
        _sessionJson(
          launch: launch,
          profileId: profileId,
          status: 'active',
          startedAtMs: now,
        ),
      );
      state = state.copyWith(
        phase: RealtimeConversationPhase.live,
        activity: RealtimeConversationActivity.listening,
      );
      notifyListeners();
    } catch (error) {
      await _cleanup(discard: true);
      state = state.copyWith(
        phase: RealtimeConversationPhase.failed,
        activity: RealtimeConversationActivity.inactive,
        error: 'Could not start realtime conversation: $error',
      );
      notifyListeners();
    }
  }

  String _instructions(RealtimeConversationLaunch launch) {
    final anchor = launch.anchor;
    if (launch.mode == RealtimeConversationMode.free || anchor == null) {
      return 'Have a natural spoken conversation with the learner. Keep replies concise and invite genuine back-and-forth.';
    }
    return 'Discuss the selected topic naturally. Do not merely recite it. Selected topic: ${anchor.text}';
  }

  void _onConnectionMessage(Object? message) {
    if (message is List<int>) {
      unawaited(_audio.play(Uint8List.fromList(message)));
      return;
    }
    if (message is! String) return;
    try {
      final value = jsonDecode(message) as Map<String, dynamic>;
      switch (value['type']) {
        case 'speech_started':
          state = state.copyWith(
            activity: RealtimeConversationActivity.learnerSpeaking,
          );
          unawaited(
            _startLearnerTurn(
              value['provider_item_id'] as String?,
              value['audio_start_ms'] as int?,
            ),
          );
        case 'speech_stopped':
          state = state.copyWith(
            activity: RealtimeConversationActivity.thinking,
          );
          _providerResponseActive = true;
          _responseDone = Completer<void>();
          unawaited(_stopLearnerTurn(value['provider_item_id'] as String?));
        case 'turn_committed':
          _correlateActiveLearner(value['provider_item_id'] as String?);
        case 'provider_transcript_preview':
          _updateLearnerProviderText(
            value['provider_item_id'] as String?,
            value['text'] as String? ?? '',
          );
        case 'provider_transcript_final':
          _updateLearnerProviderText(
            value['provider_item_id'] as String?,
            value['transcript'] as String? ?? '',
          );
        case 'assistant_transcript_delta':
          state = state.copyWith(
            activity: RealtimeConversationActivity.assistantSpeaking,
          );
          _updateAssistantText(
            value['provider_item_id'] as String?,
            value['delta'] as String? ?? '',
            append: true,
          );
        case 'assistant_transcript_final':
          unawaited(
            _finalizeAssistantTurn(
              value['provider_item_id'] as String?,
              value['transcript'] as String? ?? '',
            ),
          );
        case 'response_done':
          _providerResponseActive = false;
          state = state.copyWith(
            activity: RealtimeConversationActivity.listening,
          );
          if (_responseDone?.isCompleted == false) _responseDone!.complete();
        case 'provider_error' || 'connection_failed':
          unawaited(_failAndCleanup(value['error'].toString()));
      }
    } catch (error) {
      unawaited(_failAndCleanup('Invalid realtime provider event: $error'));
    }
    notifyListeners();
  }

  Future<void> _startLearnerTurn(
    String? providerItemId,
    int? audioStartMs,
  ) async {
    if (state.phase != RealtimeConversationPhase.live) return;
    await _audio.stopPlayback();
    if (_connection?.isOpen == true) _connection!.send('cancel');
    final interruptedAssistant = _turns.interruptAssistant(_nowMs());
    final interruptedItem = interruptedAssistant == null
        ? null
        : _item(interruptedAssistant);
    _syncItems();
    final sequence = _turns.startLearner(
      startedAtMs: _nowMs(),
      providerItemId: providerItemId,
    );
    _syncItems();
    if (sequence == null) return;
    if (interruptedItem != null) {
      unawaited(
        _persistInterruptedItem(
          interruptedItem,
          failureKind: 'learner_barge_in',
        ),
      );
    }
    try {
      await _audio.beginTurn(
        '${_sessionId ?? 'realtime'}-learner-$sequence',
        audioStartMs: audioStartMs,
      );
    } catch (error) {
      _replaceItem(
        sequence,
        (item) => item.copyWith(status: 'failed', error: '$error'),
      );
      _turns.activeLearnerSequence = null;
    }
    notifyListeners();
  }

  Future<void> _stopLearnerTurn(String? providerItemId) async {
    final sequence = _turns.closeLearnerCorrelation(providerItemId);
    if (sequence == null) return;
    _syncItems();
    try {
      final captured = await _audio.endTurn();
      final endedAt = _nowMs();
      _replaceItem(
        sequence,
        (item) => item.copyWith(
          status: 'local_transcription_pending',
          endedAtMs: endedAt,
        ),
      );
      final generation = _generation;
      final work = _processLearnerTurn(sequence, captured, endedAt, generation);
      _postProcessing.add(work);
      state = state.copyWith(
        postProcessingCount: state.postProcessingCount + 1,
      );
      unawaited(
        work.whenComplete(() {
          _postProcessing.remove(work);
          if (generation != _generation) return;
          state = state.copyWith(
            postProcessingCount: state.postProcessingCount > 0
                ? state.postProcessingCount - 1
                : 0,
          );
          notifyListeners();
        }),
      );
    } catch (error) {
      _replaceItem(
        sequence,
        (item) => item.copyWith(
          status: 'failed',
          endedAtMs: _nowMs(),
          error: 'Could not close learner audio: $error',
        ),
      );
    }
    notifyListeners();
  }

  Future<void> _processLearnerTurn(
    int sequence,
    CapturedRecording captured,
    int endedAt,
    int generation,
  ) async {
    final api = _activeApi;
    final launch = _launch;
    final sessionId = _sessionId;
    if (api == null || launch == null || sessionId == null) return;
    RecordingAsset? asset;
    try {
      final anchor = launch.anchor;
      asset = await api.createRecordingAsset(
        CreateRecordingAsset(
          filePath: captured.path,
          durationMs: captured.durationMs,
          target: PracticeTarget(
            // Recording targets describe the captured media span. Realtime
            // turn identity is stored separately on the conversation turn.
            kind: 'segment',
            startMs: anchor?.startMs ?? 0,
            endMs: anchor?.endMs ?? 0,
          ),
          sourceSegment: PlayableSegment(
            mediaId: anchor?.mediaId,
            startMs: anchor?.startMs ?? 0,
            endMs: anchor?.endMs ?? 0,
            label: launch.mode == RealtimeConversationMode.free
                ? 'free realtime conversation'
                : 'realtime conversation topic',
            subtitleSnapshot: anchor?.text ?? '',
            availability: anchor?.mediaId == null
                ? 'missing_media'
                : 'available',
          ),
          language: launch.language,
          audio: RecordingAudioMetadata(
            container: 'wav',
            codec: 'pcm_s16le',
            sampleRateHz: 16000,
            channels: 1,
            sampleFormat: 's16',
            byteLength: captured.byteLength,
            contentSha256: captured.contentSha256,
          ),
          recorderVersion: 'macos-avfoundation-realtime-turn-preroll-v2',
        ),
      );
      if (generation != _generation) {
        try {
          await api.deleteRecordingAsset(asset.id);
        } catch (_) {}
        return;
      }
      _recordingAssetIds[sequence] = asset.id;
      await api.saveRealtimeTurn(
        _learnerTurnJson(
          sequence,
          sessionId: sessionId,
          status: 'awaiting_local_transcript',
          recordingAssetId: asset.id,
          endedAt: endedAt,
        ),
      );
      if (generation != _generation) return;
      var job = await api.createRecordingTranscription(
        recordingId: asset.id,
        modelId: launch.modelId,
        language: launch.language,
      );
      while (job.status != 'completed' &&
          job.status != 'failed' &&
          job.status != 'cancelled' &&
          generation == _generation) {
        await _delay(const Duration(milliseconds: 150));
        if (generation != _generation) return;
        job = await api.recordingTranscriptionJob(job.id);
      }
      if (generation != _generation) return;
      final local = job.status == 'completed'
          ? (job.rawTranscript?.trim() ?? '')
          : '';
      if (local.isEmpty) {
        await api.saveRealtimeTurn(
          _learnerTurnJson(
            sequence,
            sessionId: sessionId,
            status: 'failed',
            recordingAssetId: asset.id,
            endedAt: endedAt,
            failureKind: 'local_transcription_failed',
          ),
        );
        _replaceItem(
          sequence,
          (item) => item.copyWith(
            status: 'failed',
            error:
                job.errorMessage ??
                'Local transcription produced no learner text.',
          ),
        );
        return;
      }
      final completedAt = _nowMs();
      await api.saveRealtimeTurn(
        _learnerTurnJson(
          sequence,
          sessionId: sessionId,
          status: 'finalized',
          recordingAssetId: asset.id,
          endedAt: endedAt,
          localTranscript: local,
          transcriptionJobId: job.id,
          completedAt: completedAt,
        ),
      );
      _replaceItem(
        sequence,
        (item) => item.copyWith(status: 'finalized', localText: local),
      );
    } catch (error) {
      if (generation != _generation) return;
      if (asset != null) {
        try {
          await api.saveRealtimeTurn(
            _learnerTurnJson(
              sequence,
              sessionId: sessionId,
              status: 'failed',
              recordingAssetId: asset.id,
              endedAt: endedAt,
              failureKind: 'local_post_processing_failed',
            ),
          );
        } catch (_) {}
      }
      _replaceItem(
        sequence,
        (item) => item.copyWith(
          status: 'failed',
          error: 'Could not process learner turn: $error',
        ),
      );
    }
  }

  Map<String, dynamic> _learnerTurnJson(
    int sequence, {
    required String sessionId,
    required String status,
    required String recordingAssetId,
    required int endedAt,
    String? failureKind,
    String? localTranscript,
    String? transcriptionJobId,
    int? completedAt,
  }) {
    final item = _item(sequence);
    return {
      'id': '$sessionId-learner-$sequence',
      'session_id': sessionId,
      'sequence': sequence,
      'role': 'learner',
      'status': status,
      'assistance': state.mode == RealtimeConversationMode.free
          ? 'unknown'
          : 'content_anchored',
      'provider_transcript': item.providerText.isEmpty
          ? null
          : {
              'text': item.providerText,
              'provider_item_id': item.providerItemId,
              'received_at_ms': endedAt,
            },
      'local_transcript': localTranscript == null
          ? null
          : {
              'text': localTranscript,
              'recording_asset_id': recordingAssetId,
              'transcription_job_id': transcriptionJobId,
              'completed_at_ms': completedAt,
            },
      'recording_asset_id': recordingAssetId,
      'started_at_ms': item.startedAtMs,
      'ended_at_ms': endedAt,
      'failure_kind': failureKind,
    };
  }

  void _updateLearnerProviderText(String? providerItemId, String text) {
    _turns.updateLearnerProviderText(providerItemId, text);
    _syncItems();
  }

  void _updateAssistantText(
    String? providerItemId,
    String text, {
    required bool append,
  }) {
    _turns.updateAssistantText(
      providerItemId,
      text,
      append: append,
      startedAtMs: _nowMs(),
    );
    _syncItems();
  }

  Future<void> _finalizeAssistantTurn(
    String? providerItemId,
    String transcript,
  ) async {
    final endedAt = _nowMs();
    final sequence = _turns.finalizeAssistant(
      providerItemId,
      transcript,
      endedAt,
    );
    _syncItems();
    final api = _activeApi;
    final sessionId = _sessionId;
    if (sequence == null || api == null || sessionId == null) return;
    final item = _item(sequence);
    try {
      await api.saveRealtimeTurn({
        'id': '$sessionId-assistant-$sequence',
        'session_id': sessionId,
        'sequence': sequence,
        'role': 'assistant',
        'status': 'finalized',
        'assistance': 'unknown',
        'provider_transcript': item.providerText.isEmpty
            ? null
            : {
                'text': item.providerText,
                'provider_item_id': item.providerItemId,
                'received_at_ms': endedAt,
              },
        'local_transcript': null,
        'recording_asset_id': null,
        'started_at_ms': item.startedAtMs,
        'ended_at_ms': endedAt,
        'failure_kind': null,
      });
    } catch (error) {
      _replaceItem(
        sequence,
        (current) => current.copyWith(
          status: 'failed',
          error: 'Could not save assistant turn: $error',
        ),
      );
    }
    notifyListeners();
  }

  Future<void> finish() async {
    final api = _activeApi;
    final launch = _launch;
    if (state.phase != RealtimeConversationPhase.live ||
        api == null ||
        launch == null) {
      return;
    }
    state = state.copyWith(
      phase: RealtimeConversationPhase.draining,
      activity: RealtimeConversationActivity.inactive,
      error: null,
    );
    notifyListeners();
    try {
      if (_turns.activeLearnerSequence != null) {
        await _stopLearnerTurn(null);
      }
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      final sessionRecording = await _audio.stop();
      try {
        await File(sessionRecording.path).delete();
      } catch (_) {}
      var providerDrained = true;
      if (_providerResponseActive && _responseDone != null) {
        providerDrained = await _responseDone!.future
            .then((_) => true)
            .timeout(const Duration(seconds: 15), onTimeout: () => false);
      }
      final activeAssistant = _turns.activeAssistantSequence;
      if (activeAssistant != null) {
        final item = _item(activeAssistant);
        if (providerDrained && item.providerText.trim().isNotEmpty) {
          await _finalizeAssistantTurn(item.providerItemId, item.providerText);
        } else {
          final sequence = _turns.interruptAssistant(_nowMs());
          _syncItems();
          if (sequence != null) {
            await _persistInterruptedItem(
              _item(sequence),
              failureKind: providerDrained
                  ? 'assistant_response_incomplete'
                  : 'provider_drain_timeout',
            );
          }
        }
      }
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      await _connection?.close();
      _connection = null;
      await _audio.shutdown();
      state = state.copyWith(
        phase: RealtimeConversationPhase.postProcessing,
        activity: RealtimeConversationActivity.inactive,
      );
      notifyListeners();
      while (_postProcessing.isNotEmpty) {
        await Future.wait(List<Future<void>>.from(_postProcessing));
      }
      final endedAt = _nowMs();
      await _persistTerminalSession(
        status: 'completed',
        failureKind: null,
        endedAtMs: endedAt,
      );
      state = state.copyWith(phase: RealtimeConversationPhase.done);
      await loadHistory(api);
    } catch (error) {
      await _persistTerminalSession(
        status: 'failed',
        failureKind: 'finalization_failed',
        endedAtMs: _nowMs(),
      );
      state = state.copyWith(
        phase: RealtimeConversationPhase.failed,
        activity: RealtimeConversationActivity.inactive,
        error: 'Could not finish realtime conversation: $error',
      );
    }
    notifyListeners();
  }

  Future<void> cancel() async {
    ++_generation;
    final activeLearner = _turns.activeLearnerSequence;
    if (activeLearner != null) {
      await _audio.discardTurn();
      _replaceItem(
        activeLearner,
        (item) => item.copyWith(status: 'interrupted', endedAtMs: _nowMs()),
      );
      _turns.activeLearnerSequence = null;
    }
    final activeAssistant = _turns.interruptAssistant(_nowMs());
    _syncItems();
    final unfinished = state.items.where(
      (item) =>
          item.status == 'streaming' ||
          item.status == 'local_transcription_pending',
    );
    for (final item in unfinished.toList(growable: false)) {
      _replaceItem(
        item.sequence,
        (current) => current.copyWith(
          status: 'interrupted',
          endedAtMs: current.endedAtMs ?? _nowMs(),
        ),
      );
    }
    final interruptedSequences = <int>{
      ?activeLearner,
      ?activeAssistant,
      ...unfinished.map((item) => item.sequence),
    };
    for (final sequence in interruptedSequences) {
      await _persistInterruptedItem(
        _item(sequence),
        failureKind: 'user_cancelled',
      );
    }
    await _cleanup(discard: true);
    await _persistTerminalSession(
      status: 'interrupted',
      failureKind: 'user_cancelled',
      endedAtMs: _nowMs(),
    );
    state = state.copyWith(
      phase: RealtimeConversationPhase.idle,
      activity: RealtimeConversationActivity.inactive,
      error: null,
    );
    notifyListeners();
  }

  Future<void> _persistInterruptedItem(
    RealtimeConversationItem item, {
    required String failureKind,
  }) async {
    final api = _activeApi;
    final sessionId = _sessionId;
    if (api == null || sessionId == null) return;
    final endedAt = item.endedAtMs ?? _nowMs();
    try {
      await api.saveRealtimeTurn({
        'id': '$sessionId-${item.role}-${item.sequence}',
        'session_id': sessionId,
        'sequence': item.sequence,
        'role': item.role,
        'status': 'interrupted',
        'assistance':
            item.role == 'learner' &&
                state.mode == RealtimeConversationMode.topicAnchored
            ? 'content_anchored'
            : 'unknown',
        'provider_transcript': item.providerText.isEmpty
            ? null
            : {
                'text': item.providerText,
                'provider_item_id': item.providerItemId,
                'received_at_ms': endedAt,
              },
        'local_transcript': null,
        'recording_asset_id': _recordingAssetIds[item.sequence],
        'started_at_ms': item.startedAtMs,
        'ended_at_ms': endedAt,
        'failure_kind': failureKind,
      });
    } catch (error) {
      _replaceItem(
        item.sequence,
        (current) =>
            current.copyWith(error: 'Could not save interrupted turn: $error'),
      );
    }
  }

  Map<String, dynamic> _sessionJson({
    required RealtimeConversationLaunch launch,
    required String profileId,
    required String status,
    required int startedAtMs,
    int? endedAtMs,
    String? failureKind,
  }) {
    final anchor = launch.anchor;
    return {
      'id': _sessionId,
      'profile_id': profileId,
      'language': launch.language,
      'context': {
        'surface_kind': launch.mode == RealtimeConversationMode.free
            ? 'open_chat'
            : 'topic_anchored',
        'content_anchor': anchor?.mediaId == null
            ? null
            : {
                'media_id': anchor!.mediaId,
                'start_ms': anchor.startMs,
                'end_ms': anchor.endMs,
                'source_text': anchor.text,
              },
      },
      'status': status,
      'started_at_ms': startedAtMs,
      'ended_at_ms': endedAtMs,
      'failure_kind': failureKind,
    };
  }

  Future<void> _persistTerminalSession({
    required String status,
    required String? failureKind,
    required int endedAtMs,
  }) async {
    final api = _activeApi;
    final launch = _launch;
    final startedAt = _sessionStartedAtMs;
    final profileId = state.selectedProfileId;
    if (api != null &&
        launch != null &&
        _sessionId != null &&
        startedAt != null &&
        profileId != null) {
      try {
        await api.saveRealtimeSession(
          _sessionJson(
            launch: launch,
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
    _launch = null;
  }

  Future<void> _cleanup({required bool discard}) async {
    await _audioSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _audioSubscription = null;
    _connectionSubscription = null;
    if (discard) await _audio.cancel();
    await _connection?.close();
    _connection = null;
  }

  Future<void> _failAndCleanup(String message) async {
    await _cleanup(discard: true);
    await _persistTerminalSession(
      status: 'failed',
      failureKind: 'provider_connection_failed',
      endedAtMs: _nowMs(),
    );
    state = state.copyWith(
      phase: RealtimeConversationPhase.failed,
      activity: RealtimeConversationActivity.inactive,
      error: message,
    );
    notifyListeners();
  }

  void _correlateActiveLearner(String? providerItemId) {
    _turns.correlateActiveLearner(providerItemId);
    _syncItems();
  }

  void _replaceItem(
    int sequence,
    RealtimeConversationItem Function(RealtimeConversationItem) update,
  ) {
    _turns.replace(sequence, update);
    _syncItems();
  }

  RealtimeConversationItem _item(int sequence) => _turns.item(sequence);

  void _syncItems() {
    state = state.copyWith(items: _turns.items);
  }

  void _resetConversationState() {
    _turns.reset();
    _providerResponseActive = false;
    _responseDone = null;
    _postProcessing.clear();
    _recordingAssetIds.clear();
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
      endedAtMs: _nowMs(),
    );
  }
}
