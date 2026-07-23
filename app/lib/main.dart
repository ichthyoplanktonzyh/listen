import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fvp/fvp.dart' as fvp;

import 'controllers/app_controllers.dart';
import 'controllers/auxiliary_audio_controller.dart';
import 'controllers/backend_event_coordinator.dart';
import 'controllers/content_channel_coordinator.dart';
import 'controllers/download_controller.dart';
import 'controllers/extensive_listening_controller.dart';
import 'controllers/hunting_actions_coordinator.dart';
import 'controllers/hunting_controller.dart';
import 'controllers/hunting_session_controller.dart';
import 'controllers/learning_controller.dart';
import 'controllers/learning_workflow_controller.dart';
import 'controllers/listening_inbox_coordinator.dart';
import 'controllers/media_library_coordinator.dart';
import 'controllers/media_session_coordinator.dart';
import 'controllers/occurrence_media_resolver.dart';
import 'controllers/playback_actions_coordinator.dart';
import 'controllers/player_controller.dart';
import 'controllers/practice_actions_coordinator.dart';
import 'controllers/practice_controller.dart';
import 'controllers/reading_channel_coordinator.dart';
import 'controllers/reading_controller.dart';
import 'controllers/reading_diff_controller.dart';
import 'controllers/reading_task_controller.dart';
import 'controllers/realtime_conversation_controller.dart';
import 'controllers/resource_actions_coordinator.dart';
import 'controllers/settings_controller.dart';
import 'controllers/slice_player_controller.dart';
import 'controllers/speaking_actions_coordinator.dart';
import 'controllers/speaking_channel_coordinator.dart';
import 'controllers/speaking_task_controller.dart';
import 'controllers/speech_enhancement_workflow_controller.dart';
import 'controllers/subtitle_controller.dart';
import 'controllers/subtitle_sources_coordinator.dart';
import 'controllers/vocabulary_actions_coordinator.dart';
import 'controllers/writing_channel_coordinator.dart';
import 'controllers/writing_task_controller.dart';
import 'localization.dart';
import 'models/capability_readiness.dart';
import 'models/content_activity.dart';
import 'models/content_channel.dart';
import 'models/personal_expression.dart';
import 'models/practice.dart';
import 'models/task_status.dart';
import 'models/timeline.dart';
import 'models/types.dart';
import 'player_adapter.dart';
import 'services/api_service.dart';
import 'services/external_tools.dart';
import 'settings.dart';
import 'theme/listen_theme.dart';
import 'theme/spacing.dart';
import 'utils/format_duration.dart';
import 'widgets/app_bar/app_bar_capabilities.dart';
import 'widgets/app_bar/player_app_bar.dart';
import 'widgets/channels/reading_channel.dart';
import 'widgets/channels/speaking_channel.dart';
import 'widgets/channels/writing_channel.dart';
import 'widgets/common/listen_loading.dart';
import 'widgets/flows/content_speaking_activity_dialog.dart';
import 'widgets/flows/learning_flows.dart';
import 'widgets/flows/manual_review_flow.dart';
import 'widgets/flows/media_import_flows.dart';
import 'widgets/flows/reading_flows.dart';
import 'widgets/flows/speaking_flows.dart';
import 'widgets/flows/subtitle_resource_flows.dart';
import 'widgets/flows/writing_flows.dart';
import 'widgets/home/listening_home.dart';
import 'widgets/layout/content_channel_switcher.dart';
import 'widgets/layout/media_workbench.dart';
import 'widgets/layout/playback_bar.dart';
import 'widgets/layout/player_overlays.dart';
import 'widgets/layout/player_stage.dart';
import 'widgets/layout/shell_recede.dart';
import 'widgets/layout/side_panel.dart';
import 'widgets/panels/l1_specialty_dialog.dart';
import 'widgets/panels/realtime_conversation_panel.dart';
import 'widgets/player/download_status_bar.dart';
import 'widgets/player/player_global_shortcuts.dart';
import 'widgets/settings/settings_flow.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final bundledFfmpeg =
      '${File(Platform.resolvedExecutable).parent.parent.path}'
      '/Frameworks/mdk.framework/Versions/A/libffmpeg.8.dylib';
  fvp.registerWith(
    options: {
      'platforms': ['macos'],
      'global': {'ffmpeg': bundledFfmpeg, 'libffmpeg': bundledFfmpeg},
    },
  );
  runApp(const ListenApp());
}

/// Folds the live playback/subtitle state into [current] for persistence.
///
/// Only fields whose source of truth lives in [player] or [subtitles] are
/// written; everything else rides along via `copyWith`. `_saveSettings` must
/// stay on this path: it once rebuilt a fresh `AppSettings(...)` here, which
/// silently reset every non-enumerated field (theme mode, resume state,
/// pronunciation prefs, …) to its default on every save.
AppSettings mergeLiveSettings({
  required AppSettings current,
  required PlayerController player,
  required SubtitleController subtitles,
}) => current.copyWith(
  rate: player.rate,
  volume: player.volume,
  primarySubtitleOffsetMs: subtitles.primarySubtitleOffset.inMilliseconds,
  secondarySubtitleOffsetMs: subtitles.secondarySubtitleOffset.inMilliseconds,
  subtitlesVisible: subtitles.visible,
  secondarySubtitlesVisible: subtitles.secondaryVisible,
  statusStylesVisible: subtitles.statusStylesVisible,
  primaryFontSize: subtitles.primaryFontSize,
  secondaryFontSize: subtitles.secondaryFontSize,
  primaryFontFamily: subtitles.primaryFontFamily,
  secondaryFontFamily: subtitles.secondaryFontFamily,
  subtitlePreset: subtitles.preset,
  subtitlePositionX: subtitles.positionX,
  subtitlePositionY: subtitles.positionY,
  subtitleBackgroundOpacity: subtitles.backgroundOpacity,
);

