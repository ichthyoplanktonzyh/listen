import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/practice.dart';
import '../models/realtime_conversation.dart';
import '../services/api_service.dart';
import '../services/realtime_audio_bridge.dart';
import '../services/shadowing_recorder.dart';
import 'speaking_task_controller.dart';

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
    this.source,
  });

  factory RealtimeConversationLaunch.topic({
    required SpeakingTaskSource source,
    required String modelId,
  }) => RealtimeConversationLaunch(
    mode: RealtimeConversationMode.topicAnchored,
    language: source.language,
    modelId: modelId,
    source: source,
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
  final SpeakingTaskSource? source;
}

class RealtimeConversationState {
  const RealtimeConversationState({
    this.phase = 'idle',
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

  final String phase;
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
    String? phase,
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
  int _nextSequence = 1;
  int? _activeLearnerSequence;
  int? _activeAssistantSequence;
  final Map<String, int> _providerItemSequences = {};
  final List<Future<void>> _postProcessing = [];

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
        launch.source == null) {
      state = state.copyWith(error: 'Choose a topic before starting.');
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    _resetConversationState();
    state = state.copyWith(
      phase: 'connecting',
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
          if (state.phase == 'live' || state.phase == 'draining') {
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

  String _instructions(RealtimeConversationLaunch launch) {
    final source = launch.source;
    if (launch.mode == RealtimeConversationMode.free || source == null) {
      return 'Have a natural spoken conversation with the learner. Keep replies concise and invite genuine back-and-forth.';
    }
    return 'Discuss the selected topic naturally. Do not merely recite it. Selected topic: ${source.transcriptSnapshot}';
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
          unawaited(
            _startLearnerTurn(
              value['provider_item_id'] as String?,
              value['audio_start_ms'] as int?,
            ),
          );
        case 'speech_stopped':
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
    if (state.phase != 'live' || _activeLearnerSequence != null) return;
    await _audio.stopPlayback();
    if (_connection?.isOpen == true) _connection!.send('cancel');
    final sequence = _nextSequence++;
    _activeLearnerSequence = sequence;
    if (providerItemId != null) {
      _providerItemSequences[providerItemId] = sequence;
    }
    _appendItem(
      RealtimeConversationItem(
        sequence: sequence,
        role: 'learner',
        status: 'streaming',
        startedAtMs: _nowMs(),
        providerItemId: providerItemId,
      ),
    );
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
      _activeLearnerSequence = null;
    }
    notifyListeners();
  }

  Future<void> _stopLearnerTurn(String? providerItemId) async {
    final sequence = _activeLearnerSequence;
    if (sequence == null) return;
    _correlate(sequence, providerItemId);
    _activeLearnerSequence = null;
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
      final work = _processLearnerTurn(sequence, captured, endedAt);
      _postProcessing.add(work);
      state = state.copyWith(
        postProcessingCount: state.postProcessingCount + 1,
      );
      unawaited(
        work.whenComplete(() {
          _postProcessing.remove(work);
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
  ) async {
    final api = _activeApi;
    final launch = _launch;
    final sessionId = _sessionId;
    if (api == null || launch == null || sessionId == null) return;
    RecordingAsset? asset;
    try {
      final source = launch.source;
      asset = await api.createRecordingAsset(
        CreateRecordingAsset(
          filePath: captured.path,
          durationMs: captured.durationMs,
          target: PracticeTarget(
            // Recording targets describe the captured media span. Realtime
            // turn identity is stored separately on the conversation turn.
            kind: 'segment',
            startMs: source?.startMs ?? 0,
            endMs: source?.endMs ?? 0,
          ),
          sourceSegment: PlayableSegment(
            mediaId: source?.mediaId,
            startMs: source?.startMs ?? 0,
            endMs: source?.endMs ?? 0,
            label: launch.mode == RealtimeConversationMode.free
                ? 'free realtime conversation'
                : 'realtime conversation topic',
            subtitleSnapshot: source?.transcriptSnapshot ?? '',
            availability: source?.mediaId == null
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
      await api.saveRealtimeTurn(
        _learnerTurnJson(
          sequence,
          sessionId: sessionId,
          status: 'awaiting_local_transcript',
          recordingAssetId: asset.id,
          endedAt: endedAt,
        ),
      );
      var job = await api.createRecordingTranscription(
        recordingId: asset.id,
        modelId: launch.modelId,
        language: launch.language,
      );
      while (job.status != 'completed' &&
          job.status != 'failed' &&
          job.status != 'cancelled') {
        await _delay(const Duration(milliseconds: 150));
        job = await api.recordingTranscriptionJob(job.id);
      }
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
    final sequence = _sequenceFor(
      providerItemId,
      role: 'learner',
      fallback: _activeLearnerSequence,
    );
    if (sequence == null) return;
    _correlate(sequence, providerItemId);
    _replaceItem(sequence, (item) => item.copyWith(providerText: text));
  }

  void _updateAssistantText(
    String? providerItemId,
    String text, {
    required bool append,
  }) {
    var sequence = _sequenceFor(
      providerItemId,
      role: 'assistant',
      fallback: _activeAssistantSequence,
    );
    if (sequence == null) {
      sequence = _nextSequence++;
      _activeAssistantSequence = sequence;
      if (providerItemId != null) {
        _providerItemSequences[providerItemId] = sequence;
      }
      _appendItem(
        RealtimeConversationItem(
          sequence: sequence,
          role: 'assistant',
          status: 'streaming',
          startedAtMs: _nowMs(),
          providerItemId: providerItemId,
        ),
      );
    }
    _correlate(sequence, providerItemId);
    _replaceItem(
      sequence,
      (item) =>
          item.copyWith(providerText: append ? item.providerText + text : text),
    );
  }

  Future<void> _finalizeAssistantTurn(
    String? providerItemId,
    String transcript,
  ) async {
    final existingSequence = _sequenceFor(
      providerItemId,
      role: 'assistant',
      fallback: _activeAssistantSequence,
    );
    if (existingSequence != null &&
        _item(existingSequence).status == 'finalized') {
      return;
    }
    _updateAssistantText(providerItemId, transcript, append: false);
    final sequence = _sequenceFor(
      providerItemId,
      role: 'assistant',
      fallback: _activeAssistantSequence,
    );
    final api = _activeApi;
    final sessionId = _sessionId;
    if (sequence == null || api == null || sessionId == null) return;
    final endedAt = _nowMs();
    _replaceItem(
      sequence,
      (item) => item.copyWith(status: 'finalized', endedAtMs: endedAt),
    );
    _activeAssistantSequence = null;
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
    if (state.phase != 'live' || api == null || launch == null) return;
    state = state.copyWith(phase: 'draining', error: null);
    notifyListeners();
    try {
      if (_activeLearnerSequence != null) {
        await _stopLearnerTurn(null);
      }
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      final sessionRecording = await _audio.stop();
      try {
        await File(sessionRecording.path).delete();
      } catch (_) {}
      if (_providerResponseActive && _responseDone != null) {
        await _responseDone!.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {},
        );
      }
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      await _connection?.close();
      _connection = null;
      await _audio.shutdown();
      state = state.copyWith(phase: 'post_processing');
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
      state = state.copyWith(phase: 'done');
      await loadHistory(api);
    } catch (error) {
      await _persistTerminalSession(
        status: 'failed',
        failureKind: 'finalization_failed',
        endedAtMs: _nowMs(),
      );
      state = state.copyWith(
        phase: 'failed',
        error: 'Could not finish realtime conversation: $error',
      );
    }
    notifyListeners();
  }

  Future<void> cancel() async {
    ++_generation;
    if (_activeLearnerSequence != null) {
      await _audio.discardTurn();
      final sequence = _activeLearnerSequence!;
      _replaceItem(
        sequence,
        (item) => item.copyWith(status: 'interrupted', endedAtMs: _nowMs()),
      );
      _activeLearnerSequence = null;
    }
    await _cleanup(discard: true);
    await _persistTerminalSession(
      status: 'interrupted',
      failureKind: 'user_cancelled',
      endedAtMs: _nowMs(),
    );
    state = state.copyWith(phase: 'idle', error: null);
    notifyListeners();
  }

  Map<String, dynamic> _sessionJson({
    required RealtimeConversationLaunch launch,
    required String profileId,
    required String status,
    required int startedAtMs,
    int? endedAtMs,
    String? failureKind,
  }) {
    final source = launch.source;
    return {
      'id': _sessionId,
      'profile_id': profileId,
      'language': launch.language,
      'context': {
        'surface_kind': launch.mode == RealtimeConversationMode.free
            ? 'open_chat'
            : 'topic_anchored',
        'content_anchor': source?.mediaId == null
            ? null
            : {
                'media_id': source!.mediaId,
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
    state = state.copyWith(phase: 'failed', error: message);
    notifyListeners();
  }

  void _correlateActiveLearner(String? providerItemId) {
    final sequence = _activeLearnerSequence;
    if (sequence != null) _correlate(sequence, providerItemId);
  }

  void _correlate(int sequence, String? providerItemId) {
    if (providerItemId == null) return;
    _providerItemSequences[providerItemId] = sequence;
    _replaceItem(
      sequence,
      (item) => item.copyWith(providerItemId: providerItemId),
    );
  }

  int? _sequenceFor(
    String? providerItemId, {
    required String role,
    int? fallback,
  }) {
    final correlated = providerItemId == null
        ? null
        : _providerItemSequences[providerItemId];
    if (correlated != null && _item(correlated).role == role) return correlated;
    if (fallback != null && _item(fallback).role == role) return fallback;
    for (final item in state.items.reversed) {
      if (item.role == role && item.status != 'finalized') return item.sequence;
    }
    return null;
  }

  void _appendItem(RealtimeConversationItem item) {
    state = state.copyWith(
      items: [...state.items, item]
        ..sort((a, b) => a.sequence.compareTo(b.sequence)),
    );
  }

  void _replaceItem(
    int sequence,
    RealtimeConversationItem Function(RealtimeConversationItem) update,
  ) {
    state = state.copyWith(
      items: state.items
          .map((item) => item.sequence == sequence ? update(item) : item)
          .toList(growable: false),
    );
  }

  RealtimeConversationItem _item(int sequence) =>
      state.items.firstWhere((item) => item.sequence == sequence);

  void _resetConversationState() {
    _nextSequence = 1;
    _providerResponseActive = false;
    _responseDone = null;
    _activeLearnerSequence = null;
    _activeAssistantSequence = null;
    _providerItemSequences.clear();
    _postProcessing.clear();
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
