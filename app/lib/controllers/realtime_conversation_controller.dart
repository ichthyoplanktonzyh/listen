import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/realtime_conversation_repository.dart';
import '../models/api_failure.dart';
import '../models/practice.dart';
import '../models/realtime_conversation.dart';
import '../services/realtime_audio_bridge.dart';
import '../services/realtime_transport_service.dart';
import '../services/shadowing_recorder.dart';
import 'realtime_turn_assembler.dart';

export '../services/realtime_transport_service.dart'
    show RealtimeConnection, RealtimeConnectionFactory;

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

/// Everything one learner turn's post-processing needs, captured at the moment
/// the turn closed.
///
/// Held by value rather than read off the controller's active-session fields
/// so a rerun stays possible after the conversation has ended — the debrief,
/// where a failed turn is actually looked at, is shown once those fields have
/// already been released.
class _LearnerTurnJob {
  const _LearnerTurnJob({
    required this.launch,
    required this.sessionId,
    required this.captured,
    required this.endedAt,
  });

  final RealtimeConversationLaunch launch;
  final String sessionId;
  final CapturedRecording captured;
  final int endedAt;
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
  RealtimeConversationState({
    this.phase = RealtimeConversationPhase.idle,
    this.activity = RealtimeConversationActivity.inactive,
    List<RealtimeProviderProfileView> profiles = const [],
    this.selectedProfileId,
    this.mode = RealtimeConversationMode.topicAnchored,
    List<RealtimeConversationItem> items = const [],
    this.postProcessingCount = 0,
    List<RealtimeConversationSessionView> historySessions = const [],
    List<RealtimeConversationItem> historyItems = const [],
    this.selectedHistorySessionId,
    this.historyLoading = false,
    this.historyError,
    this.error,
  }) : _profiles = List.unmodifiable(profiles),
       _items = List.unmodifiable(items),
       _historySessions = List.unmodifiable(historySessions),
       _historyItems = List.unmodifiable(historyItems);

  final RealtimeConversationPhase phase;
  final RealtimeConversationActivity activity;
  final List<RealtimeProviderProfileView> _profiles;
  List<RealtimeProviderProfileView> get profiles =>
      List.unmodifiable(_profiles);
  final String? selectedProfileId;
  final RealtimeConversationMode mode;
  final List<RealtimeConversationItem> _items;
  List<RealtimeConversationItem> get items => List.unmodifiable(_items);
  final int postProcessingCount;
  final List<RealtimeConversationSessionView> _historySessions;
  List<RealtimeConversationSessionView> get historySessions =>
      List.unmodifiable(_historySessions);
  final List<RealtimeConversationItem> _historyItems;
  List<RealtimeConversationItem> get historyItems =>
      List.unmodifiable(_historyItems);
  final String? selectedHistorySessionId;
  final bool historyLoading;

  /// Why the history list or a replayed session could not be read. A named
  /// notice, never an interpolated exception.
  final RealtimeConversationNotice? historyError;

  /// Why the conversation itself could not start, run or finish.
  final RealtimeConversationNotice? error;

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
        : historyError as RealtimeConversationNotice?,
    error: identical(error, _unset)
        ? this.error
        : error as RealtimeConversationNotice?,
  );
}

const _unset = Object();

class RealtimeConversationController extends ChangeNotifier {
  RealtimeConversationController({
    RealtimeConversationRepository repository =
        const UnavailableRealtimeConversationRepository(),
    RealtimeAudioSession? audio,
    RealtimeTransportService? transport,
    RealtimeConnectionFactory? connect,
    Future<void> Function(Duration)? delay,
    int Function()? nowMs,
    this.providerDrainTimeout = const Duration(seconds: 15),
  }) : assert(transport == null || connect == null),
       // Repository is deliberately named publicly while stored privately.
       // ignore: prefer_initializing_formals
       _repository = repository,
       _audio = audio ?? RealtimeAudioBridge(),
       _transport = transport ?? IoRealtimeTransportService(connect: connect),
       _delay = delay ?? Future<void>.delayed,
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final RealtimeConversationRepository _repository;
  final RealtimeAudioSession _audio;
  final RealtimeTransportService _transport;
  final Future<void> Function(Duration) _delay;
  final int Function() _nowMs;
  final Duration providerDrainTimeout;

  RealtimeConversationState state = RealtimeConversationState();
  RealtimeConnection? _connection;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<Object?>? _connectionSubscription;
  int _generation = 0;
  String? _sessionId;
  int? _sessionStartedAtMs;
  RealtimeConversationLaunch? _launch;
  Completer<void>? _responseDone;
  bool _providerResponseActive = false;
  final RealtimeTurnAssembler _turns = RealtimeTurnAssembler();
  final List<Future<void>> _postProcessing = [];
  final Map<int, String> _recordingAssetIds = {};