class ListenApp extends StatelessWidget {
  const ListenApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([appLanguage, appThemeMode]),
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'listen',
      locale: appLanguage.value == 'system' ? null : Locale(appLanguage.value),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ListenTheme.light(),
      darkTheme: ListenTheme.dark(),
      themeMode: appThemeMode.value,
      home: const PlayerScreen(),
    ),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with TickerProviderStateMixin {
  // ── Service / infrastructure handles ──
  final adapter = DesktopPlayerAdapter();
  final recordingAdapter = DesktopPlayerAdapter();
  final transcriptController = ScrollController();
  final subscriptions = <StreamSubscription<dynamic>>[];
  Timer? progressTimer;
  Timer? syntaxCapabilityTimer;
  LocalApi? api;

  // ── Controllers ──
  final playerController = PlayerController();
  final subtitleController = SubtitleController();
  final learningController = LearningController();
  final practiceController = PracticeController();
  final slicePlayerController = SlicePlayerController();
  final auxiliaryAudioController = AuxiliaryAudioController();
  final readingController = ReadingController();
  final readingTaskController = ReadingTaskController();
  final speakingTaskController = SpeakingTaskController();
  final realtimeConversationController = RealtimeConversationController();
  final writingTaskController = WritingTaskController();
  final readingDiffController = ReadingDiffController();
  final extensiveListeningController = ExtensiveListeningController();
  final huntingController = HuntingController();
  final huntingSessionController = HuntingSessionController();
  final learningWorkflowController = LearningWorkflowController();
  final speechEnhancementWorkflowController =
      SpeechEnhancementWorkflowController();
  final settingsController = SettingsController();
  final downloadController = DownloadController();
  late final resourceActions = ResourceActionsCoordinator(
    player: playerController,
    subtitle: subtitleController,
    speechEnhancement: speechEnhancementWorkflowController,
  );
  late final playbackActions = PlaybackActionsCoordinator(
    adapter: adapter,
    player: playerController,
    subtitle: subtitleController,
  );
  late final mediaSession = MediaSessionCoordinator(
    adapter: adapter,
    player: playerController,
    subtitle: subtitleController,
    learning: learningController,
    settings: settingsController,
    speechEnhancement: speechEnhancementWorkflowController,
    resourceActions: resourceActions,
  );
  late final huntingActions = HuntingActionsCoordinator(
    huntingSession: huntingSessionController,
    player: playerController,
    extensiveListening: extensiveListeningController,
    subtitle: subtitleController,
  );
  late final inboxActions = ListeningInboxCoordinator(
    extensiveListening: extensiveListeningController,
    player: playerController,
    subtitle: subtitleController,
    playbackActions: playbackActions,
  );
  late final practiceActions = PracticeActionsCoordinator(
    practice: practiceController,
    player: playerController,
    subtitle: subtitleController,
    learning: learningController,
    slicePlayer: slicePlayerController,
    playbackActions: playbackActions,
    settings: settingsController,
    adapter: adapter,
    recordingAdapter: recordingAdapter,
    stopAuxiliaryAudio: auxiliaryAudioController.stop,
  );
  late final speakingActions = SpeakingActionsCoordinator(
    task: speakingTaskController,
    player: playerController,
    subtitle: subtitleController,
    settings: settingsController,
    slicePlayer: slicePlayerController,
    adapter: adapter,
    recordingAdapter: recordingAdapter,
    stopAuxiliaryAudio: auxiliaryAudioController.stop,
  );
  late final vocabularyActions = VocabularyActionsCoordinator(
    workflow: learningWorkflowController,
    learning: learningController,
    subtitle: subtitleController,
    settings: settingsController,
    player: playerController,
  );
  late final mediaLibraryActions = MediaLibraryCoordinator(
    player: playerController,
    subtitle: subtitleController,
    learning: learningController,
    settings: settingsController,
    extensiveListening: extensiveListeningController,
  );
  late final subtitleSources = SubtitleSourcesCoordinator(
    player: playerController,
    subtitle: subtitleController,
    settings: settingsController,
  );
  late final readingChannel = ReadingChannelCoordinator(
    adapter: adapter,
    player: playerController,
    subtitle: subtitleController,
    settings: settingsController,
    reading: readingController,
    readingTask: readingTaskController,
    readingDiff: readingDiffController,
  );
  late final writingChannel = WritingChannelCoordinator(
    adapter: adapter,
    recordingAdapter: recordingAdapter,
    player: playerController,
    subtitle: subtitleController,
    settings: settingsController,
    slicePlayer: slicePlayerController,
    auxiliaryAudio: auxiliaryAudioController,
    task: writingTaskController,
  );
  late final speakingChannel = SpeakingChannelCoordinator(
    actions: speakingActions,
    task: speakingTaskController,
    readingTask: readingTaskController,
    learning: learningController,
    player: playerController,
  );
  late final contentChannels = ContentChannelCoordinator(
    reading: readingChannel,
    speaking: speakingChannel,
    speakingActions: speakingActions,
    writing: writingChannel,
  );

  // ── Local UI state (not managed by controllers) ──
  String get status => playerController.status;
  final taskStatuses = <UserTaskKind, UserTaskStatus>{};
  bool dragging = false;
  bool connectingApi = true;
  bool _workbenchExpanded = false;
  late final AnimationController _workbenchAnimController;
  late final Animation<Offset> _workbenchSlideAnimation;
  // ── Convenience ──
  AppLocalizations get l => AppLocalizations.of(context);

  ExternalTools get tools => ExternalTools(
    ffmpegPath: settingsController.ffmpegPath,
    ffprobePath: settingsController.ffprobePath,
    ytDlpPath: settingsController.ytDlpPath,
  );

  // Tracks the last primary cue id for de-duplicating async calls in _onPosition.
  String? _lastPrimaryCueId;

  // De-duplicates SnackBar surfacing of error statuses.
  String? _lastSurfacedError;

  /// Errors published on the status line are easy to miss; surface each new
  /// one once as a SnackBar as well.
  void _surfaceErrorStatus() {
    if (!mounted || !playerController.statusIsError) return;
    final message = playerController.status;
    if (message.isEmpty || message == _lastSurfacedError) return;
    _lastSurfacedError = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final colors = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: colors.onError)),
          backgroundColor: colors.error,
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  /// Keeps the extensive-listening played clock honest: it ticks only while
  /// the main player is actually playing (issue #3).
  void _trackExtensivePlayback() =>
      extensiveListeningController.notePlaybackState(playerController.playing);

  @override
  void initState() {
    super.initState();
    playerController.addListener(_surfaceErrorStatus);
    playerController.addListener(_trackExtensivePlayback);
    speakingActions.text = (key) => l.text(key);
    _workbenchAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _workbenchSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _workbenchAnimController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
    resourceActions.bind(
      getApi: () => api,
      isMounted: () => mounted,
      text: (key) => l.text(key),
      reloadSpeechEnhancements: (trackId) async {
        await mediaSession.loadSpeechEnhancements(trackId);
      },
      activatePrimaryTrack: (track, {required nextStatus}) async {
        await mediaSession.usePrimarySubtitleTrack(
          track,
          nextStatus: nextStatus,
        );
      },
      reloadLearningEntries: () async {
        await vocabularyActions.loadWordEntries();
        await vocabularyActions.loadPhraseEntries();
      },
    );
    mediaSession.bind(
      getApi: () => api,
      isMounted: () => mounted,
      text: (key) => l.text(key),
      confirmLLTimelineMismatch: _confirmLLTimelineMismatch,
      onMediaSwitched: () {
        unawaited(slicePlayerController.close());
        if (speakingActions.isOpen) {
          speakingChannel.closeL1Check();
          unawaited(speakingActions.close(api, restorePosition: false));
        }
        huntingSessionController.stop();
        setState(() {
          taskStatuses.clear();
          _workbenchExpanded = true;
        });
        _workbenchAnimController.forward();
      },
      reloadLearningEntries: () async {
        await vocabularyActions.loadWordEntries();
        await vocabularyActions.loadPhraseEntries();
      },
      loadPhraseCandidates: vocabularyActions.loadPhraseCandidates,
      generatedPrimaryStatus: _generatedPrimarySubtitleStatus,
    );
    playbackActions.bind(
      getApi: () => api,
      isMounted: () => mounted,
      text: (key) => l.text(key),
      reloadLearningEntries: () async {
        await vocabularyActions.loadWordEntries();
        await vocabularyActions.loadPhraseEntries();
      },
    );
    huntingActions.bind(
      getApi: () => api,
      isMounted: () => mounted,
      text: (key) => l.text(key),
    );
    inboxActions.bind(
      getApi: () => api,
      isMounted: () => mounted,
      text: (key) => l.text(key),
    );
    practiceActions.bind(
      getApi: () => api,
      isMounted: () => mounted,
      text: (key) => l.text(key),
      refreshDiagnosis: _refreshDiagnosis,
      seekCue: _seekCue,
    );
    vocabularyActions.bind(
      getApi: () => api,
      isMounted: () => mounted,
      text: (key) => l.text(key),
      refreshDiagnosis: _refreshDiagnosis,
    );
    mediaLibraryActions.bind(
      getApi: () => api,
      isMounted: () => mounted,
      text: (key) => l.text(key),
      requestRebuild: () => setState(() {}),
      openMediaPath: mediaSession.openMediaPath,
      openMedia: mediaSession.openMedia,
    );
    readingChannel.bind(
      getApi: () => api,
      isMounted: () => mounted,
      openSlicePlayback: _openSlicePlayback,
      openWord: vocabularyActions.openWord,
    );
    contentChannels.bind(
      getApi: () => api,
      speakingAvailable: () => Platform.isMacOS,
      openSpeaking: _openContentSpeakingActivity,
      openWriting: () => writingChannel.openTask(
        writingChannel.kind,
        promptSnapshot: writingPrompt(l, writingChannel.kind),
        fixedRubricPoints: writingTaskTemplate(l),
      ),
    );
    speakingChannel.text = (key) => l.text(key);
    speakingChannel.bind(
      getApi: () => api,
      isMounted: () => mounted,
      askPersonalExpressionAssessment: _askPersonalExpressionAssessment,
      onReturnToReview: () => unawaited(_openReviewQueue()),
      onReturnToPersonalExpression: () => unawaited(_openPersonalExpression()),
    );
    writingChannel.bind(
      getApi: () => api,
      isMounted: () => mounted,
      openSlicePlayback: _openSlicePlayback,
      closeOtherChannels: () async {
        speakingChannel.closeL1Check();
        if (speakingActions.isOpen) await speakingActions.close(api);
        await readingChannel.close();
      },
    );
    subtitleSources.bind(
      getApi: () => api,
      isMounted: () => mounted,
      text: (key) => l.text(key),
      showSnackBar: _showSnackBar,
      setTaskStatus: _setTaskStatus,
      openMediaPath: mediaSession.openMediaPath,
      openSubtitlePath: mediaSession.openSubtitlePath,
    );
    // `_connectApi` reads localized status strings off `context`, which is only
    // legal once initState has completed and dependencies are resolved.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_connectApi());
    });
    unawaited(_loadSettings());
    subscriptions.addAll([
      adapter.position.listen(_onPosition),
      adapter.duration.listen((value) {
        playerController.setDuration(value);
      }),
      adapter.playing.listen((value) {
        playerController.setPlaying(value);
      }),
      adapter.errors.listen((value) {
        playerController.setStatus(value);
      }),
      adapter.tracks.listen((value) {
        if (!mounted) return;
        String? defaultId;
        for (final track in value.audio) {
          if (track.isDefault == true) {
            defaultId = track.id;
            break;
          }
        }
        playerController.setAudioTracks(value.audio);
        playerController.setSelectedAudioId(defaultId);
        playerController.setEmbeddedSubtitleTracks(value.subtitle);
      }),
    ]);
  }

  Future<void> _loadSettings() async {
    await settingsController.load();
    if (!mounted) return;
    final s = settingsController.settings;
    // Sync to subtitle controller
    subtitleController.setPrimarySubtitleOffset(
      Duration(milliseconds: s.primarySubtitleOffsetMs),
    );
    subtitleController.setSecondarySubtitleOffset(
      Duration(milliseconds: s.secondarySubtitleOffsetMs),
    );
    subtitleController.setVisible(s.subtitlesVisible);
    subtitleController.setSecondaryVisible(s.secondarySubtitlesVisible);
    subtitleController.setStatusStylesVisible(s.statusStylesVisible);
    subtitleController.setPrimaryFontSize(s.primaryFontSize);
    subtitleController.setSecondaryFontSize(s.secondaryFontSize);
    subtitleController.setPrimaryFontFamily(s.primaryFontFamily);
    subtitleController.setSecondaryFontFamily(s.secondaryFontFamily);
    subtitleController.setPreset(s.subtitlePreset);
    subtitleController.setPositionX(s.subtitlePositionX);
    subtitleController.setPositionY(s.subtitlePositionY);
    subtitleController.setBackgroundOpacity(s.subtitleBackgroundOpacity);
    // Sync to player controller
    playerController.setRate(s.rate);
    playerController.setVolume(s.volume);
    appLanguage.value = s.language;
    appThemeMode.value = themeModeFromSetting(s.themeMode);
    await adapter.setRate(playerController.rate);
    await adapter.setVolume(playerController.volume);
  }

  Future<void> _saveSettings() => settingsController.update(
    mergeLiveSettings(
      current: settingsController.settings,
      player: playerController,
      subtitles: subtitleController,
    ),
  );

  void _setWorkbenchMediaFraction(double value) {
    settingsController.setSettings(
      settingsController.settings.copyWith(workbenchMediaFraction: value),
    );
    settingsController.saveSoon();
  }

  Future<void> _connectApi() async {
    if (api != null) return;
    // Everything lives inside the try: a throw before `connectingApi` is
    // cleared would strand the boot screen on a spinner forever.
    try {
      if (mounted) {
        playerController.setStatus(l.text('statusStartingCore'));
        setState(() {
          connectingApi = true;
        });
      }
      final value = await LocalApi.connect();
      if (!mounted) return value.close();
      playerController.setStatus(l.text('statusCoreConnected'));
      setState(() {
        api = value;
        connectingApi = false;
      });
      subscriptions.add(value.events().listen(_onEvent));
      value.listLanguages().then((languages) {
        if (mounted) learningController.availableLanguages = languages;
      }, onError: (_) {});
      progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (playerController.mediaId != null) {
          unawaited(
            api?.saveProgress(
              playerController.mediaId!,
              playerController.position,
            ),
          );
          mediaLibraryActions.recordRecentMedia();
        }
      });
      syntaxCapabilityTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(subtitleSources.checkSyntaxCapability()),
      );
      unawaited(subtitleSources.checkSyntaxCapability());
      unawaited(mediaLibraryActions.prefetchHomeSummary());
      unawaited(_runSmokeIfConfigured());
    } catch (error) {
      if (mounted) {
        playerController.setStatus(
          '${l.text('statusCoreUnavailable')}: $error',
          error: true,
        );
        setState(() {
          connectingApi = false;
        });
      }
    }
  }

  void _expandWorkbench() {
    setState(() => _workbenchExpanded = true);
    _workbenchAnimController.forward();
  }

  void _collapseWorkbench() {
    unawaited(practiceActions.closePracticeWindow());
    _workbenchAnimController.reverse().then((_) {
      if (mounted) setState(() => _workbenchExpanded = false);
    });
  }

  Future<void> _runSmokeIfConfigured() async {
    final media = Platform.environment['LLPLAYERNEXT_SMOKE_MEDIA'];
    final subtitle = Platform.environment['LLPLAYERNEXT_SMOKE_SUBTITLE'];
    final secondary =
        Platform.environment['LLPLAYERNEXT_SMOKE_SECONDARY_SUBTITLE'];
    if (media == null) return;
    await mediaSession.openMediaPath(media);
    if (subtitle != null) {
      await mediaSession.openSubtitlePath(subtitle, secondary: false);
    }
    if (secondary != null) {
      await mediaSession.openSubtitlePath(secondary, secondary: true);
    }
  }

  void _onEvent(Map<String, dynamic> event) {
    BackendEventCoordinator(
      currentMediaId: () => playerController.mediaId,
      currentPrimaryTrackId: () => subtitleController.primaryTrack?.id,
      loadWordEntries: vocabularyActions.loadWordEntries,
      loadTimelineResource: resourceActions.loadTimelineResource,
      readSubtitle: (trackId) => api!.readSubtitle(trackId),
      loadGeneratedTrack: mediaSession.loadGeneratedTrack,
      loadSpeechEnhancements: (trackId) async {
        await mediaSession.loadSpeechEnhancements(trackId);
      },
      setStatus: (value) {
        if (mounted) playerController.setStatus(value);
      },
      setTaskStatus: _setTaskStatus,
      updateWordEntry: learningController.updateSingleWordEntry,
      updateCapabilityProfile: learningController.updateCapabilityProfile,
      text: (key) => l.text(key),
    ).handle(event);
  }

  void _setTaskStatus(UserTaskStatus value) {
    if (!mounted) return;
    playerController.setStatus(_taskStatusText(value));
    setState(() {
      taskStatuses[value.kind] = value;
    });
  }

  String _taskStatusText(UserTaskStatus value) =>
      '${l.text(value.titleKey)}: ${l.text(value.stateKey)} · '
      '${value.progress.clamp(0, 100)}%';

  void _onPosition(Duration value) {
    subtitleController.updatePosition(value);
    subtitleController.updateCurrentWord(
      value,
      enabled: settingsController.wordSyncVisible,
      chunkEnabled: settingsController.chunkHighlightActive,
    );
    subtitleController.updateCurrentDetectedPhone(
      value,
      enabled:
          settingsController.settings.phonemeRibbonVisible ||
          settingsController.settings.soundPatternRibbonVisible,
    );

    final primaryCue = subtitleController.currentPrimaryCue;
    if (subtitleController.loopCue &&
        primaryCue != null &&
        value >= subtitleController.primaryCursor.mediaEnd(primaryCue)) {
      unawaited(
        adapter.seek(subtitleController.primaryCursor.mediaStart(primaryCue)),
      );
      return;
    }
    if (playerController.sourceLoopStart != null &&
        playerController.sourceLoopEnd != null &&
        value >= playerController.sourceLoopEnd!) {
      unawaited(adapter.seek(playerController.sourceLoopStart!));
      return;
    }
    if (primaryCue?.id != _lastPrimaryCueId) {
      _lastPrimaryCueId = primaryCue?.id;
      unawaited(_refreshDiagnosis());
      unawaited(vocabularyActions.loadPhraseCandidates(primaryCue));
      unawaited(subtitleSources.ensureCurrentPronunciation(primaryCue));
    }
    playerController.setPosition(value);
    huntingSessionController.updatePosition(value);
  }

  Future<bool> _confirmLLTimelineMismatch({
    required String resourceFingerprint,
    required String currentFingerprint,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('timelineFingerprintMismatch')),
        content: Text(
          '${l.text('timelineFingerprintMismatchBody')}\n\n'
          'Current: $currentFingerprint\n'
          'Resource: $resourceFingerprint',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.text('attachAnyway')),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  String _generatedPrimarySubtitleStatus(SpeechEnhancementLoadResult? result) {
    final parts = <String>[l.text('generatedPrimarySubtitleLoaded')];
    final readiness = _currentCapabilityReadiness();
    parts.addAll(readiness.learningItems.map(_capabilityStatusSegment));
    if (result != null && result.errors.isNotEmpty) {
      parts.add(l.text('generatedSubtitleResourceWarning'));
    }
    return parts.join(' · ');
  }

  CapabilityReadinessSnapshot _currentCapabilityReadiness() =>
      CapabilityReadinessSnapshot.fromResources(
        activeTrack: subtitleController.primaryTrack,
        document: subtitleController.llTimelineDocument,
        wordTimelineSummaries: subtitleController.wordTimelineSummaries,
        chunkTimelineSummaries: subtitleController.chunkTimelineSummaries,
        phoneTimelineSummaries: subtitleController.phoneTimelineSummaries,
        activeWordTimingCount: subtitleController.activeWordTimingCount,
        timelineResourceError: subtitleController.timelineResourceError,
      );

  String _capabilityStatusSegment(CapabilityReadiness readiness) =>
      '${l.text(readiness.titleKey)}: ${l.text(readiness.stateKey)}';

  Future<void> _deleteSubtitleResource(SubtitleTrack track) =>
      deleteSubtitleResourceFlow(
        context: context,
        resourceActions: resourceActions,
        track: track,
      );

  Future<void> _exportSubtitleResource(SubtitleTrack track) =>
      exportSubtitleResourceFlow(
        context: context,
        api: api,
        resourceActions: resourceActions,
        track: track,
      );

  Future<void> _openManualReviewTimeline() => openManualReviewFlow(
    context: context,
    api: api,
    adapter: adapter,
    playerController: playerController,
    subtitleController: subtitleController,
    resourceActions: resourceActions,
    mediaSession: mediaSession,
  );

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _generateSubtitles({required bool secondary}) =>
      generateSubtitlesFlow(
        context: context,
        api: api,
        playerController: playerController,
        settingsController: settingsController,
        secondary: secondary,
        recordTaskStatus: (value) {
          setState(() {
            taskStatuses[value.kind] = value;
          });
        },
      );

  Future<void> _openTranscriptionCenter() => openTranscriptionCenterFlow(
    context: context,
    api: api,
    loadTrack: mediaSession.loadGeneratedTrack,
  );

  Future<void> _openPhoneticAnalysisCenter() =>
      openPhoneticAnalysisCenterFlow(context: context, api: api);

  Future<void> _openOnline() => openOnlineMediaFlow(
    context: context,
    adapter: adapter,
    playerController: playerController,
    subtitleController: subtitleController,
    downloadController: downloadController,
    tools: tools,
    onMediaSwitched: () {
      setState(() {
        taskStatuses.clear();
        _workbenchExpanded = true;
      });
      _workbenchAnimController.forward();
    },
  );

  Future<void> _importEmbeddedSubtitle() => importEmbeddedSubtitleFlow(
    context: context,
    playerController: playerController,
    mediaSession: mediaSession,
    tools: tools,
    api: api,
    isMediaPath: subtitleSources.isMediaPath,
  );

  Future<void> _openSettings() => showAppSettings(
    context: context,
    settingsController: settingsController,
    subtitleController: subtitleController,
    playerController: playerController,
    learningController: learningController,
    saveSettings: _saveSettings,
    api: api,
  );

  Future<void> _openContentSpeakingActivity(LocalApi service) async {
    final activity = await showContentSpeakingActivityDialog(context);
    if (!mounted || activity == null) return;
    switch (activity) {
      case ContentSpeakingActivity.retelling:
        await speakingActions.openRetelling(
          service,
          fixedRubricPoints: listeningRetellTemplate(l),
          closeReading: readingChannel.close,
        );
      case ContentSpeakingActivity.shadowing:
        await practiceActions.startShadowingPractice();
      case ContentSpeakingActivity.conversation:
        final selection = speakingActions.selectCurrentSegment();
        if (selection != null) await _openRealtimeConversation(selection);
    }
  }

  Future<void> _openFreeConversation() => _openRealtimeConversation();

  Future<void> _openRealtimeConversation([
    ContentSegmentSelection? selection,
  ]) async {
    final service = api;
    if (service == null || !Platform.isMacOS) return;
    final language =
        selection?.language ??
        settingsController.resolveLearningLanguage(
          subtitleController.primaryTrack?.language,
        );
    final models = await service.transcriptionModels();
    final installed = models.where(
      (model) => model.state == 'installed' || model.state == 'custom',
    );
    final model = installed
        .where((candidate) => language == 'en' || !candidate.englishOnly)
        .firstOrNull;
    if (!mounted) return;
    if (model == null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.text('modelRequired')),
          content: Text(l.text('installModelFirst')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.text('close')),
            ),
          ],
        ),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (routeContext) => RealtimeConversationPanel(
          controller: realtimeConversationController,
          api: service,
          launch: selection == null
              ? RealtimeConversationLaunch.free(
                  language: language,
                  modelId: model.id,
                )
              : RealtimeConversationLaunch.topic(
                  anchor: RealtimeConversationAnchor(
                    language: selection.language,
                    text: selection.transcriptSnapshot,
                    mediaId: selection.mediaId,
                    startMs: selection.startMs,
                    endMs: selection.endMs,
                  ),
                  modelId: model.id,
                ),
          acquireAudioFocus: speakingActions.acquireRecordingFocus,
          onClose: () => Navigator.pop(routeContext),
        ),
      ),
    );
  }

  Future<void> _openLearningAssets() => openLearningAssetsFlow(
    context: context,
    api: api,
    settingsController: settingsController,
    subtitleController: subtitleController,
    openSlicePlayback: _openSlicePlayback,
    onPlayExpressionSource: _playPersonalExpressionSource,
    onStartExpressionSpeaking: _startPersonalExpressionSpeaking,
  );

  Future<void> _playPersonalExpressionSource(
    PersonalExpressionSourceView value,
  ) async {
    final mediaId = value.mediaId;
    final startMs = value.startMs;
    final endMs = value.endMs;
    if (mediaId == null || startMs == null || endMs == null) return;
    await _openSlicePlayback(
      currentMediaSliceOccurrence(
        mediaId: mediaId,
        trackId: value.trackId,
        sentenceId: value.sentenceId ?? value.candidateRef ?? mediaId,
        textSnapshot: value.text,
        startMs: startMs,
        endMs: endMs,
        mediaFingerprint: value.mediaFingerprint,
      ),
    );
  }

  Future<void> _startPersonalExpressionSpeaking(
    SentencePatternAssetView pattern,
  ) async {
    final service = api;
    if (service == null || !Platform.isMacOS) return;
    speakingChannel.activePersonalPattern = pattern;
    setState(() => _workbenchExpanded = true);
    _workbenchAnimController.forward();
    await speakingActions.openPersonalPattern(
      service,
      patternId: pattern.id,
      language: pattern.language,
      sourceText: pattern.source.text,
      promptText: pattern.currentVersion.patternText,
      mediaId: pattern.source.mediaId,
      trackId: pattern.source.trackId,
      startMs: pattern.source.startMs,
      endMs: pattern.source.endMs,
      fixedRubricPoints: personalExpressionTemplate(l),
      closeReading: readingChannel.close,
    );
  }

  Future<void> _openPersonalExpression({
    PersonalExpressionSourceView? source,
  }) => openPersonalExpressionFlow(
    context: context,
    api: api,
    language: settingsController.resolveLearningLanguage(
      subtitleController.primaryTrack?.language,
    ),
    initialSource: source,
    onPlaySource: _playPersonalExpressionSource,
    onStartSpeaking: _startPersonalExpressionSpeaking,
  );

  Future<void> _openLearningResources() =>
      openLearningResourcesFlow(context: context, api: api);

  Future<void> _openPhrase(PhraseCandidate candidate, Cue cue) =>
      openPhraseFlow(
        context: context,
        api: api,
        playerController: playerController,
        subtitleController: subtitleController,
        settingsController: settingsController,
        learningController: learningController,
        candidate: candidate,
        cue: cue,
      );

  Future<void> _correctCurrentLemma() => correctCurrentLemmaFlow(
    context: context,
    api: api,
    playerController: playerController,
    subtitleController: subtitleController,
    settingsController: settingsController,
    learningController: learningController,
  );

  Future<void> _searchOpenSubtitles({required bool secondary}) =>
      searchOpenSubtitlesFlow(
        context: context,
        playerController: playerController,
        settingsController: settingsController,
        mediaSession: mediaSession,
        api: api,
        secondary: secondary,
      );

  Future<void> _exportLogs() async {
    final source = api?.logPath;
    if (source == null || !await File(source).exists()) {
      playerController.setStatus(l.text('statusNoCoreLog'));
      return;
    }
    final location = await getSaveLocation(suggestedName: 'listen-core.log');
    if (location == null) return;
    await File(source).copy(location.path);
    playerController.setStatus(
      l.text('statusExportedDiagnostics').replaceAll('{path}', location.path),
    );
  }

  Future<void> _openSlicePlayback(Map<String, dynamic> occurrence) async {
    final result = await playbackActions.resolveOccurrenceMedia(
      occurrence,
      filterMediaExtensions: true,
    );
    if (result is UnresolvedOccurrenceMedia) {
      playerController.setStatus(result.message);
      await slicePlayerController.showError(
        result.message,
        occurrence: occurrence,
      );
      return;
    }
    final resolved = result as ResolvedOccurrenceMedia;
    // The slice owns audio focus. Pausing preserves the primary media,
    // position, and any practice loop so closing is non-destructive.
    await adapter.pause();
    await slicePlayerController.open(
      path: resolved.path,
      occurrence: occurrence,
    );
    if (slicePlayerController.state.error != null) {
      playerController.setStatus(slicePlayerController.state.error!);
    }
  }

  Future<void> _closeSlicePlayback() => slicePlayerController.close();

  /// Explicit reading mark on the selected word (Slice 5). Assistance is the
  /// honest translation visibility at marking time; one act, one
  /// reading-channel observation, nothing else.
  Future<void> _recordReadingMark(bool understood) async {
    final service = api;
    final entry = learningController.selectedLexicalDetails?.entry;
    final token = learningController.selectedToken;
    final cue = learningController.selectedCue;
    if (service == null || entry == null || token == null) return;
    try {
      await service.recordReadingMarking(
        lexicalEntryId: entry.id,
        sentenceId: cue?.id,
        surfaceForm: token.text,
        mediaId: subtitleController.primaryTrack?.mediaId,
        translationVisible: readingController.state.translationVisible,
        understood: understood,
      );
      playerController.setStatus(l.text('readingMarkSaved'));
    } catch (error) {
      playerController.setStatus(
        '${l.text('statusReadingMarkFailed')}: $error',
        error: true,
      );
    }
  }

  /// Opens the same-family clip aggregation for one L1 difficulty hint
  /// (Phase 3.9): listen goes through the slice playback window; practice is
  /// available for clips of the currently loaded track and seeds the
  /// practice window on that sentence.
  Future<void> _openL1Specialty(L1DiagnosisHint hint) async {
    final service = api;
    if (service == null || !mounted) return;
    final currentTrackId = subtitleController.primaryTrack?.id;
    L1SpecialtyView payload;
    try {
      payload = await service.l1SpecialtyOccurrences(
        difficultyKind: hint.difficultyKind,
        language: settingsController.resolveLearningLanguage(
          subtitleController.primaryTrack?.language,
        ),
        trackId: currentTrackId,
      );
    } catch (error) {
      playerController.setStatus(
        '${l.text('statusSpecialtyClipsUnavailable')}: $error',
        error: true,
      );
      return;
    }
    if (!mounted) return;
    final action = await showL1SpecialtyDialog(
      context: context,
      difficultyKindName: AppLocalizations.of(
        context,
      ).l1DifficultyName(hint.difficultyKind),
      payload: payload,
      currentTrackId: currentTrackId,
    );
    if (action == null || !mounted) return;
    if (action.action == 'play') {
      await _openSlicePlayback(action.occurrence.toJson());
      return;
    }
    final sentenceId = action.occurrence.sentenceId;
    final cues = subtitleController.primaryTrack?.cues ?? const <Cue>[];
    final cueIndex = cues.indexWhere((cue) => cue.id == sentenceId);
    if (cueIndex < 0) return;
    await _seekCue(cues[cueIndex]);
    await practiceActions.startSentenceDictationPractice();
  }

  Future<void> _openDiagnosisView() async {
    learningController.selectSidePanel(3);
    await _refreshDiagnosis();
  }

  Future<void> _toggleExtensiveListening() async {
    if (!extensiveListeningController.active) {
      final started = await extensiveListeningController.startSession(
        api: api,
        mediaId: playerController.mediaId,
        trackId: subtitleController.primaryTrack?.id,
      );
      if (started && mounted) {
        playerController.setStatus(l.text('statusExtensiveListeningStarted'));
      }
      return;
    }
    final huntingState = huntingSessionController.state;
    final huntingSummary = huntingState.enabled
        ? HuntingCompletionSummary(
            promptedCount: huntingState.promptedCount,
            recognizedCount: huntingState.recognizedCount,
            notRecognizedCount: huntingState.notRecognizedCount,
            notNoticedCount: huntingState.notNoticedCount,
          )
        : null;
    // Snapshot before the dialog opens so the figure the user confirms is the
    // one that gets reported; it is accumulated playing time, not wall clock.
    final playedDuration = extensiveListeningController.playedDuration;
    final report = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('finishExtensiveListening')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l
                  .text('extensiveSessionPlayedDuration')
                  .replaceAll('{duration}', formatDuration(playedDuration)),
            ),
            const SizedBox(height: ListenSpacing.gap12),
            Text(l.text('comprehensionReportPrompt')),
            if (huntingSummary != null) ...[
              const SizedBox(height: ListenSpacing.gap12),
              Text(
                l
                    .text('huntingCompletionSummary')
                    .replaceAll('{prompted}', '${huntingSummary.promptedCount}')
                    .replaceAll(
                      '{recognized}',
                      '${huntingSummary.recognizedCount}',
                    ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.text('skipReport')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'unclear'),
            child: Text(l.text('reportUnclear')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'got_the_gist'),
            child: Text(l.text('reportGist')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'understood_all'),
            child: Text(l.text('reportUnderstoodAll')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final finished = await extensiveListeningController.finishSession(
      api,
      comprehensionReport: report,
      huntingSummary: huntingSummary,
    );
    if (finished && mounted) {
      huntingSessionController.stop();
      playerController.setStatus(l.text('statusExtensiveListeningFinished'));
    }
  }

  Future<void> _hardInterruptListening() async {
    if (playerController.playing) await adapter.playOrPause();
    await inboxActions.captureListeningInbox();
    learningController.selectSidePanel(3);
    await _refreshDiagnosis();
    if (mounted) {
      playerController.setStatus(l.text('statusPausedForListeningCheck'));
    }
  }

  Future<void> _openVocabulary() => _showVocabulary();

  Future<void> _openListeningDictionaryEntry(String entryId) =>
      _showVocabulary(initialEntryId: entryId);

  Future<void> _acquireAuxiliaryAudioFocus() async {
    await adapter.pause();
    await recordingAdapter.pause();
    await slicePlayerController.pause();
  }

  void _playPronunciationAudio(String url) => unawaited(
    auxiliaryAudioController.playRemote(
      url,
      acquireAudioFocus: _acquireAuxiliaryAudioFocus,
    ),
  );

  Future<void> _showVocabulary({
    String? initialEntryId,
    bool openCrossModalReview = false,
  }) => showVocabularyFlow(
    context: context,
    api: api,
    settingsController: settingsController,
    subtitleController: subtitleController,
    playbackActions: playbackActions,
    practiceActions: practiceActions,
    huntingController: huntingController,
    auxiliaryAudio: auxiliaryAudioController,
    pauseBackgroundPlayback: _acquireAuxiliaryAudioFocus,
    initialEntryId: initialEntryId,
    openCrossModalReview: openCrossModalReview,
  );

  Future<void> _openReviewQueue() => openReviewQueueFlow(
    context: context,
    api: api,
    playerController: playerController,
    playbackActions: playbackActions,
    startReviewShadowing: _startReviewShadowing,
    startDelayedRetelling: _startDelayedRetelling,
  );

  Future<void> _openCoachDashboard() => openCoachDashboardFlow(
    context: context,
    api: api,
    language: settingsController.resolveLearningLanguage(
      subtitleController.primaryTrack?.language,
    ),
    openReviewQueue: _openReviewQueue,
    openVocabulary: ({bool openCrossModalReview = false}) =>
        _showVocabulary(openCrossModalReview: openCrossModalReview),
    openPersonalExpression: () => _openPersonalExpression(),
  );

  Future<void> _startReviewShadowing(ReviewQueueEntry entry) async {
    final mediaId = entry.item.source.mediaId;
    final startMs = entry.playbackStartMs;
    final endMs = entry.playbackEndMs;
    if (mediaId == null || startMs == null || endMs == null) return;
    final media = await api?.readMedia(mediaId);
    final path = media?.path;
    if (path == null || !File(path).existsSync()) {
      playerController.setStatus(
        l.text('statusReviewMediaUnavailable'),
        error: true,
      );
      return;
    }
    final sentenceId = entry.item.anchors
        .where((anchor) => anchor.kind == 'sentence')
        .map((anchor) => anchor.sentenceId)
        .whereType<String>()
        .firstOrNull;
    await practiceActions.startExternalShadowing(path, {
      'media_id': mediaId,
      'track_id': entry.item.source.trackId,
      'sentence_id': sentenceId,
      'sentence_text_snapshot': entry.item.promptSnapshot,
      'start_ms_snapshot': startMs,
      'end_ms_snapshot': endMs,
    });
  }

  Future<void> _startDelayedRetelling(ReviewQueueEntry entry) async {
    final service = api;
    final mediaId = entry.item.source.mediaId;
    if (service == null || mediaId == null) return;
    final media = await service.readMedia(mediaId);
    final path = media.path;
    if (!File(path).existsSync()) {
      playerController.setStatus(
        l.text('statusRetellMediaUnavailable'),
        error: true,
      );
      return;
    }
    if (playerController.mediaPath == null) {
      await mediaSession.openMediaPath(path);
      await adapter.pause();
    }
    if (!mounted) return;
    setState(() => _workbenchExpanded = true);
    _workbenchAnimController.forward();
    await speakingActions.openDelayedRetelling(
      service,
      entry: entry,
      mediaPath: path,
      fixedRubricPoints: listeningRetellTemplate(l),
      closeReading: readingChannel.close,
    );
  }

  Future<String?> _askPersonalExpressionAssessment() => showDialog<String>(
    context: context,
    builder: (context) {
      final l = AppLocalizations.of(context);
      return SimpleDialog(
        title: Text(l.text('peAssessTitle')),
        children: [
          for (final (value, labelKey) in const [
            ('needs_work', 'peAssessNeedsWork'),
            ('partly_expressed', 'peAssessPartly'),
            ('expressed', 'peAssessExpressed'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: Text(l.text(labelKey)),
            ),
        ],
      );
    },
  );

  Future<void> _openSubtitleResources() => openSubtitleResourcesFlow(
    context: context,
    api: api,
    playerController: playerController,
    subtitleController: subtitleController,
    learningController: learningController,
    resourceActions: resourceActions,
    mediaSession: mediaSession,
    onManualReviewTimeline: _openManualReviewTimeline,
  );

  void _openColdStartMarking() => openColdStartMarkingFlow(
    context: context,
    api: api,
    subtitleController: subtitleController,
    resourceActions: resourceActions,
  );

  Future<void> _loopSoundRibbonFinding(
    PhonemeRibbonFinding finding,
    List<DetectedPhone> phones,
  ) async {
    if (phones.isEmpty) return;
    final startIndex = finding.phoneStart.clamp(0, phones.length - 1).toInt();
    final endIndex = finding.phoneEnd
        .clamp(startIndex, phones.length - 1)
        .toInt();
    final start = phones[startIndex].start.inMilliseconds;
    final end = phones[endIndex].end.inMilliseconds;
    await playbackActions.loopRange(
      start,
      end,
      'Looping sound-line evidence',
      labelKey: 'loopEvidence',
    );
  }

  Future<void> _loopRhythmCue(
    Duration start,
    Duration end,
    String label,
  ) async {
    await playbackActions.loopRange(
      start.inMilliseconds,
      end.inMilliseconds,
      'Looping listening rhythm: $label',
      labelKey: 'loopRhythm',
    );
  }

  Future<void> _setSoundPatternDisplayMode(String mode) async {
    if (settingsController.soundPatternDisplayMode == mode) return;
    await settingsController.update(
      settingsController.settings.copyWith(soundPatternDisplayMode: mode),
    );
  }

  Future<void> _importWordList() => importWordListFlow(
    context: context,
    api: api,
    playerController: playerController,
    subtitleController: subtitleController,
    settingsController: settingsController,
    reloadWordEntries: vocabularyActions.loadWordEntries,
  );

  Future<void> _refreshDiagnosis() async {
    final cue = subtitleController.currentPrimaryCue;
    final service = api;
    if (cue == null || service == null) {
      if (mounted) learningController.setDiagnosis(null);
      return;
    }
    await learningWorkflowController.refreshDiagnosis(
      cue: cue,
      diagnose: service.diagnose,
      currentCueId: () => subtitleController.currentPrimaryCue?.id,
      setDiagnosis: (value) {
        if (mounted) learningController.setDiagnosis(value);
      },
    );
  }

  Future<void> _seekCue(Cue? cue) async {
    if (cue == null) return;
    subtitleController.setCurrentPrimaryCue(cue);
    unawaited(_refreshDiagnosis());
    await adapter.seek(subtitleController.primaryCursor.mediaStart(cue));
  }

  /// Saves the last playback position, then stops the sidecar — in that order.
  /// [ApiService.requestStop] force-closes the HTTP client, so firing it
  /// alongside the save would abort the request and lose the position.
  ///
  /// Never awaited: `dispose` must stay synchronous. If the app exits before
  /// the chain finishes, the sidecar reaps itself once its parent is gone.
  void _stopApiAfterFinalProgressSave() {
    final api = this.api;
    if (api == null) return;
    final mediaId = playerController.mediaId;
    final pendingSave = mediaId == null
        ? Future<void>.value()
        : api.saveProgress(mediaId, playerController.position);
    unawaited(
      pendingSave
          .timeout(const Duration(seconds: 2))
          .catchError((Object _) {})
          .whenComplete(api.requestStop),
    );
  }

  @override
  void dispose() {
    _stopApiAfterFinalProgressSave();
    playerController.removeListener(_surfaceErrorStatus);
    playerController.removeListener(_trackExtensivePlayback);
    _workbenchAnimController.dispose();
    downloadController.dispose();
    unawaited(_saveSettings());
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    transcriptController.dispose();
    progressTimer?.cancel();
    syntaxCapabilityTimer?.cancel();
    unawaited(adapter.dispose());
    unawaited(recordingAdapter.dispose());
    playerController.dispose();
    subtitleController.dispose();
    learningController.dispose();
    practiceController.dispose();
    slicePlayerController.dispose();
    auxiliaryAudioController.dispose();
    readingChannel.dispose();
    writingChannel.dispose();
    speakingChannel.dispose();
    readingController.dispose();
    readingTaskController.dispose();
    speakingTaskController.dispose();
    realtimeConversationController.dispose();
    writingTaskController.dispose();
    speakingActions.dispose();
    readingDiffController.dispose();
    extensiveListeningController.dispose();
    huntingController.dispose();
    huntingSessionController.dispose();
    settingsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (api == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (connectingApi) const ListenLoading(),
              const SizedBox(height: ListenSpacing.gap16),
              Text(status, textAlign: TextAlign.center),
              if (!connectingApi) ...[
                const SizedBox(height: ListenSpacing.gap12),
                FilledButton(
                  onPressed: () => unawaited(_connectApi()),
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([
        playerController,
        subtitleController,
        learningController,
        extensiveListeningController,
        huntingController,
        huntingSessionController,
        // One handle for "which content channel is on the stage"; each
        // channel's own page state stays inside its host.
        contentChannels.selection,
        settingsController,
        downloadController,
      ]),
      builder: (context, _) => AppControllers(
        player: playerController,
        subtitle: subtitleController,
        learning: learningController,
        extensiveListening: extensiveListeningController,
        practice: practiceController,
        settings: settingsController,
        api: api!,
        child: PlayerGlobalShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.space):
                practiceActions.togglePracticePlayback,
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                unawaited(practiceActions.navigatePracticeSentence(-1)),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                unawaited(practiceActions.navigatePracticeSentence(1)),
            const SingleActivator(LogicalKeyboardKey.keyL): () =>
                subtitleController.setLoopCue(!subtitleController.loopCue),
            const SingleActivator(LogicalKeyboardKey.keyH): () =>
                subtitleController.setVisible(!subtitleController.visible),
            const SingleActivator(LogicalKeyboardKey.keyI): () =>
                unawaited(inboxActions.captureListeningInbox()),
            const SingleActivator(LogicalKeyboardKey.keyI, shift: true): () =>
                unawaited(_toggleExtensiveListening()),
            const SingleActivator(LogicalKeyboardKey.keyP, shift: true): () =>
                unawaited(_hardInterruptListening()),
            const SingleActivator(LogicalKeyboardKey.digit1): () =>
                vocabularyActions.markFirstWord('unknown_meaning'),
            const SingleActivator(LogicalKeyboardKey.digit2): () =>
                vocabularyActions.markFirstWord('known_not_recognized'),
            const SingleActivator(LogicalKeyboardKey.digit3): () =>
                vocabularyActions.markFirstWord('known_recognized'),
          },
          child: Focus(
            autofocus: true,
            // The shell recedes (#46 signature action): while media plays on
            // the workbench and the pointer rests, app bar and transport fade
            // so only the content glows; movement or chrome focus brings
            // them back.
            child: ShellRecede(
              active: _workbenchExpanded && playerController.playing,
              builder: (context, shellVisible) => Scaffold(
                appBar: ShellFadeAppBar(
                  visible: shellVisible,
                  child: PlayerAppBar(
                    // One definition of availability for every menu (#24); the
                    // native macOS menu (#23) must reuse it. `api` is non-null on
                    // this branch, but the capability object states it explicitly
                    // rather than baking the screen-level invariant into the bar.
                    capabilities: AppBarCapabilities(
                      hasMedia: playerController.mediaId != null,
                      coreReady: api != null,
                    ),
                    onOpenSubtitleResources: () =>
                        unawaited(_openSubtitleResources()),
                    onOpenVocabulary: _openVocabulary,
                    onOpenReview: () => unawaited(_openReviewQueue()),
                    onOpenMedia: mediaSession.openMedia,
                    onOpenOnline: _openOnline,
                    onImportPrimarySubtitle: () =>
                        unawaited(mediaSession.openSubtitle(secondary: false)),
                    onGeneratePrimarySubtitles: () =>
                        unawaited(_generateSubtitles(secondary: false)),
                    onSearchPrimarySubtitles: () =>
                        unawaited(_searchOpenSubtitles(secondary: false)),
                    onImportSecondarySubtitle: () =>
                        unawaited(mediaSession.openSubtitle(secondary: true)),
                    onGenerateSecondarySubtitles: () =>
                        unawaited(_generateSubtitles(secondary: true)),
                    onSearchSecondarySubtitles: () =>
                        unawaited(_searchOpenSubtitles(secondary: true)),
                    onImportEmbeddedSubtitle: () =>
                        unawaited(_importEmbeddedSubtitle()),
                    onOpenSettings: () => unawaited(_openSettings()),
                    onExportLogs: () => unawaited(_exportLogs()),
                    onExportVocabulary: () =>
                        unawaited(playbackActions.exportVocabulary()),
                    onImportVocabulary: () =>
                        unawaited(playbackActions.importVocabulary()),
                    onImportWordList: () => unawaited(_importWordList()),
                    onArchiveMedia: () =>
                        unawaited(playbackActions.archiveCurrentMedia()),
                    onOpenTranscriptionCenter: () =>
                        unawaited(_openTranscriptionCenter()),
                    onOpenPhoneticAnalysisCenter: () =>
                        unawaited(_openPhoneticAnalysisCenter()),
                    onOpenLearningAssets: () =>
                        unawaited(_openLearningAssets()),
                    onOpenLearningResources: () =>
                        unawaited(_openLearningResources()),
                  ),
                ),
                body: DropTarget(
                  onDragEntered: (_) => setState(() => dragging = true),
                  onDragExited: (_) => setState(() => dragging = false),
                  onDragDone: (details) {
                    setState(() => dragging = false);
                    unawaited(
                      subtitleSources.handleDrop(
                        details.files.map((file) => file.path).toList(),
                      ),
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: dragging
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 4,
                            )
                          : null,
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              ListeningHome(
                                onOpenMedia: mediaSession.openMedia,
                                onOpenOnline: _openOnline,
                                onContinue: () {
                                  if (_workbenchExpanded ||
                                      playerController.mediaPath != null) {
                                    _expandWorkbench();
                                  } else {
                                    unawaited(
                                      mediaLibraryActions.continueRecentMedia(),
                                    );
                                  }
                                },
                                onOpenSubtitleResources: () =>
                                    unawaited(_openSubtitleResources()),
                                onOpenVocabulary: _openVocabulary,
                                onOpenPersonalExpressions: () =>
                                    unawaited(_openPersonalExpression()),
                                onOpenConversation: () =>
                                    unawaited(_openFreeConversation()),
                                onOpenReview: () =>
                                    unawaited(_openReviewQueue()),
                                onOpenCoach: () =>
                                    unawaited(_openCoachDashboard()),
                                onOpenSettings: () =>
                                    unawaited(_openSettings()),
                                mediaLibrary: mediaLibraryActions.mediaLibrary,
                                familiarSupplyEnabled: settingsController
                                    .familiarMaterialSuggestions,
                                onOpenLibraryEntry: (entry) => unawaited(
                                  mediaLibraryActions.openLibraryEntry(entry),
                                ),
                                onStartExtensiveEntry: (entry) => unawaited(
                                  mediaLibraryActions.startExtensiveFromLibrary(
                                    entry,
                                  ),
                                ),
                                onStartIntensiveEntry: (entry) => unawaited(
                                  mediaLibraryActions.startIntensiveFromLibrary(
                                    entry,
                                  ),
                                ),
                                onSetLibraryIntent: (entry, intent) =>
                                    unawaited(
                                      mediaLibraryActions
                                          .setLibraryTriageIntent(
                                            entry,
                                            intent,
                                          ),
                                    ),
                                onToggleFamiliarSupply: (enabled) => unawaited(
                                  mediaLibraryActions.toggleFamiliarSupply(
                                    enabled,
                                  ),
                                ),
                                recentMediaTitle:
                                    settingsController.lastMediaTitle.isEmpty
                                    ? null
                                    : settingsController.lastMediaTitle,
                                recentMediaPath:
                                    settingsController.lastMediaPath.isEmpty
                                    ? null
                                    : settingsController.lastMediaPath,
                                recentPosition: Duration(
                                  milliseconds:
                                      settingsController.lastMediaPositionMs,
                                ),
                                recentDuration: Duration(
                                  milliseconds:
                                      settingsController.lastMediaDurationMs,
                                ),
                                recentSubtitleCount:
                                    settingsController.lastMediaSubtitleCount,
                                vocabularyCount:
                                    mediaLibraryActions
                                        .savedVocabulary
                                        ?.total ??
                                    0,
                                vocabularyCapped:
                                    mediaLibraryActions
                                        .savedVocabulary
                                        ?.capped ??
                                    false,
                                vocabularyKnown:
                                    mediaLibraryActions.savedVocabulary != null,
                                listeningInboxCount:
                                    extensiveListeningController
                                        .activeItemCount,
                                coreStatusText:
                                    playerController.statusIsPlayback
                                    ? ''
                                    : playerController.status,
                              ),
                              if (playerController.mediaPath != null)
                                SlideTransition(
                                  position: _workbenchSlideAnimation,
                                  child: MediaWorkbench(
                                    mediaTitle: playerController.mediaPath!
                                        .split(Platform.pathSeparator)
                                        .last,
                                    playerStage: _playerStage(),
                                    learningPanel: _sidePanel(),
                                    selectedChannel: contentChannels.selected,
                                    channelAvailability: {
                                      ContentChannel.listening:
                                          const ContentChannelAvailability.available(),
                                      ContentChannel.reading:
                                          subtitleController.primaryTrack ==
                                              null
                                          ? ContentChannelAvailability.unavailable(
                                              l.text('channelNeedsTranscript'),
                                            )
                                          : const ContentChannelAvailability.available(),
                                      ContentChannel.speaking:
                                          subtitleController.primaryTrack ==
                                              null
                                          ? ContentChannelAvailability.unavailable(
                                              l.text('channelNeedsTranscript'),
                                            )
                                          : !Platform.isMacOS
                                          ? ContentChannelAvailability.unavailable(
                                              l.text('channelUnavailable'),
                                            )
                                          : const ContentChannelAvailability.available(),
                                      ContentChannel.writing:
                                          subtitleController.primaryTrack ==
                                              null
                                          ? ContentChannelAvailability.unavailable(
                                              l.text('channelNeedsTranscript'),
                                            )
                                          : const ContentChannelAvailability.available(),
                                    },
                                    onChannelSelected: (channel) => unawaited(
                                      contentChannels.select(channel),
                                    ),
                                    immersiveStage: switch (contentChannels
                                        .selected) {
                                      ContentChannel.writing =>
                                        WritingChannelHost(
                                          api: api!,
                                          writingChannel: writingChannel,
                                          writingTaskController:
                                              writingTaskController,
                                        ),
                                      ContentChannel.speaking =>
                                        SpeakingChannelHost(
                                          api: api!,
                                          speakingChannel: speakingChannel,
                                          speakingActions: speakingActions,
                                          speakingTaskController:
                                              speakingTaskController,
                                          readingTaskController:
                                              readingTaskController,
                                        ),
                                      ContentChannel.reading =>
                                        ReadingChannelHost(
                                          api: api!,
                                          readingChannel: readingChannel,
                                          readingController: readingController,
                                          readingTaskController:
                                              readingTaskController,
                                          readingDiffController:
                                              readingDiffController,
                                          learningController:
                                              learningController,
                                          settingsController:
                                              settingsController,
                                          subtitleController:
                                              subtitleController,
                                          playerController: playerController,
                                          vocabularyActions: vocabularyActions,
                                          onSaveSentencePattern: (source) =>
                                              _openPersonalExpression(
                                                source: source,
                                              ),
                                          onOpenSlicePlayback:
                                              _openSlicePlayback,
                                          onRecordReadingMark:
                                              _recordReadingMark,
                                          onOpenListeningDictionary:
                                              _openListeningDictionaryEntry,
                                          onPlayPronunciationAudio:
                                              _playPronunciationAudio,
                                          onCorrectLemma: () =>
                                              unawaited(_correctCurrentLemma()),
                                        ),
                                      ContentChannel.listening => null,
                                    },
                                    mediaFraction: settingsController
                                        .workbenchMediaFraction,
                                    onMediaFractionChanged:
                                        _setWorkbenchMediaFraction,
                                    onCollapse: _collapseWorkbench,
                                  ),
                                ),
                              PlayerOverlays(
                                api: api,
                                practiceController: practiceController,
                                slicePlayerController: slicePlayerController,
                                huntingSessionController:
                                    huntingSessionController,
                                subtitleController: subtitleController,
                                playerController: playerController,
                                practiceActions: practiceActions,
                                huntingActions: huntingActions,
                                onCloseSlicePlayback: _closeSlicePlayback,
                              ),
                            ],
                          ),
                        ),
                        if (downloadController.snapshot != null)
                          _downloadStatusBar(downloadController.snapshot!),
                        ShellFade(visible: shellVisible, child: _controls()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _playerStage() => PlayerStage(
    adapter: adapter,
    playerController: playerController,
    subtitleController: subtitleController,
    learningController: learningController,
    settingsController: settingsController,
    onSeekCue: _seekCue,
    onSeekChunk: playbackActions.seekChunk,
    onOpenWord: vocabularyActions.openWord,
    onOpenPhrase: _openPhrase,
    onLoopSoundRibbonFinding: _loopSoundRibbonFinding,
    onLoopRhythmCue: _loopRhythmCue,
    onSetSoundPatternDisplayMode: _setSoundPatternDisplayMode,
    onSaveSettings: _saveSettings,
    onOpenMedia: mediaSession.openMedia,
    onLoadSoundReference: settingsController.phoneticAnalysisPreference == 'off'
        ? null
        : subtitleSources.analyzePhonetics,
  );

  /// Describes where the word timings for [sentenceId] came from. Returns an
  /// empty string when the sentence has no timings; callers are expected to
  /// skip the label in that case (see [SidePanel]'s `timingQuality` guard).
  String _timingQuality(String sentenceId) {
    final timings = subtitleController.timingsBySentence[sentenceId];
    if (timings == null || timings.isEmpty) return '';
    final first = timings.first;
    return '${first.source.replaceAll('_', ' ')} · ${first.provider}';
  }

  Widget _sidePanel() => SidePanel(
    playerController: playerController,
    subtitleController: subtitleController,
    learningController: learningController,
    extensiveListeningController: extensiveListeningController,
    settingsController: settingsController,
    resourceActions: resourceActions,
    mediaSession: mediaSession,
    playbackActions: playbackActions,
    transcriptController: transcriptController,
    onOpenWord: vocabularyActions.openWord,
    onSeekCue: _seekCue,
    onSetSelectedWordStatus: vocabularyActions.setSelectedWordStatus,
    onSetCapabilityOverride: vocabularyActions.setCapabilityOverride,
    onSaveSelectedLearningContent:
        vocabularyActions.saveSelectedLearningContent,
    onObserveSelected: vocabularyActions.observeSelected,
    onManualReviewTimeline: _openManualReviewTimeline,
    onDeleteSubtitle: _deleteSubtitleResource,
    onExportSubtitle: _exportSubtitleResource,
    onStartClozePractice: practiceActions.startClozePractice,
    onStartChunkDictationPractice: practiceActions.startChunkDictationPractice,
    onStartSentenceDictationPractice:
        practiceActions.startSentenceDictationPractice,
    onStartShadowingPractice: practiceActions.startShadowingPractice,
    onOpenReading: () => unawaited(readingChannel.open()),
    onOpenDiagnosisView: _openDiagnosisView,
    onOpenSlicePlayback: _openSlicePlayback,
    onOpenListeningDictionary: _openListeningDictionaryEntry,
    onPlayPronunciationAudio: _playPronunciationAudio,
    onOpenL1Specialty: _openL1Specialty,
    onCorrectLemma: () => unawaited(_correctCurrentLemma()),
    onRefreshListeningInbox: inboxActions.refreshListeningInbox,
    onReplayListeningInboxItem: inboxActions.replayListeningInboxItem,
    onProcessListeningInboxItem: inboxActions.processListeningInboxItem,
    timingQuality: _timingQuality,
    onStartColdStart: _openColdStartMarking,
    onRecordCurrentSource: vocabularyActions.recordCurrentSource,
    onReadingMark: readingController.isOpen
        ? (understood) => unawaited(_recordReadingMark(understood))
        : null,
  );

  Widget _controls() => PlaybackBar(
    adapter: adapter,
    playerController: playerController,
    extensiveListeningController: extensiveListeningController,
    huntingSessionController: huntingSessionController,
    subtitleController: subtitleController,
    mediaSession: mediaSession,
    playbackActions: playbackActions,
    taskStatuses: taskStatuses.values.toList(growable: false),
    onSeekCue: _seekCue,
    onToggleExtensiveListening: _toggleExtensiveListening,
    onToggleHunting: huntingActions.toggleHuntingMode,
    onCaptureListeningInbox: inboxActions.captureListeningInbox,
    onHardInterruptListening: _hardInterruptListening,
    onSaveSettings: _saveSettings,
    isCompact: playerController.mediaPath != null && !_workbenchExpanded,
    mediaTitle: playerController.mediaPath?.split(Platform.pathSeparator).last,
    onExpand: _expandWorkbench,
  );

  Widget _downloadStatusBar(DownloadStatusSnapshot downloadStatus) =>
      DownloadStatusBar(
        status: downloadStatus,
        onCancel: () {
          downloadController.cancel();
          playerController.setStatus(l.text('downloadCancelled'));
        },
        onOpenMediaPath: () {
          final path = downloadStatus.downloadedMediaPath;
          if (path != null) {
            downloadController.dismiss();
            unawaited(mediaSession.openMediaPath(path));
          }
        },
        onDismiss: downloadController.dismiss,
      );
}
