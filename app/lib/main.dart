import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'controllers/auxiliary_audio_controller.dart';
import 'controllers/backend_event_coordinator.dart';
import 'controllers/content_channel_coordinator.dart';
import 'controllers/content_package_journey_view_model.dart';
import 'controllers/discovery_view_model.dart';
import 'controllers/core_session_controller.dart';
import 'controllers/download_controller.dart';
import 'controllers/extensive_listening_controller.dart';
import 'controllers/hunting_actions_coordinator.dart';
import 'controllers/hunting_controller.dart';
import 'controllers/hunting_session_controller.dart';
import 'controllers/immersive_mode_controller.dart';
import 'controllers/learning_controller.dart';
import 'controllers/learning_assets_view_models.dart';
import 'controllers/learning_flow_view_models.dart';
import 'controllers/learning_workflow_controller.dart';
import 'controllers/listening_inbox_coordinator.dart';
import 'controllers/manual_review_flow_controller.dart';
import 'controllers/media_import_flow_controller.dart';
import 'controllers/media_library_coordinator.dart';
import 'controllers/media_session_coordinator.dart';
import 'controllers/occurrence_media_resolver.dart';
import 'controllers/playback_actions_coordinator.dart';
import 'controllers/player_controller.dart';
import 'controllers/phonetic_analysis_view_model.dart';
import 'controllers/practice_actions_coordinator.dart';
import 'controllers/practice_controller.dart';
import 'controllers/provider_settings_view_models.dart';
import 'controllers/personal_expression_view_model.dart';
import 'controllers/reading_channel_coordinator.dart';
import 'controllers/reading_controller.dart';
import 'controllers/reading_diff_controller.dart';
import 'controllers/reading_task_controller.dart';
import 'controllers/realtime_conversation_controller.dart';
import 'controllers/realtime_transcription_model_controller.dart';
import 'controllers/review_controller.dart';
import 'controllers/semantic_search_view_model.dart';
import 'controllers/resource_actions_coordinator.dart';
import 'controllers/settings_controller.dart';
import 'controllers/slice_player_controller.dart';
import 'controllers/speaking_actions_coordinator.dart';
import 'controllers/speaking_channel_coordinator.dart';
import 'controllers/speaking_task_controller.dart';
import 'controllers/speech_enhancement_workflow_controller.dart';
import 'controllers/subtitle_controller.dart';
import 'controllers/subtitle_sources_coordinator.dart';
import 'controllers/transcription_view_models.dart';
import 'controllers/vocabulary_actions_coordinator.dart';
import 'controllers/vocabulary_view_model.dart';
import 'controllers/coach_dashboard_controller.dart';
import 'controllers/cold_start_marking_view_model.dart';
import 'controllers/writing_channel_coordinator.dart';
import 'controllers/writing_task_controller.dart';
import 'data/repositories/core_repositories.dart';
import 'data/repositories/discovery_repository.dart';
import 'screens/discovery_home_screen.dart';
import 'theme/icon_size.dart';
import 'data/repositories/core_session_repository.dart';
import 'data/repositories/media_import_repository.dart';
import 'localization.dart';
import 'models/capability_readiness.dart';
import 'models/backend_event.dart';
import 'models/content_activity.dart';
import 'models/content_channel.dart';
import 'models/personal_expression.dart';
import 'models/practice.dart';
import 'models/task_status.dart';
import 'models/timeline.dart';
import 'models/types.dart';
import 'player_adapter.dart';
import 'player_shortcuts.dart';
import 'services/core_transport_service.dart';
import 'services/desktop_playback_bootstrap.dart';
import 'services/diagnostic_log_export_service.dart';
import 'services/external_tools.dart';
import 'services/file_transfer_service.dart';
import 'services/fullscreen_window.dart';
import 'services/media_import_file_service.dart';
import 'services/platform_capabilities.dart';
import 'services/smoke_launch_configuration_service.dart';
import 'settings.dart';
import 'theme/listen_theme.dart';
import 'theme/spacing.dart';
import 'ui/core/app_controller_scope.dart';
import 'utils/format_duration.dart';
import 'widgets/app_bar/app_bar_capabilities.dart';
import 'widgets/app_bar/macos_menu_bar.dart';
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
import 'widgets/layout/desktop_drop_surface.dart';
import 'widgets/layout/media_workbench.dart';
import 'widgets/layout/playback_bar.dart';
import 'widgets/layout/player_overlays.dart';
import 'widgets/layout/player_stage.dart';
import 'widgets/layout/shell_recede.dart';
import 'widgets/layout/side_panel.dart';
import 'widgets/panels/conversation_stage_shell.dart';
import 'widgets/panels/l1_specialty_dialog.dart';
import 'widgets/panels/realtime_conversation_panel.dart';
import 'widgets/player/download_status_bar.dart';
import 'widgets/player/player_global_shortcuts.dart';
import 'widgets/player/shortcut_cheat_sheet.dart';
import 'widgets/settings/settings_flow.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const FvpDesktopPlaybackBootstrap().initialize();
  runApp(
    const ListenApp(
      platformCapabilities: LocalPlatformCapabilities(),
      pathHelper: PlatformPathHelper(),
      smokeLaunchConfiguration: EnvironmentSmokeLaunchConfigurationService(),
    ),
  );
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
  const ListenApp({
    super.key,
    required this.platformCapabilities,
    required this.pathHelper,
    required this.smokeLaunchConfiguration,
  });

  final PlatformCapabilities platformCapabilities;
  final PlatformPathHelper pathHelper;
  final SmokeLaunchConfigurationService smokeLaunchConfiguration;

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
      home: PlayerScreen(
        platformCapabilities: platformCapabilities,
        pathHelper: pathHelper,
        smokeLaunchConfiguration: smokeLaunchConfiguration,
      ),
    ),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.platformCapabilities,
    required this.pathHelper,
    required this.smokeLaunchConfiguration,
  });

  final PlatformCapabilities platformCapabilities;
  final PlatformPathHelper pathHelper;
  final SmokeLaunchConfigurationService smokeLaunchConfiguration;

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
  Timer? syntaxCapabilityTimer;
  final coreTransport = LocalCoreTransportService();
  final discoveryMode = ValueNotifier<bool>(true);
  late final DiscoveryViewModel discoveryViewModel = DiscoveryViewModel(
    LiveDiscoveryRepository(),
    mediaImportRepository,
    coreRepositories.contentPackage,
    coreRepositories.mediaLibrary,
  )..load();
  late final coreSessionRepository = LocalCoreSessionRepository(coreTransport);
  late final coreRepositories = LocalCoreRepositories(coreTransport);
  late final coreSessionController = CoreSessionController(
    repository: coreSessionRepository,
    currentMediaId: () => playerController.mediaId,
    currentPosition: () => playerController.position,
    onProgressTick: mediaLibraryActions.recordRecentMedia,
  );
  late final DiagnosticLogExportService diagnosticLogExportService =
      LocalDiagnosticLogExportService(
        CallbackDiagnosticLogSource(
          () => coreSessionController.diagnosticLogPath,
        ),
      );
  late final mediaSessionRepository = coreRepositories.mediaSession;
  late final subtitleAnalysisRepository = coreRepositories.subtitleAnalysis;

  // ── Controllers ──
  final playerController = PlayerController();
  final subtitleController = SubtitleController();
  final learningController = LearningController();
  late final practiceController = PracticeController(
    repository: coreRepositories.practice,
  );
  final slicePlayerController = SlicePlayerController();
  late final auxiliaryAudioController = AuxiliaryAudioController(
    speechRepository: coreRepositories.speechSynthesis,
  );
  final readingController = ReadingController();
  late final readingTaskRepository = coreRepositories.readingTask;
  late final readingSessionRepository = coreRepositories.readingSession;
  late final readingTaskController = ReadingTaskController(
    repository: readingTaskRepository,
  );
  late final speakingTaskController = SpeakingTaskController(
    repository: coreRepositories.speakingTask,
  );
  late final speakingSessionRepository = coreRepositories.speakingSession;
  late final realtimeConversationController = RealtimeConversationController(
    repository: coreRepositories.realtimeConversation,
  );
  late final writingTaskController = WritingTaskController(
    repository: coreRepositories.writingTask,
  );
  late final readingDiffController = ReadingDiffController(
    repository: readingTaskRepository,
  );
  late final huntingRepository = coreRepositories.hunting;
  late final listeningRepository = coreRepositories.listening;
  late final extensiveListeningController = ExtensiveListeningController(
    repository: listeningRepository,
  );
  late final huntingController = HuntingController(
    repository: huntingRepository,
  );
  late final huntingSessionController = HuntingSessionController(
    repository: huntingRepository,
  );
  late final learningWorkflowController = LearningWorkflowController(
    repository: coreRepositories.learning,
  );
  late final speechEnhancementWorkflowController =
      SpeechEnhancementWorkflowController(
        repository: coreRepositories.speechEnhancement,
      );
  final settingsController = SettingsController();
  late final downloadController = DownloadController(
    failureMapper: coreSessionRepository.failureDetail,
  );
  late final resourceActions = ResourceActionsCoordinator(
    player: playerController,
    subtitle: subtitleController,
    speechEnhancement: speechEnhancementWorkflowController,
    repository: coreRepositories.resource,
  );
  late final playbackActions = PlaybackActionsCoordinator(
    adapter: adapter,
    player: playerController,
    subtitle: subtitleController,
    repository: coreRepositories.playback,
  );
  late final mediaSession = MediaSessionCoordinator(
    adapter: adapter,
    player: playerController,
    subtitle: subtitleController,
    learning: learningController,
    settings: settingsController,
    speechEnhancement: speechEnhancementWorkflowController,
    resourceActions: resourceActions,
    repository: mediaSessionRepository,
    subtitleAnalysis: subtitleAnalysisRepository,
  );
  late final huntingActions = HuntingActionsCoordinator(
    huntingSession: huntingSessionController,
    player: playerController,
    extensiveListening: extensiveListeningController,
    subtitle: subtitleController,
    repository: huntingRepository,
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
    repository: coreRepositories.mediaLibrary,
  );
  late final subtitleSources = SubtitleSourcesCoordinator(
    player: playerController,
    subtitle: subtitleController,
    settings: settingsController,
    repository: subtitleAnalysisRepository,
  );
  late final mediaImportRepository = LocalMediaImportRepository(
    tools,
    const LocalMediaImportFileService(),
    coreSessionRepository.failureDetail,
  );
  late final mediaImportController = MediaImportFlowController(
    mediaImportRepository,
    adapter,
    mediaSession,
    () => coreSessionController.state.isConnected,
    subtitleSources.isMediaPath,
    playerController: playerController,
    subtitleController: subtitleController,
    downloadController: downloadController,
  );
  late final readingChannel = ReadingChannelCoordinator(
    adapter: adapter,
    player: playerController,
    subtitle: subtitleController,
    settings: settingsController,
    reading: readingController,
    readingTask: readingTaskController,
    readingDiff: readingDiffController,
    repository: readingSessionRepository,
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
    repository: speakingSessionRepository,
  );
  late final contentChannels = ContentChannelCoordinator(
    reading: readingChannel,
    speaking: speakingChannel,
    speakingActions: speakingActions,
    writing: writingChannel,
  );
  // #25-A: fullscreen immersive playback. A fullscreen window without media
  // on the stage is just a big window, so the gate follows the media.
  late final immersiveMode = ImmersiveModeController(
    window: MacosFullscreenWindow(),
    canEnter: () => playerController.mediaPath != null,
  );

  // ── Local UI state (not managed by controllers) ──
  String get status => playerController.status;
  final taskStatuses = <UserTaskKind, UserTaskStatus>{};
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
  CoreConnectionStatus? _lastCoreStatus;
  int _handledCoreConnectionGeneration = 0;

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
    playerController.addListener(_exitImmersiveWhenMediaCloses);
    coreSessionController.addListener(_onCoreSessionStateChanged);
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
      isMounted: () => mounted,
      text: (key) => l.text(key),
      confirmLLTimelineMismatch: _confirmLLTimelineMismatch,
      onMediaSwitched: () {
        unawaited(slicePlayerController.close());
        if (speakingActions.isOpen) {
          speakingChannel.closeL1Check();
          unawaited(speakingActions.close(restorePosition: false));
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
      isMounted: () => mounted,
      text: (key) => l.text(key),
      reloadLearningEntries: () async {
        await vocabularyActions.loadWordEntries();
        await vocabularyActions.loadPhraseEntries();
      },
    );
    huntingActions.bind(isMounted: () => mounted, text: (key) => l.text(key));
    inboxActions.bind(isMounted: () => mounted, text: (key) => l.text(key));
    practiceActions.bind(
      isMounted: () => mounted,
      text: (key) => l.text(key),
      refreshDiagnosis: _refreshDiagnosis,
      seekCue: _seekCue,
    );
    vocabularyActions.bind(
      isMounted: () => mounted,
      text: (key) => l.text(key),
      refreshDiagnosis: _refreshDiagnosis,
    );
    mediaLibraryActions.bind(
      isMounted: () => mounted,
      text: (key) => l.text(key),
      requestRebuild: () => setState(() {}),
      openMediaPath: mediaSession.openMediaPath,
      openMedia: mediaSession.openMedia,
    );
    readingChannel.bind(
      isMounted: () => mounted,
      openSlicePlayback: _openSlicePlayback,
      openWord: vocabularyActions.openWord,
    );
    contentChannels.bind(
      speakingAvailable: () =>
          coreSessionController.state.isConnected &&
          widget.platformCapabilities.isMacOS,
      openSpeaking: _openContentSpeakingActivity,
      openWriting: () => writingChannel.openTask(
        writingChannel.kind,
        promptSnapshot: writingPrompt(l, writingChannel.kind),
        fixedRubricPoints: writingTaskTemplate(l),
      ),
    );
    speakingChannel.text = (key) => l.text(key);
    speakingChannel.bind(
      isMounted: () => mounted,
      askPersonalExpressionAssessment: _askPersonalExpressionAssessment,
      onReturnToReview: () => unawaited(_openReviewQueue()),
      onReturnToPersonalExpression: () => unawaited(_openPersonalExpression()),
    );
    writingChannel.bind(
      isMounted: () => mounted,
      openSlicePlayback: _openSlicePlayback,
      closeOtherChannels: () async {
        speakingChannel.closeL1Check();
        if (speakingActions.isOpen) await speakingActions.close();
        await readingChannel.close();
      },
    );
    subtitleSources.bind(
      isMounted: () => mounted,
      text: (key) => l.text(key),
      showSnackBar: _showSnackBar,
      setTaskStatus: _setTaskStatus,
      openMediaPath: mediaSession.openMediaPath,
      openSubtitlePath: mediaSession.openSubtitlePath,
    );
    // Core status localization reads `context`, which is only
    // legal once initState has completed and dependencies are resolved.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(coreSessionController.connect());
    });
    unawaited(_loadSettings());
    subscriptions.addAll([
      coreSessionController.events.listen(_onEvent),
      adapter.position.listen(_onPosition),
      adapter.duration.listen((value) {
        playerController.setDuration(value);
      }),
      adapter.playing.listen((value) {
        playerController.setPlaying(value);
      }),
      adapter.errors.listen((failure) {
        playerController.setNamedFailure(failure, l.text);
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

  /// Keyboard volume/rate (#25) persist exactly like the transport slider.
  Future<void> _keyboardVolumeBy(double delta) async {
    await playbackActions.volumeBy(delta);
    await _saveSettings();
  }

  Future<void> _keyboardRateBy(double delta) async {
    await playbackActions.rateBy(delta);
    await _saveSettings();
  }

  void _setWorkbenchMediaFraction(double value) {
    settingsController.setSettings(
      settingsController.settings.copyWith(workbenchMediaFraction: value),
    );
    settingsController.saveSoon();
  }

  void _onCoreSessionStateChanged() {
    if (!mounted) return;
    final state = coreSessionController.state;
    learningController.availableLanguages = state.availableLanguages;
    if (!state.isConnected) {
      syntaxCapabilityTimer?.cancel();
      syntaxCapabilityTimer = null;
    }
    if (_lastCoreStatus != state.status) {
      _lastCoreStatus = state.status;
      switch (state.status) {
        case CoreConnectionStatus.disconnected:
          break;
        case CoreConnectionStatus.connecting:
          playerController.setStatus(l.text('statusStartingCore'));
        case CoreConnectionStatus.connected:
          playerController.setStatus(l.text('statusCoreConnected'));
        case CoreConnectionStatus.failed:
          playerController.setStatus(
            l.text('statusCoreUnavailable'),
            error: true,
            failure: state.failure,
          );
      }
    }
    if (state.isConnected &&
        state.connectionGeneration > _handledCoreConnectionGeneration) {
      _handledCoreConnectionGeneration = state.connectionGeneration;
      syntaxCapabilityTimer?.cancel();
      syntaxCapabilityTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(subtitleSources.checkSyntaxCapability()),
      );
      unawaited(subtitleSources.checkSyntaxCapability());
      unawaited(mediaLibraryActions.prefetchHomeSummary());
      unawaited(_runSmokeIfConfigured());
    }
    setState(() {});
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
    final configuration = widget.smokeLaunchConfiguration.read();
    if (configuration == null) return;
    await mediaSession.openMediaPath(configuration.mediaPath);
    if (configuration.primarySubtitlePath case final subtitle?) {
      await mediaSession.openSubtitlePath(subtitle, secondary: false);
    }
    if (configuration.secondarySubtitlePath case final secondary?) {
      await mediaSession.openSubtitlePath(secondary, secondary: true);
    }
  }

  void _onEvent(BackendEvent event) {
    BackendEventCoordinator(
      currentMediaId: () => playerController.mediaId,
      currentPrimaryTrackId: () => subtitleController.primaryTrack?.id,
      loadWordEntries: vocabularyActions.loadWordEntries,
      loadTimelineResource: resourceActions.loadTimelineResource,
      readSubtitle: mediaSessionRepository.readSubtitle,
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
    ).handleEvent(event);
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
        playerController: playerController,
        resourceActions: resourceActions,
        track: track,
      );

  Future<void> _openManualReviewTimeline() async {
    final controller = ManualReviewFlowController(
      coreSessionController.state.isConnected
          ? coreRepositories.manualReview
          : null,
      adapter,
      resourceActions,
      mediaSession,
      playerController: playerController,
      subtitleController: subtitleController,
    );
    try {
      await openManualReviewFlow(context: context, controller: controller);
    } finally {
      controller.dispose();
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _generateSubtitles({required bool secondary}) =>
      generateSubtitlesFlow(
        context: context,
        viewModel: !coreSessionController.state.isConnected
            ? null
            : GenerateSubtitlesViewModel(
                coreRepositories.transcription,
                mediaId: playerController.mediaId ?? '',
                secondary: secondary,
                preferredQuality: settingsController.transcriptionQuality,
                preferredLanguage: settingsController.transcriptionLanguage,
              ),
        playerController: playerController,
        recordTaskStatus: (value) {
          setState(() {
            taskStatuses[value.kind] = value;
          });
        },
      );

  Future<void> _openTranscriptionCenter() {
    final repository = coreSessionController.state.isConnected
        ? coreRepositories.transcription
        : null;
    return openTranscriptionCenterFlow(
      context: context,
      viewModel: repository == null
          ? null
          : TranscriptionCenterViewModel(
              repository,
              loadTrack: mediaSession.loadGeneratedTrack,
            ),
      createRegenerateViewModel: (job) => GenerateSubtitlesViewModel(
        repository!,
        mediaId: job.mediaId,
        secondary: job.destination == 'secondary',
        preferredQuality: settingsController.transcriptionQuality,
        preferredLanguage: settingsController.transcriptionLanguage,
        force: true,
      ),
      playerController: playerController,
    );
  }

  Future<void> _openPhoneticAnalysisCenter() => openPhoneticAnalysisCenterFlow(
    context: context,
    viewModel: !coreSessionController.state.isConnected
        ? null
        : PhoneticAnalysisViewModel(coreRepositories.phoneticAnalysis),
    playerController: playerController,
  );

  Future<void> _openOnline() => openOnlineMediaFlow(
    context: context,
    controller: mediaImportController,
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
    controller: mediaImportController,
  );

  Future<void> _openSettings() async {
    final available = coreSessionController.state.isConnected;
    final learnerViewModel = !available
        ? null
        : LearnerSettingsViewModel(coreRepositories.learnerSettings);
    final llmViewModel = !available
        ? null
        : LlmProviderSettingsViewModel(coreRepositories.llmProvider);
    final realtimeViewModel = !available
        ? null
        : RealtimeProviderSettingsViewModel(coreRepositories.realtimeProvider);
    final syntaxViewModel = !available
        ? null
        : SyntaxCapabilitySettingsViewModel(
            coreRepositories.syntaxCapability,
            currentTrackId: subtitleController.primaryTrack?.id,
          );
    try {
      await showAppSettings(
        context: context,
        settingsController: settingsController,
        subtitleController: subtitleController,
        playerController: playerController,
        learningController: learningController,
        saveSettings: _saveSettings,
        learnerViewModel: learnerViewModel,
        llmViewModel: llmViewModel,
        realtimeViewModel: realtimeViewModel,
        syntaxViewModel: syntaxViewModel,
      );
    } finally {
      learnerViewModel?.dispose();
      llmViewModel?.dispose();
      realtimeViewModel?.dispose();
      syntaxViewModel?.dispose();
    }
  }

  Future<void> _openContentSpeakingActivity() async {
    final activity = await showContentSpeakingActivityDialog(context);
    if (!mounted || activity == null) return;
    switch (activity) {
      case ContentSpeakingActivity.retelling:
        await speakingActions.openRetelling(
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
    if (!coreSessionController.state.isConnected ||
        !widget.platformCapabilities.isMacOS) {
      return;
    }
    final language =
        selection?.language ??
        settingsController.resolveLearningLanguage(
          subtitleController.primaryTrack?.language,
        );
    final modelOutcome = await RealtimeTranscriptionModelController(
      coreRepositories.transcription,
    ).selectForLanguage(language);
    if (!mounted) return;
    if (modelOutcome is RealtimeTranscriptionModelFailure) {
      playerController.setStatus(
        l.text('statusCoreUnavailable'),
        error: true,
        failure: modelOutcome.failure,
      );
      return;
    }
    if (modelOutcome is! RealtimeTranscriptionModelSelected) {
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
    // A returning user must land on the lobby, not a stale debrief: the
    // controller is a singleton that outlives the route, so its terminal
    // state (done/failed + items) would re-render the old debrief on re-entry.
    realtimeConversationController.resetToIdle();
    await Navigator.push<void>(
      context,
      // The stage powers on instead of sliding in like a page of chrome
      // (#83). It stays a window-sized dark room: F and macOS fullscreen
      // remain the player's (#25 boundary untouched).
      conversationStageRoute<void>(
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        builder: (routeContext) => RealtimeConversationPanel(
          controller: realtimeConversationController,
          launch: selection == null
              ? RealtimeConversationLaunch.free(
                  language: language,
                  modelId: modelOutcome.modelId,
                )
              : RealtimeConversationLaunch.topic(
                  anchor: RealtimeConversationAnchor(
                    language: selection.language,
                    text: selection.transcriptSnapshot,
                    mediaId: selection.mediaId,
                    startMs: selection.startMs,
                    endMs: selection.endMs,
                  ),
                  modelId: modelOutcome.modelId,
                ),
          acquireAudioFocus: speakingActions.acquireRecordingFocus,
          onClose: () => Navigator.pop(routeContext),
          // Realtime provider configuration lives in settings (#87); the
          // conversation route covers the app bar, so it hands the learner
          // back there instead of hosting the form itself.
          onManageVoices: _openSettings,
          // The lobby's caption switch is a habit, so it is remembered
          // across conversations and restarts (#85 · S8).
          captionEnabled: settingsController.realtimeCaptionVisible,
          onCaptionEnabledChanged: (value) =>
              unawaited(settingsController.setRealtimeCaptionVisible(value)),
          // The debrief's 回流 is a door, not a claim (#86 · S9): the words
          // this conversation handed to the speaking channel are in the
          // vocabulary book, and an amber target goes straight into 我的表达.
          onOpenVocabulary: _openVocabulary,
          // `manual`, not a conversation source kind: the turn never became
          // learner output, so what the learner keeps here is something they
          // are writing down — the backend's production evidence is not
          // allowed to gain a row from a turn the loop never closed.
          onSaveExpression: (text) => _openPersonalExpression(
            source: PersonalExpressionSourceView(kind: 'manual', text: text),
          ),
        ),
      ),
    );
  }

  Future<void> _openLearningAssets() {
    final available = coreSessionController.state.isConnected;
    final language = settingsController.resolveLearningLanguage(
      subtitleController.primaryTrack?.language,
    );
    final expressionRepository = !available
        ? null
        : coreRepositories.personalExpression;
    return openLearningAssetsFlow(
      context: context,
      viewModel: !available
          ? null
          : LearningAssetsViewModel(
              coreRepositories.learningAssets,
              language: language,
            ),
      createPersonalExpressionViewModel: expressionRepository == null
          ? null
          : () => PersonalExpressionViewModel(
              expressionRepository,
              language: language,
            ),
      createPersonalExpressionDetailViewModel: expressionRepository == null
          ? null
          : (pattern) => PersonalExpressionDetailViewModel(
              expressionRepository,
              pattern: pattern,
            ),
      playerController: playerController,
      openSlicePlayback: _openSlicePlayback,
      onPlaySource: _playPersonalExpressionSource,
      onStartSpeaking: _startPersonalExpressionSpeaking,
    );
  }

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
    if (!coreSessionController.state.isConnected ||
        !widget.platformCapabilities.isMacOS) {
      return;
    }
    speakingChannel.activePersonalPattern = pattern;
    setState(() => _workbenchExpanded = true);
    _workbenchAnimController.forward();
    await speakingActions.openPersonalPattern(
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

  Future<void> _openPersonalExpression({PersonalExpressionSourceView? source}) {
    final available = coreSessionController.state.isConnected;
    final language = settingsController.resolveLearningLanguage(
      subtitleController.primaryTrack?.language,
    );
    final repository = !available ? null : coreRepositories.personalExpression;
    return openPersonalExpressionFlow(
      context: context,
      viewModel: repository == null
          ? null
          : PersonalExpressionViewModel(repository, language: language),
      createDetailViewModel: repository == null
          ? null
          : (pattern) =>
                PersonalExpressionDetailViewModel(repository, pattern: pattern),
      playerController: playerController,
      initialSource: source,
      onPlaySource: _playPersonalExpressionSource,
      onStartSpeaking: _startPersonalExpressionSpeaking,
    );
  }

  Future<void> _openLearningResources() => openLearningResourcesFlow(
    context: context,
    viewModel: !coreSessionController.state.isConnected
        ? null
        : LearningResourcesViewModel(coreRepositories.learningAssets),
    playerController: playerController,
  );

  Future<void> _openPhrase(PhraseCandidate candidate, Cue cue) =>
      openPhraseFlow(
        context: context,
        viewModel: !coreSessionController.state.isConnected
            ? null
            : PhraseCandidateViewModel(
                coreRepositories.learningAssets,
                candidate: candidate,
                initialStatus: learningController
                    .phraseEntries[candidate.canonicalForm]
                    ?.entry
                    .status,
                source: {
                  'language': settingsController.resolveLearningLanguage(
                    subtitleController.primaryTrack?.language,
                  ),
                  'media_id': playerController.mediaId,
                  'sentence_id': cue.id,
                  'sentence_text': cue.text,
                  'media_title': playerController.mediaTitle ?? '',
                  'media_fingerprint': playerController.mediaFingerprint,
                  'start_ms': cue.start.inMilliseconds,
                  'end_ms': cue.end.inMilliseconds,
                },
              ),
        playerController: playerController,
        learningController: learningController,
      );

  Future<void> _correctCurrentLemma() {
    final token = learningController.selectedToken;
    final original = token?.normalized;
    return correctCurrentLemmaFlow(
      context: context,
      viewModel: !coreSessionController.state.isConnected || original == null
          ? null
          : LemmaCorrectionViewModel(
              coreRepositories.lexical,
              original: original,
              language: settingsController.resolveLearningLanguage(
                subtitleController.primaryTrack?.language,
              ),
            ),
      playerController: playerController,
      learningController: learningController,
    );
  }

  Future<void> _searchOpenSubtitles({required bool secondary}) =>
      searchOpenSubtitlesFlow(
        context: context,
        controller: OpenSubtitlesFlowController(
          coreSessionController.state.isConnected
              ? coreRepositories.learningAssets
              : null,
          mediaSession,
          playerController: playerController,
          settingsController: settingsController,
        ),
        secondary: secondary,
      );

  Future<void> _exportLogs() async {
    final outcome = await diagnosticLogExportService.export();
    switch (outcome) {
      case DiagnosticLogUnavailable():
        playerController.setStatus(l.text('statusNoCoreLog'));
      case DiagnosticLogExportCancelled():
        return;
      case DiagnosticLogExported(:final path):
        playerController.setStatus(
          l.text('statusExportedDiagnostics').replaceAll('{path}', path),
        );
      case DiagnosticLogExportFailed(:final error):
        playerController.setStatus(
          l.text('statusNoCoreLog'),
          error: true,
          failure: coreSessionRepository.failureDetail(error),
        );
    }
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
    final entry = learningController.selectedLexicalDetails?.entry;
    final token = learningController.selectedToken;
    final cue = learningController.selectedCue;
    if (!coreSessionController.state.isConnected ||
        entry == null ||
        token == null) {
      return;
    }
    try {
      await learningWorkflowController.recordReadingMarking(
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
        l.text('statusReadingMarkFailed'),
        error: true,
        failure: learningWorkflowController.failureDetail(error),
      );
    }
  }

  /// Opens the same-family clip aggregation for one L1 difficulty hint
  /// (Phase 3.9): listen goes through the slice playback window; practice is
  /// available for clips of the currently loaded track and seeds the
  /// practice window on that sentence.
  Future<void> _openL1Specialty(L1DiagnosisHint hint) async {
    if (!coreSessionController.state.isConnected || !mounted) return;
    final currentTrackId = subtitleController.primaryTrack?.id;
    L1SpecialtyView payload;
    try {
      payload = await learningWorkflowController.l1SpecialtyOccurrences(
        difficultyKind: hint.difficultyKind,
        language: settingsController.resolveLearningLanguage(
          subtitleController.primaryTrack?.language,
        ),
        trackId: currentTrackId,
      );
    } catch (error) {
      playerController.setStatus(
        l.text('statusSpecialtyClipsUnavailable'),
        error: true,
        failure: learningWorkflowController.failureDetail(error),
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
    viewModel: !coreSessionController.state.isConnected
        ? null
        : VocabularyViewModel(
            repository: coreRepositories.lexical,
            language: settingsController.resolveLearningLanguage(
              subtitleController.primaryTrack?.language,
            ),
          ),
    semanticSearchViewModel: !coreSessionController.state.isConnected
        ? null
        : SemanticSearchViewModel(coreRepositories.semanticSearch),
    playerController: playerController,
    playbackActions: playbackActions,
    practiceActions: practiceActions,
    huntingController: huntingController,
    auxiliaryAudio: auxiliaryAudioController,
    pauseBackgroundPlayback: _acquireAuxiliaryAudioFocus,
    initialEntryId: initialEntryId,
    openCrossModalReview: openCrossModalReview,
  );

  Future<void> _openReviewQueue() {
    final repository = coreSessionController.state.isConnected
        ? coreRepositories.review
        : null;
    return openReviewQueueFlow(
      context: context,
      controller: repository == null ? null : ReviewController(repository),
      resolver: repository == null
          ? null
          : OccurrenceMediaResolver(repository: repository),
      playerController: playerController,
      pauseBackgroundPlayback: _acquireAuxiliaryAudioFocus,
      startReviewShadowing: _startReviewShadowing,
      startDelayedRetelling: _startDelayedRetelling,
    );
  }

  Future<void> _openCoachDashboard() => openCoachDashboardFlow(
    context: context,
    controller: !coreSessionController.state.isConnected
        ? null
        : CoachDashboardController(coreRepositories.coachDashboard),
    playerController: playerController,
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
    if (!coreSessionController.state.isConnected ||
        mediaId == null ||
        startMs == null ||
        endMs == null) {
      return;
    }
    final resolution = await OccurrenceMediaResolver(
      repository: coreRepositories.review,
    ).resolveLinkedMedia(mediaId);
    if (resolution is! ResolvedOccurrenceMedia) {
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
    await practiceActions.startExternalShadowing(resolution.path, {
      'media_id': mediaId,
      'track_id': entry.item.source.trackId,
      'sentence_id': sentenceId,
      'sentence_text_snapshot': entry.item.promptSnapshot,
      'start_ms_snapshot': startMs,
      'end_ms_snapshot': endMs,
    });
  }

  Future<void> _startDelayedRetelling(ReviewQueueEntry entry) async {
    final mediaId = entry.item.source.mediaId;
    if (!coreSessionController.state.isConnected || mediaId == null) return;
    final resolution = await OccurrenceMediaResolver(
      repository: coreRepositories.review,
    ).resolveLinkedMedia(mediaId);
    if (resolution is! ResolvedOccurrenceMedia) {
      playerController.setStatus(
        l.text('statusRetellMediaUnavailable'),
        error: true,
      );
      return;
    }
    final path = resolution.path;
    if (playerController.mediaPath == null) {
      await mediaSession.openMediaPath(path);
      await adapter.pause();
    }
    if (!mounted) return;
    setState(() => _workbenchExpanded = true);
    _workbenchAnimController.forward();
    await speakingActions.openDelayedRetelling(
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

  Future<void> _openSubtitleResources() {
    final mediaId = playerController.mediaId;
    final mediaPath = playerController.mediaPath;
    final durationMs = playerController.duration.inMilliseconds;
    final canUseContentPackages =
        mediaId != null &&
        mediaPath != null &&
        mediaPath.isNotEmpty &&
        durationMs > 0;
    final ContentPackageJourneyViewModelFactory? packageFactory =
        canUseContentPackages
        ? () => ContentPackageJourneyViewModel(
            coreRepositories.contentPackage,
            (track) async {
              await mediaSession.usePrimarySubtitleTrack(
                track,
                nextStatus: l.text('contentPackageSelected'),
              );
              await resourceActions.loadSubtitleResources(updateStatus: false);
            },
            (timelineId) async {
              await coreRepositories.resource.activateWordTimeline(timelineId);
              final trackId = subtitleController.primaryTrack?.id;
              if (trackId != null) {
                try {
                  await resourceActions.loadTimelineResource(trackId);
                } catch (_) {
                  // Activation is durable Core state. A follow-up refresh is
                  // best-effort and must not report that activation failed.
                }
              }
            },
            mediaId: mediaId,
            mediaPath: mediaPath,
            mediaTitle: widget.pathHelper.basename(mediaPath),
            mediaKind: _contentPackageMediaKind(mediaPath),
            durationMs: durationMs,
          )
        : null;
    return openSubtitleResourcesFlow(
      context: context,
      backendAvailable: coreSessionController.state.isConnected,
      createColdStartViewModel: !coreSessionController.state.isConnected
          ? null
          : ({required trackId, required language}) =>
                ColdStartMarkingViewModel(
                  coreRepositories.coldStartMarking,
                  trackId: trackId,
                  language: language,
                ),
      playerController: playerController,
      subtitleController: subtitleController,
      learningController: learningController,
      resourceActions: resourceActions,
      mediaSession: mediaSession,
      onManualReviewTimeline: _openManualReviewTimeline,
      createContentPackageViewModel: packageFactory,
    );
  }

  String _contentPackageMediaKind(String? path) {
    final normalized = path?.toLowerCase() ?? '';
    return normalized.endsWith('.mp3') ||
            normalized.endsWith('.wav') ||
            normalized.endsWith('.m4a') ||
            normalized.endsWith('.flac') ||
            normalized.endsWith('.aac') ||
            normalized.endsWith('.ogg') ||
            normalized.endsWith('.opus')
        ? 'audio'
        : 'video';
  }

  void _openColdStartMarking() => openColdStartMarkingFlow(
    context: context,
    createViewModel: !coreSessionController.state.isConnected
        ? null
        : ({required trackId, required language}) => ColdStartMarkingViewModel(
            coreRepositories.coldStartMarking,
            trackId: trackId,
            language: language,
          ),
    playerController: playerController,
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
    viewModel: !coreSessionController.state.isConnected
        ? null
        : ExternalVocabularyImportViewModel(
            coreRepositories.externalVocabulary,
            language: settingsController.resolveLearningLanguage(
              subtitleController.primaryTrack?.language,
            ),
            onImported: vocabularyActions.loadWordEntries,
            fileService: const LocalExternalWordListFileService(),
          ),
    playerController: playerController,
  );

  Future<void> _refreshDiagnosis() async {
    final cue = subtitleController.currentPrimaryCue;
    if (cue == null || !coreSessionController.state.isConnected) {
      if (mounted) learningController.setDiagnosis(null);
      return;
    }
    await learningWorkflowController.refreshDiagnosis(
      cue: cue,
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

  @override
  void dispose() {
    unawaited(coreSessionController.shutdown());
    coreSessionController.removeListener(_onCoreSessionStateChanged);
    playerController.removeListener(_surfaceErrorStatus);
    playerController.removeListener(_trackExtensivePlayback);
    _workbenchAnimController.dispose();
    downloadController.dispose();
    mediaImportController.dispose();
    unawaited(_saveSettings());
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    transcriptController.dispose();
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
    immersiveMode.dispose();
    discoveryMode.dispose();
    discoveryViewModel.dispose();
    coreSessionController.dispose();
    super.dispose();
  }

  /// #25-A: closing or archiving the media while immersive would strand the
  /// user in a chrome-less fullscreen home — leave the immersive state (and
  /// system fullscreen) with the media.
  void _exitImmersiveWhenMediaCloses() {
    if (playerController.mediaPath == null && immersiveMode.immersive) {
      unawaited(immersiveMode.exit());
    }
  }

  @override
  Widget build(BuildContext context) {
    final coreState = coreSessionController.state;
    if (!coreState.isConnected) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (coreState.isConnecting) const ListenLoading(),
              const SizedBox(height: ListenSpacing.gap16),
              Text(status, textAlign: TextAlign.center),
              if (!coreState.isConnecting) ...[
                const SizedBox(height: ListenSpacing.gap12),
                FilledButton(
                  onPressed: () => unawaited(coreSessionController.connect()),
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
        // The transport's Space indicator follows the practice draft (#25).
        practiceController,
        // One handle for "which content channel is on the stage"; each
        // channel's own page state stays inside its host.
        contentChannels.selection,
        settingsController,
        downloadController,
        immersiveMode,
      ]),
      builder: (context, _) {
        // One definition of availability for every menu (#24): the AppBar
        // menus and the native macOS menu bar (#23) read this same object.
        final capabilities = AppBarCapabilities(
          hasMedia: playerController.mediaId != null,
          coreReady: coreState.isConnected,
        );
        // #25: keys live in the shortcut table (player_shortcuts.dart); this
        // map only supplies what each action *does*. The macOS Playback/Help
        // menus (#23) reuse it, so a table row has exactly one callback.
        final shortcutActions = <String, VoidCallback>{
          'playPause': practiceActions.togglePracticePlayback,
          'seekBack': () => unawaited(
            playbackActions.seekBy(-PlaybackActionsCoordinator.seekStep),
          ),
          'seekForward': () => unawaited(
            playbackActions.seekBy(PlaybackActionsCoordinator.seekStep),
          ),
          'volumeUp': () => unawaited(_keyboardVolumeBy(5)),
          'volumeDown': () => unawaited(_keyboardVolumeBy(-5)),
          'toggleMute': () => unawaited(playbackActions.toggleMute()),
          'speedDown': () => unawaited(_keyboardRateBy(-0.25)),
          'speedUp': () => unawaited(_keyboardRateBy(0.25)),
          'toggleFullscreen': () => unawaited(immersiveMode.toggle()),
          'exitFullscreen': () => unawaited(immersiveMode.exit()),
          'previousSentence': () =>
              unawaited(practiceActions.navigatePracticeSentence(-1)),
          'nextSentence': () =>
              unawaited(practiceActions.navigatePracticeSentence(1)),
          'loopSentence': () =>
              subtitleController.setLoopCue(!subtitleController.loopCue),
          'toggleSubtitles': () =>
              subtitleController.setVisible(!subtitleController.visible),
          'captureInbox': () => unawaited(inboxActions.captureListeningInbox()),
          'toggleExtensiveListening': () =>
              unawaited(_toggleExtensiveListening()),
          'hardInterrupt': () => unawaited(_hardInterruptListening()),
          'markUnknown': () =>
              vocabularyActions.markFirstWord('unknown_meaning'),
          'markKnownNotRecognized': () =>
              vocabularyActions.markFirstWord('known_not_recognized'),
          'markKnownRecognized': () =>
              vocabularyActions.markFirstWord('known_recognized'),
          'showCheatSheet': () => unawaited(showShortcutCheatSheet(context)),
        };
        return AppControllerScope(
          player: playerController,
          subtitle: subtitleController,
          learning: learningController,
          extensiveListening: extensiveListeningController,
          practice: practiceController,
          settings: settingsController,
          child: PlayerGlobalShortcuts(
            bindings: buildPlayerShortcutBindings(
              markKeysEnabled: settingsController.markKeysEnabled,
              actions: shortcutActions,
            ),
            child: Focus(
              autofocus: true,
              // The shell recedes (#46 signature action): while media plays
              // on the workbench and the pointer rests, app bar and
              // transport fade so only the content glows; movement or
              // chrome focus brings them back.
              child: _macosMenuHost(
                capabilities: capabilities,
                shortcutActions: shortcutActions,
                child: ShellRecede(
                  // Recede while media plays on the workbench — and always in the
                  // immersive state, where an idle pointer hides the controls
                  // even when playback is paused (#25-A player convention).
                  active:
                      (_workbenchExpanded && playerController.playing) ||
                      immersiveMode.immersive,
                  builder: (context, shellVisible) => Scaffold(
                    // Immersive drops the app bar entirely: the stage owns the
                    // whole screen, chrome returns only on exit.
                    appBar: immersiveMode.immersive
                        ? null
                        : ShellFadeAppBar(
                            visible: shellVisible,
                            child: PlayerAppBar(
                              // The shared availability object built above (#24);
                              // the macOS menu bar reads the same instance (#23).
                              capabilities: capabilities,
                              onOpenSubtitleResources: () =>
                                  unawaited(_openSubtitleResources()),
                              onOpenVocabulary: _openVocabulary,
                              onOpenReview: () => unawaited(_openReviewQueue()),
                              onOpenMedia: mediaSession.openMedia,
                              onOpenOnline: _openOnline,
                              onImportPrimarySubtitle: () => unawaited(
                                mediaSession.openSubtitle(secondary: false),
                              ),
                              onGeneratePrimarySubtitles: () => unawaited(
                                _generateSubtitles(secondary: false),
                              ),
                              onSearchPrimarySubtitles: () => unawaited(
                                _searchOpenSubtitles(secondary: false),
                              ),
                              onImportSecondarySubtitle: () => unawaited(
                                mediaSession.openSubtitle(secondary: true),
                              ),
                              onGenerateSecondarySubtitles: () => unawaited(
                                _generateSubtitles(secondary: true),
                              ),
                              onSearchSecondarySubtitles: () => unawaited(
                                _searchOpenSubtitles(secondary: true),
                              ),
                              onImportEmbeddedSubtitle: () =>
                                  unawaited(_importEmbeddedSubtitle()),
                              onOpenSettings: () => unawaited(_openSettings()),
                              onExportLogs: () => unawaited(_exportLogs()),
                              onExportVocabulary: () =>
                                  unawaited(playbackActions.exportVocabulary()),
                              onImportVocabulary: () =>
                                  unawaited(playbackActions.importVocabulary()),
                              onImportWordList: () =>
                                  unawaited(_importWordList()),
                              onArchiveMedia: () => unawaited(
                                playbackActions.archiveCurrentMedia(),
                              ),
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
                    body: immersiveMode.immersive
                        ? _immersiveBody(shellVisible)
                        : DesktopDropSurface(
                            onDropped: subtitleSources.handleDrop,
                            child: Column(
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      ValueListenableBuilder<bool>(
                                        valueListenable: discoveryMode,
                                        builder: (context, showDiscovery, _) {
                                          if (showDiscovery) {
                                            return DiscoveryHome(
                                              viewModel: discoveryViewModel,
                                              onOpenMedia:
                                                  mediaSession.openMedia,
                                              onOpenSettings: () =>
                                                  unawaited(_openSettings()),
                                              onOpenClassicHome: () =>
                                                  discoveryMode.value = false,
                                              onPlayMedia:
                                                  mediaSession.openMediaPath,
                                            );
                                          }
                                          return Stack(
                                            children: [
                                              ListeningHome(
                                                onOpenMedia:
                                                    mediaSession.openMedia,
                                                onOpenOnline: _openOnline,
                                                onContinue: () {
                                                  if (_workbenchExpanded ||
                                                      playerController
                                                              .mediaPath !=
                                                          null) {
                                                    _expandWorkbench();
                                                  } else {
                                                    unawaited(
                                                      mediaLibraryActions
                                                          .continueRecentMedia(),
                                                    );
                                                  }
                                                },
                                                onOpenSubtitleResources: () =>
                                                    unawaited(
                                                      _openSubtitleResources(),
                                                    ),
                                                onOpenVocabulary:
                                                    _openVocabulary,
                                                onOpenPersonalExpressions: () =>
                                                    unawaited(
                                                      _openPersonalExpression(),
                                                    ),
                                                onOpenConversation: () =>
                                                    unawaited(
                                                      _openFreeConversation(),
                                                    ),
                                                onOpenReview: () => unawaited(
                                                  _openReviewQueue(),
                                                ),
                                                onOpenCoach: () => unawaited(
                                                  _openCoachDashboard(),
                                                ),
                                                onOpenSettings: () =>
                                                    unawaited(_openSettings()),
                                                mediaLibrary:
                                                    mediaLibraryActions
                                                        .mediaLibrary,
                                                familiarSupplyEnabled:
                                                    settingsController
                                                        .familiarMaterialSuggestions,
                                                onOpenLibraryEntry: (entry) =>
                                                    unawaited(
                                                      mediaLibraryActions
                                                          .openLibraryEntry(
                                                            entry,
                                                          ),
                                                    ),
                                                onStartExtensiveEntry:
                                                    (entry) => unawaited(
                                                      mediaLibraryActions
                                                          .startExtensiveFromLibrary(
                                                            entry,
                                                          ),
                                                    ),
                                                onStartIntensiveEntry:
                                                    (entry) => unawaited(
                                                      mediaLibraryActions
                                                          .startIntensiveFromLibrary(
                                                            entry,
                                                          ),
                                                    ),
                                                onSetLibraryIntent:
                                                    (
                                                      entry,
                                                      intent,
                                                    ) => unawaited(
                                                      mediaLibraryActions
                                                          .setLibraryTriageIntent(
                                                            entry,
                                                            intent,
                                                          ),
                                                    ),
                                                onToggleFamiliarSupply:
                                                    (enabled) => unawaited(
                                                      mediaLibraryActions
                                                          .toggleFamiliarSupply(
                                                            enabled,
                                                          ),
                                                    ),
                                                recentMediaTitle:
                                                    settingsController
                                                        .lastMediaTitle
                                                        .isEmpty
                                                    ? null
                                                    : settingsController
                                                          .lastMediaTitle,
                                                recentMediaPath:
                                                    settingsController
                                                        .lastMediaPath
                                                        .isEmpty
                                                    ? null
                                                    : settingsController
                                                          .lastMediaPath,
                                                recentPosition: Duration(
                                                  milliseconds:
                                                      settingsController
                                                          .lastMediaPositionMs,
                                                ),
                                                recentDuration: Duration(
                                                  milliseconds:
                                                      settingsController
                                                          .lastMediaDurationMs,
                                                ),
                                                recentSubtitleCount:
                                                    settingsController
                                                        .lastMediaSubtitleCount,
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
                                                    mediaLibraryActions
                                                        .savedVocabulary !=
                                                    null,
                                                listeningInboxCount:
                                                    extensiveListeningController
                                                        .activeItemCount,
                                                coreStatusText:
                                                    playerController
                                                        .statusIsPlayback
                                                    ? ''
                                                    : playerController.status,
                                              ),
                                              if (playerController.mediaPath !=
                                                  null)
                                                SlideTransition(
                                                  position:
                                                      _workbenchSlideAnimation,
                                                  child: MediaWorkbench(
                                                    mediaTitle: widget
                                                        .pathHelper
                                                        .basename(
                                                          playerController
                                                              .mediaPath!,
                                                        ),
                                                    playerStage: _playerStage(),
                                                    learningPanel: _sidePanel(),
                                                    selectedChannel:
                                                        contentChannels
                                                            .selected,
                                                    channelAvailability: {
                                                      ContentChannel.listening:
                                                          const ContentChannelAvailability.available(),
                                                      ContentChannel.reading:
                                                          subtitleController
                                                                  .primaryTrack ==
                                                              null
                                                          ? ContentChannelAvailability.unavailable(
                                                              l.text(
                                                                'channelNeedsTranscript',
                                                              ),
                                                            )
                                                          : const ContentChannelAvailability.available(),
                                                      ContentChannel.speaking:
                                                          subtitleController
                                                                  .primaryTrack ==
                                                              null
                                                          ? ContentChannelAvailability.unavailable(
                                                              l.text(
                                                                'channelNeedsTranscript',
                                                              ),
                                                            )
                                                          : !widget
                                                                .platformCapabilities
                                                                .isMacOS
                                                          ? ContentChannelAvailability.unavailable(
                                                              l.text(
                                                                'channelUnavailable',
                                                              ),
                                                            )
                                                          : const ContentChannelAvailability.available(),
                                                      ContentChannel.writing:
                                                          subtitleController
                                                                  .primaryTrack ==
                                                              null
                                                          ? ContentChannelAvailability.unavailable(
                                                              l.text(
                                                                'channelNeedsTranscript',
                                                              ),
                                                            )
                                                          : const ContentChannelAvailability.available(),
                                                    },
                                                    onChannelSelected:
                                                        (channel) => unawaited(
                                                          contentChannels
                                                              .select(channel),
                                                        ),
                                                    immersiveStage: switch (contentChannels
                                                        .selected) {
                                                      ContentChannel.writing =>
                                                        WritingChannelHost(
                                                          writingChannel:
                                                              writingChannel,
                                                          writingTaskController:
                                                              writingTaskController,
                                                        ),
                                                      ContentChannel.speaking =>
                                                        SpeakingChannelHost(
                                                          speakingChannel:
                                                              speakingChannel,
                                                          speakingActions:
                                                              speakingActions,
                                                          speakingTaskController:
                                                              speakingTaskController,
                                                          readingTaskController:
                                                              readingTaskController,
                                                        ),
                                                      ContentChannel.reading => ReadingChannelHost(
                                                        readingChannel:
                                                            readingChannel,
                                                        readingController:
                                                            readingController,
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
                                                        playerController:
                                                            playerController,
                                                        vocabularyActions:
                                                            vocabularyActions,
                                                        onSaveSentencePattern:
                                                            (source) =>
                                                                _openPersonalExpression(
                                                                  source:
                                                                      source,
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
                                                            unawaited(
                                                              _correctCurrentLemma(),
                                                            ),
                                                      ),
                                                      ContentChannel
                                                          .listening =>
                                                        null,
                                                    },
                                                    mediaFraction:
                                                        settingsController
                                                            .workbenchMediaFraction,
                                                    onMediaFractionChanged:
                                                        _setWorkbenchMediaFraction,
                                                    onCollapse:
                                                        _collapseWorkbench,
                                                  ),
                                                ),
                                              Positioned(
                                                right: 16,
                                                bottom: 16,
                                                child: ActionChip(
                                                  avatar: const Icon(
                                                    Icons.arrow_back,
                                                    size:
                                                        ListenIconSize.control,
                                                  ),
                                                  label: Text(
                                                    l.text(
                                                      'discoveryBackToResources',
                                                    ),
                                                  ),
                                                  onPressed: () =>
                                                      discoveryMode.value =
                                                          true,
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                      PlayerOverlays(
                                        practiceController: practiceController,
                                        slicePlayerController:
                                            slicePlayerController,
                                        huntingSessionController:
                                            huntingSessionController,
                                        subtitleController: subtitleController,
                                        playerController: playerController,
                                        practiceActions: practiceActions,
                                        huntingActions: huntingActions,
                                        onCloseSlicePlayback:
                                            _closeSlicePlayback,
                                      ),
                                    ],
                                  ),
                                ),
                                if (downloadController.snapshot != null)
                                  _downloadStatusBar(
                                    downloadController.snapshot!,
                                  ),
                                ShellFade(
                                  visible: shellVisible,
                                  child: _controls(),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// #23: mounts the native macOS menu bar around the shell; other platforms
  /// pass through. Availability and actions are the same objects the AppBar
  /// and `CallbackShortcuts` consume — the menu is a surface, not a source.
  Widget _macosMenuHost({
    required AppBarCapabilities capabilities,
    required Map<String, VoidCallback> shortcutActions,
    required Widget child,
  }) {
    if (!widget.platformCapabilities.isMacOS) return child;
    return MacosMenuBar(
      capabilities: capabilities,
      shortcutActions: shortcutActions,
      onOpenSettings: () => unawaited(_openSettings()),
      onOpenMedia: mediaSession.openMedia,
      onOpenOnline: _openOnline,
      onImportPrimarySubtitle: () =>
          unawaited(mediaSession.openSubtitle(secondary: false)),
      onImportSecondarySubtitle: () =>
          unawaited(mediaSession.openSubtitle(secondary: true)),
      onImportEmbeddedSubtitle: () => unawaited(_importEmbeddedSubtitle()),
      onArchiveMedia: () => unawaited(playbackActions.archiveCurrentMedia()),
      onOpenSubtitleResources: () => unawaited(_openSubtitleResources()),
      onOpenVocabulary: _openVocabulary,
      onOpenReview: () => unawaited(_openReviewQueue()),
      onOpenCoach: () => unawaited(_openCoachDashboard()),
      onOpenTranscriptionCenter: () => unawaited(_openTranscriptionCenter()),
      onOpenPhoneticAnalysisCenter: () =>
          unawaited(_openPhoneticAnalysisCenter()),
      child: child,
    );
  }

  /// #25-A: the immersive body — the stage full-bleed, the transport as an
  /// auto-hiding overlay pinned to the bottom, the pointer hidden while the
  /// chrome is away. This path deliberately skips the workbench split, its
  /// header and side panel — and with them the `ListenBreakpoints` narrow
  /// -window degradations, which have no business on a fullscreen stage.
  Widget _immersiveBody(bool shellVisible) => MouseRegion(
    cursor: shellVisible ? MouseCursor.defer : SystemMouseCursors.none,
    child: Stack(
      fit: StackFit.expand,
      children: [
        _playerStage(),
        PlayerOverlays(
          practiceController: practiceController,
          slicePlayerController: slicePlayerController,
          huntingSessionController: huntingSessionController,
          subtitleController: subtitleController,
          playerController: playerController,
          practiceActions: practiceActions,
          huntingActions: huntingActions,
          onCloseSlicePlayback: _closeSlicePlayback,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ShellFade(visible: shellVisible, child: _controls()),
        ),
      ],
    ),
  );

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
    onToggleFullscreen: () => unawaited(immersiveMode.toggle()),
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
    spaceTargetsPractice: practiceController.draft?.referenceMediaPath != null,
    isCompact:
        playerController.mediaPath != null &&
        !_workbenchExpanded &&
        !immersiveMode.immersive,
    mediaTitle: playerController.mediaPath == null
        ? null
        : widget.pathHelper.basename(playerController.mediaPath!),
    onExpand: _expandWorkbench,
    isFullscreen: immersiveMode.immersive,
    onToggleFullscreen: playerController.mediaPath == null
        ? null
        : () => unawaited(immersiveMode.toggle()),
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