  /// Learner turns whose post-processing failed with a failure the backend
  /// itself marked retryable, held with everything a rerun needs. Populated
  /// only on an explicit `retryable: true`; a turn that is not in here has no
  /// retry affordance, which is why the button never promises a rerun the
  /// client cannot perform.
  final Map<int, _LearnerTurnJob> _retryableTurns = {};

  Future<void> loadProfiles() async {
    try {
      final profiles = await _repository.profiles();
      state = state.copyWith(
        profiles: profiles,
        selectedProfileId:
            state.selectedProfileId ??
            (profiles.isEmpty ? null : profiles.first.id),
        error: null,
      );
    } catch (error) {
      state = state.copyWith(
        error: RealtimeConversationNotice(
          kind: 'providers_not_loaded',
          detail: _transport.describeFailure(error),
        ),
      );
    }
    notifyListeners();
  }

  Future<void> loadHistory() async {
    state = state.copyWith(historyLoading: true, historyError: null);
    notifyListeners();
    try {
      final sessions = await _repository.sessions();
      final sessionsWithTurns = await Future.wait(
        sessions.map((session) async {
          try {
            return session.withTurns(await _repository.turns(session.id));
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
        historyError: RealtimeConversationNotice(
          kind: 'history_not_loaded',
          detail: _transport.describeFailure(error),
        ),
      );
    }
    notifyListeners();
  }

  Future<void> openHistorySession(String sessionId) async {
    state = state.copyWith(
      selectedHistorySessionId: sessionId,
      historyItems: const [],
      historyLoading: true,
      historyError: null,
    );
    notifyListeners();
    try {
      final items = await _repository.turns(sessionId);
      state = state.copyWith(
        historyItems: items,
        historyLoading: false,
        historyError: null,
      );
    } catch (error) {
      state = state.copyWith(
        historyLoading: false,
        historyError: RealtimeConversationNotice(
          kind: 'turns_not_loaded',
          detail: _transport.describeFailure(error),
        ),
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

  Future<void> registerProfile({
    required String displayName,
    required String adapterKind,
    required String baseUrl,
    required String modelId,
    required String voice,
    required String secret,
  }) async {
    final saved = await _repository.registerProfile(
      displayName: displayName,
      adapterKind: adapterKind,
      baseUrl: baseUrl,
      modelId: modelId,
      voice: voice,
      secret: secret,
    );
    final profiles = await _repository.profiles();
    state = state.copyWith(
      profiles: profiles,
      selectedProfileId: saved.id,
      error: null,
    );
    notifyListeners();
  }

  Future<void> start(
    RealtimeConversationLaunch launch, {
    required Future<void> Function() acquireAudioFocus,
  }) async {
    final profileId = state.selectedProfileId;
    if (profileId == null) {
      state = state.copyWith(
        error: const RealtimeConversationNotice(kind: 'no_voice_selected'),
      );
      notifyListeners();
      return;
    }
    if (launch.mode == RealtimeConversationMode.topicAnchored &&
        launch.anchor == null) {
      state = state.copyWith(
        error: const RealtimeConversationNotice(kind: 'no_topic_selected'),
      );
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
      final request = _repository.connectionRequest(
        profileId: profileId,
        language: launch.language,
        instructions: _instructions(launch),
      );
      final connection = await _transport.connect(request.uri, request.headers);
      if (generation != _generation) {
        await connection.close();
        return;
      }
      _connection = connection;
      _connectionSubscription = connection.messages.listen(
        _onConnectionMessage,
        onError: (Object error) {
          unawaited(
            _failAndCleanup(
              RealtimeConversationNotice(
                kind: 'connection_failed',
                detail: _transport.describeFailure(error),
              ),
            ),
          );
        },
        onDone: () {
          if (state.phase == RealtimeConversationPhase.live ||
              state.phase == RealtimeConversationPhase.draining) {
            unawaited(
              _failAndCleanup(
                const RealtimeConversationNotice(kind: 'provider_disconnected'),
              ),
            );
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
      _launch = launch;
      await _repository.saveSession(
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
        error: RealtimeConversationNotice(
          kind: 'start_failed',
          detail: _transport.describeFailure(error),
        ),
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
    try {
      final event = _transport.decode(message);
      if (event case RealtimeAudioEvent(:final bytes)) {
        unawaited(_audio.play(bytes));
        return;
      }
      if (event is! RealtimeJsonEvent) return;
      final value = event.value;
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
          // The provider's own words. They were being shown verbatim, which
          // is the same mistake in a different costume — they get the same
          // treatment: a named state, with whatever the parser can type kept
          // as diagnostics.
          unawaited(
            _failAndCleanup(
              RealtimeConversationNotice(
                kind: 'provider_error',
                detail: ApiFailure.parse(value['error'].toString()),
              ),
            ),
          );
      }
    } catch (error) {
      unawaited(
        _failAndCleanup(
          RealtimeConversationNotice(
            kind: 'provider_event_invalid',
            detail: _transport.describeFailure(error),
          ),
        ),
      );
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
        (item) => item.copyWith(
          status: 'failed',
          failure: RealtimeTurnFailure(
            kind: 'learner_audio_capture_failed',
            detail: _transport.describeFailure(error),
          ),
        ),
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
      final launch = _launch;
      final sessionId = _sessionId;
      if (launch == null || sessionId == null) return;
      _track(
        _LearnerTurnJob(
          launch: launch,
          sessionId: sessionId,
          captured: captured,
          endedAt: endedAt,
        ),
        sequence,
      );
    } catch (error) {
      _replaceItem(
        sequence,
        (item) => item.copyWith(
          status: 'failed',
          endedAtMs: _nowMs(),
          failure: RealtimeTurnFailure(
            kind: 'learner_audio_capture_failed',
            detail: _transport.describeFailure(error),
          ),
        ),
      );
    }
    notifyListeners();
  }

  /// Runs one learner turn's post-processing and keeps the pending count in
  /// step with it. Shared by the first attempt and by
  /// [retryLearnerTranscription], so a retry is accounted for exactly like the
  /// original run — the debrief goes back to "still transcribing" instead of
  /// showing a settled tally over work that is running again.
  void _track(_LearnerTurnJob job, int sequence) {
    final generation = _generation;
    final work = _processLearnerTurn(sequence, job, generation);
    _postProcessing.add(work);
    state = state.copyWith(postProcessingCount: state.postProcessingCount + 1);
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
  }

  /// Runs a failed learner turn's local transcription again.
  ///
  /// Only reachable for a turn the backend itself called retryable: the job is
  /// stored in [_retryableTurns] exclusively when [ApiFailure.isRetryable] was
  /// true, so calling this for anything else is a no-op rather than a second
  /// doomed round trip. The turn's whole context (api, launch, session id,
  /// captured audio) is held with the job, because a conversation that has
  /// already finished has released the controller's active-session fields.
  ///
  /// This adds an operation; it does not change the phase/activity state
  /// machine. The turn simply re-enters `local_transcription_pending` and
  /// takes the same path it took the first time.
  Future<void> retryLearnerTranscription(int sequence) async {
    final job = _retryableTurns.remove(sequence);
    if (job == null) return;
    _replaceItem(
      sequence,
      (item) =>
          item.copyWith(status: 'local_transcription_pending', failure: null),
    );
    _track(job, sequence);
    notifyListeners();
  }

  Future<void> _processLearnerTurn(
    int sequence,
    _LearnerTurnJob job,
    int generation,
  ) async {
    final launch = job.launch;
    final sessionId = job.sessionId;
    final captured = job.captured;
    final endedAt = job.endedAt;
    RecordingAsset? asset;
    try {
      final anchor = launch.anchor;
      asset = await _repository.createRecordingAsset(
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
          await _repository.deleteRecordingAsset(asset.id);
        } catch (_) {}
        return;
      }
      _recordingAssetIds[sequence] = asset.id;
      await _repository.saveTurn(
        _learnerTurnJson(
          sequence,
          sessionId: sessionId,
          status: 'awaiting_local_transcript',
          recordingAssetId: asset.id,
          endedAt: endedAt,
        ),
      );
      if (generation != _generation) return;
      var transcription = await _repository.createTranscription(
        recordingId: asset.id,
        modelId: launch.modelId,
        language: launch.language,
      );
      while (transcription.status != 'completed' &&
          transcription.status != 'failed' &&
          transcription.status != 'cancelled' &&
          generation == _generation) {
        await _delay(const Duration(milliseconds: 150));
        if (generation != _generation) return;
        transcription = await _repository.transcriptionJob(transcription.id);
      }
      if (generation != _generation) return;
      final local = transcription.status == 'completed'
          ? (transcription.rawTranscript?.trim() ?? '')
          : '';
      if (local.isEmpty) {
        await _repository.saveTurn(
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
            // The transcription job answered; it just answered with nothing.
            // Its own message is an operator-facing diagnostic, so it goes
            // where diagnostics go rather than into the turn's body.
            failure: RealtimeTurnFailure(
              kind: 'local_transcription_failed',
              detail: transcription.errorMessage == null
                  ? null
                  : ApiFailure(
                      raw: transcription.errorMessage!,
                      message: transcription.errorMessage,
                    ),
            ),
          ),
        );
        return;
      }
      final completedAt = _nowMs();
      await _repository.saveTurn(
        _learnerTurnJson(
          sequence,
          sessionId: sessionId,
          status: 'finalized',
          recordingAssetId: asset.id,
          endedAt: endedAt,
          localTranscript: local,
          transcriptionJobId: transcription.id,
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
          await _repository.saveTurn(
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
      // The turn keeps a *named* state; the exception becomes typed
      // diagnostics hanging off it. Nothing here is ever interpolated into a
      // sentence — the string this used to build (`'Could not process learner
      // turn: $error'`) is exactly what leaked an error code, a
      // correlation id, a sidecar URI and an internal route into the card
      // that shows what the learner said.
      final detail = _transport.describeFailure(error);
      // Only the backend may authorise a retry, and only by saying so.
      // Holding the job here is what makes the affordance real rather than a
      // button that reruns nothing: a conversation that already finished has
      // released the controller's active-session fields.
      if (detail.isRetryable) _retryableTurns[sequence] = job;
      _replaceItem(
        sequence,
        (item) => item.copyWith(
          status: 'failed',
          failure: RealtimeTurnFailure(
            kind: 'local_post_processing_failed',
            detail: detail,
          ),
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
    final sessionId = _sessionId;
    if (sequence == null || sessionId == null) return;
    final item = _item(sequence);
    try {
      await _repository.saveTurn({
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
          failure: RealtimeTurnFailure(
            kind: 'assistant_history_not_saved',
            detail: _transport.describeFailure(error),
          ),
        ),
      );
    }
    notifyListeners();
  }

  Future<void> finish() async {
    final launch = _launch;
    if (state.phase != RealtimeConversationPhase.live || launch == null) {
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
      await _transport.deleteTemporaryRecording(sessionRecording.path);
      var providerDrained = true;
      if (_providerResponseActive && _responseDone != null) {
        providerDrained = await _responseDone!.future
            .then((_) => true)
            .timeout(providerDrainTimeout, onTimeout: () => false);
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
      await loadHistory();
    } catch (error) {
      await _persistTerminalSession(
        status: 'failed',
        failureKind: 'finalization_failed',
        endedAtMs: _nowMs(),
      );
      state = state.copyWith(
        phase: RealtimeConversationPhase.failed,
        activity: RealtimeConversationActivity.inactive,
        error: RealtimeConversationNotice(
          kind: 'finish_failed',
          detail: _transport.describeFailure(error),
        ),
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
      postProcessingCount: 0,
      error: null,
    );
    notifyListeners();
  }

  Future<void> _persistInterruptedItem(
    RealtimeConversationItem item, {
    required String failureKind,
  }) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final endedAt = item.endedAtMs ?? _nowMs();
    try {
      await _repository.saveTurn({
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
        (current) => current.copyWith(
          failure: RealtimeTurnFailure(
            kind: 'interrupted_turn_not_saved',
            detail: _transport.describeFailure(error),
          ),
        ),
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
    final launch = _launch;
    final startedAt = _sessionStartedAtMs;
    final profileId = state.selectedProfileId;
    if (launch != null &&
        _sessionId != null &&
        startedAt != null &&
        profileId != null) {
      try {
        await _repository.saveSession(
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

  Future<void> _failAndCleanup(RealtimeConversationNotice notice) async {
    await _cleanup(discard: true);
    await _persistTerminalSession(
      status: 'failed',
      failureKind: 'provider_connection_failed',
      endedAtMs: _nowMs(),
    );
    state = state.copyWith(
      phase: RealtimeConversationPhase.failed,
      activity: RealtimeConversationActivity.inactive,
      error: notice,
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

  /// Resets the controller to its initial idle state, clearing all
  /// conversation data. Called before pushing the conversation route so a
  /// returning user always lands on the lobby rather than a stale debrief.
  ///
  /// Only safe when no conversation is active; an in-flight session is never
  /// silently dropped by this method.
  void resetToIdle() {
    if (!state.canConfigure) return;
    final profiles = state.profiles;
    final selectedProfileId = state.selectedProfileId;
    _resetConversationState();
    state = RealtimeConversationState(
      profiles: profiles,
      selectedProfileId: selectedProfileId,
    );
    notifyListeners();
  }

  void _resetConversationState() {
    _turns.reset();
    _providerResponseActive = false;
    _responseDone = null;
    _postProcessing.clear();
    _recordingAssetIds.clear();
    _retryableTurns.clear();
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
