import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'localization.dart';
import 'player_adapter.dart';
import 'settings.dart';
import 'theme/listen_theme.dart';

import 'controllers/app_controllers.dart';
import 'controllers/auxiliary_audio_controller.dart';
import 'controllers/backend_event_coordinator.dart';
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
import 'controllers/reading_controller.dart';
import 'controllers/reading_diff_controller.dart';
import 'controllers/reading_task_controller.dart';
import 'controllers/realtime_conversation_controller.dart';
import 'controllers/resource_actions_coordinator.dart';
import 'controllers/speech_enhancement_workflow_controller.dart';
import 'controllers/speaking_actions_coordinator.dart';
import 'controllers/speaking_task_controller.dart';
import 'controllers/writing_task_controller.dart';
import 'controllers/subtitle_controller.dart';
import 'controllers/subtitle_sources_coordinator.dart';
import 'controllers/vocabulary_actions_coordinator.dart';
import 'controllers/settings_controller.dart';
import 'controllers/slice_player_controller.dart';
import 'models/capability_readiness.dart';
import 'models/practice.dart';
import 'models/personal_expression.dart';
import 'models/task_status.dart';
import 'models/reading.dart';
import 'models/timeline.dart';
import 'models/types.dart';
import 'services/api_service.dart';
import 'services/external_tools.dart';
import 'widgets/panels/intensive_practice_window.dart';
import 'widgets/panels/l1_specialty_dialog.dart';
import 'widgets/panels/hunting_prompt_card.dart';
import 'widgets/panels/listening_check_panel.dart';
import 'widgets/panels/reading_diff_panel.dart';
import 'widgets/panels/reading_task_studio.dart';
import 'widgets/panels/reading_view.dart';
import 'widgets/panels/reading_word_inspector.dart';
import 'widgets/panels/realtime_conversation_panel.dart';
import 'widgets/panels/slice_playback_window.dart';
import 'widgets/panels/speaking_task_studio.dart';
import 'widgets/panels/writing_task_studio.dart';
import 'widgets/player/download_status_bar.dart';
import 'widgets/app_bar/player_app_bar.dart';
import 'widgets/flows/learning_flows.dart';
import 'widgets/flows/reading_flows.dart';
import 'widgets/flows/speaking_flows.dart';
import 'widgets/flows/writing_flows.dart';
import 'widgets/flows/manual_review_flow.dart';
import 'widgets/flows/media_import_flows.dart';
import 'widgets/flows/subtitle_resource_flows.dart';
import 'widgets/layout/playback_bar.dart';
import 'widgets/layout/media_workbench.dart';
import 'widgets/layout/content_channel_switcher.dart';
import 'widgets/layout/player_stage.dart';
import 'widgets/layout/side_panel.dart';
import 'widgets/home/listening_home.dart';
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

class ListenApp extends StatelessWidget {
  const ListenApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: appLanguage,
    builder: (context, language, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'listen',
      locale: language == 'system' ? null : Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ListenTheme.light(),
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
  ReadingTaskSource? _readingTaskStudioSource;
  ReadingTaskSource? _readingDiffSource;
  ReadingParagraph? _readingDiffParagraph;
  bool _readingWordInspectorOpen = false;
  // Non-null while the listening-retell surface replaces the reading view.
  ReadingTaskSource? _listeningCheckSource;
  int _listeningPlayCount = 0;
  ReadingTaskSource? _speakingL1CheckSource;
  SentencePatternAssetView? _activePersonalPattern;
  WritingTaskSource? _writingTaskStudioSource;
  String _writingKind = WritingTaskController.summaryKind;
  int _writingPlayCount = 0;
  int _speakingL1PlayCount = 0;
  bool _realtimeConversationOpen = false;
  Timer? _readingSaveTimer;
  String? _lastSavedReadingAnchor;
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

  @override
  void initState() {
    super.initState();
    readingController.addListener(_scheduleReadingPositionSave);
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
          if (_speakingL1CheckSource != null) _closeSpeakingL1Check();
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
    inboxActions.bind(getApi: () => api, isMounted: () => mounted);
    practiceActions.bind(
      getApi: () => api,
      isMounted: () => mounted,
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
    subtitleSources.bind(
      getApi: () => api,
      isMounted: () => mounted,
      showSnackBar: _showSnackBar,
      setTaskStatus: _setTaskStatus,
      openMediaPath: mediaSession.openMediaPath,
      openSubtitlePath: mediaSession.openSubtitlePath,
    );
    unawaited(_connectApi());
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
    await adapter.setRate(playerController.rate);
    await adapter.setVolume(playerController.volume);
  }

  Future<void> _saveSettings() => settingsController.update(
    AppSettings(
      rate: playerController.rate,
      volume: playerController.volume,
      primarySubtitleOffsetMs:
          subtitleController.primarySubtitleOffset.inMilliseconds,
      secondarySubtitleOffsetMs:
          subtitleController.secondarySubtitleOffset.inMilliseconds,
      subtitlesVisible: subtitleController.visible,
      secondarySubtitlesVisible: subtitleController.secondaryVisible,
      statusStylesVisible: subtitleController.statusStylesVisible,
      primaryFontSize: subtitleController.primaryFontSize,
      secondaryFontSize: subtitleController.secondaryFontSize,
      primaryFontFamily: subtitleController.primaryFontFamily,
      secondaryFontFamily: subtitleController.secondaryFontFamily,
      subtitlePreset: subtitleController.preset,
      language: settingsController.language,
      subtitlePositionX: subtitleController.positionX,
      subtitlePositionY: subtitleController.positionY,
      subtitleBackgroundOpacity: subtitleController.backgroundOpacity,
      primaryColor: settingsController.primaryColor.toARGB32(),
      secondaryColor: settingsController.secondaryColor.toARGB32(),
      transcriptWidth: settingsController.transcriptWidth,
      workbenchMediaFraction: settingsController.workbenchMediaFraction,
      ffmpegPath: settingsController.ffmpegPath,
      ffprobePath: settingsController.ffprobePath,
      ytDlpPath: settingsController.ytDlpPath,
      transcriptionQuality: settingsController.transcriptionQuality,
      transcriptionLanguage: settingsController.transcriptionLanguage,
      transcriptionDestination: settingsController.transcriptionDestination,
      openSubtitlesApiKey: settingsController.openSubtitlesApiKey,
      wordSyncVisible: settingsController.wordSyncVisible,
      groupingMode: settingsController.groupingMode,
      chunkDisplayStyle: settingsController.chunkDisplayStyle,
      highlightCurrentChunk: settingsController.highlightCurrentChunk,
      chunkHighlightStyle: settingsController.chunkHighlightStyle,
      wordHighlightStyle: settingsController.wordHighlightStyle,
      wordAnimationIntensity: settingsController.wordAnimationIntensity,
      ruleHintsLevel: settingsController.ruleHintsLevel,
      phoneticProviderId: settingsController.settings.phoneticProviderId,
      phoneticModelId: settingsController.settings.phoneticModelId,
      phoneticAnalysisPreference: settingsController.phoneticAnalysisPreference,
      phonemeRibbonVisible: settingsController.phonemeRibbonVisible,
      soundPatternRibbonVisible: settingsController.soundPatternRibbonVisible,
      soundPatternDisplayMode: settingsController.soundPatternDisplayMode,
      phonemeRibbonStyle: settingsController.phonemeRibbonStyle,
      learningLanguage: settingsController.learningLanguage,
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
    if (mounted) {
      playerController.setStatus('Starting local core...');
      setState(() {
        connectingApi = true;
      });
    }
    try {
      final value = await LocalApi.connect();
      if (!mounted) return value.close();
      playerController.setStatus('Local core connected');
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
        playerController.setStatus('Core unavailable: $error');
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
    _activePersonalPattern = pattern;
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
      closeReading: _closeReading,
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

  Future<void> _showCurrentPhraseCandidates() =>
      showCurrentPhraseCandidatesFlow(
        context: context,
        api: api,
        playerController: playerController,
        subtitleController: subtitleController,
        settingsController: settingsController,
      );

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

  Future<void> _searchOpenSubtitles({bool? secondary}) =>
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
      playerController.setStatus('No core log is available yet');
      return;
    }
    final location = await getSaveLocation(suggestedName: 'listen-core.log');
    if (location == null) return;
    await File(source).copy(location.path);
    playerController.setStatus('Exported diagnostics to ${location.path}');
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

  /// Enters the reading posture over the current primary track. Playback is
  /// paused (reading has its own rhythm); the position is untouched so
  /// closing returns to the exact playback context.
  Future<void> _openReading() async {
    final track = subtitleController.primaryTrack;
    if (track == null) return;
    await adapter.pause();
    // Restore the saved reading cursor; a fetch failure just starts from the
    // top (the cursor is a convenience, never a gate).
    String? resumeAnchor;
    try {
      final saved = await api?.readingPosition(track.id);
      resumeAnchor = saved?.anchorCueId;
    } catch (_) {}
    _lastSavedReadingAnchor = resumeAnchor;
    readingController.open(
      track,
      secondaryTrack: subtitleController.secondaryTrack,
      resumeAnchorCueId: resumeAnchor,
    );
  }

  Future<void> _closeReading() async {
    if (_listeningCheckSource != null) _closeListeningCheck();
    if (_readingTaskStudioSource != null) _closeReadingTaskStudio();
    if (_readingDiffSource != null) _closeReadingDiff();
    _readingSaveTimer?.cancel();
    unawaited(_saveReadingPosition());
    readingController.close();
    if (mounted) setState(() => _readingWordInspectorOpen = false);
  }

  Future<void> _openReadingWord(SubtitleToken token, Cue cue) async {
    if (!_readingWordInspectorOpen) {
      setState(() => _readingWordInspectorOpen = true);
    }
    await vocabularyActions.openWord(token, cue);
  }

  /// Debounced cursor write: paragraph taps arrive in bursts while the user
  /// settles; only the resting anchor is worth a backend round trip.
  void _scheduleReadingPositionSave() {
    final state = readingController.state;
    if (!state.open ||
        state.anchorCueId == null ||
        state.anchorCueId == _lastSavedReadingAnchor) {
      return;
    }
    _readingSaveTimer?.cancel();
    _readingSaveTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(_saveReadingPosition());
    });
  }

  Future<void> _saveReadingPosition() async {
    final state = readingController.state;
    final trackId = state.trackId;
    final anchor = state.anchorCueId;
    if (trackId == null || anchor == null) return;
    if (anchor == _lastSavedReadingAnchor) return;
    try {
      await api?.saveReadingPosition(
        trackId: trackId,
        mediaId: subtitleController.primaryTrack?.mediaId,
        anchorCueId: anchor,
        paragraphIndex: state.anchorParagraphIndex,
      );
      _lastSavedReadingAnchor = anchor;
    } catch (_) {
      // Cursor writes are best-effort; the next tap retries.
    }
  }

  /// Builds the shared segment descriptor for reading/listening tasks and
  /// the diff card. The response language defaults to the learner's L1
  /// (comprehension is best demonstrated in the language they think in),
  /// falling back to the track language when L1 was never set.
  Future<ReadingTaskSource?> _readingTaskSource(
    ReadingParagraph paragraph,
  ) async {
    final track = subtitleController.primaryTrack;
    final service = api;
    if (track == null || service == null) return null;
    final cursor = subtitleController.primaryCursor;
    final sourceLanguage = settingsController.resolveLearningLanguage(
      track.language,
    );
    var responseLanguage = sourceLanguage;
    try {
      final profile = await service.learnerProfile();
      final l1 = profile.l1Language;
      if (l1 != null && l1.isNotEmpty) responseLanguage = l1;
    } catch (_) {}
    final anchor = Cue(
      id: paragraph.anchorCueId,
      index: 0,
      start: paragraph.start,
      end: paragraph.end,
      text: '',
      tokens: const [],
    );
    return ReadingTaskSource(
      anchorCueId: paragraph.anchorCueId,
      mediaId: track.mediaId ?? playerController.mediaId,
      trackId: track.id,
      startMs: cursor.mediaStart(anchor).inMilliseconds,
      endMs: cursor.mediaEnd(anchor).inMilliseconds,
      sourceLanguage: sourceLanguage,
      responseLanguage: responseLanguage,
      transcriptSnapshot: paragraph.sentences
          .map((sentence) => sentence.text)
          .join(' '),
    );
  }

  /// Opens the paragraph-task flow (Slice 3): manual rubric + typed answer +
  /// per-point self-assessment through the 3.11 semantic fact family.
  Future<void> _openReadingTask(ReadingParagraph paragraph) async {
    final source = await _readingTaskSource(paragraph);
    final service = api;
    if (source == null || service == null || !mounted) return;
    await adapter.pause();
    setState(() => _readingTaskStudioSource = source);
    unawaited(
      readingTaskController.openTask(
        service,
        source: source,
        templatePoints: readingTaskTemplate(l),
      ),
    );
  }

  void _closeReadingTaskStudio() {
    readingTaskController.closeTask();
    setState(() => _readingTaskStudioSource = null);
  }

  Future<void> _selectContentChannel(ContentChannel channel) async {
    if (channel != ContentChannel.speaking && _realtimeConversationOpen) {
      await realtimeConversationController.cancel();
      if (mounted) setState(() => _realtimeConversationOpen = false);
    }
    switch (channel) {
      case ContentChannel.listening:
        if (_writingTaskStudioSource != null) await _closeWritingTaskStudio();
        if (_speakingL1CheckSource != null) _closeSpeakingL1Check();
        if (speakingActions.isOpen) await speakingActions.close(api);
        await _closeReading();
        return;
      case ContentChannel.reading:
        if (_writingTaskStudioSource != null) await _closeWritingTaskStudio();
        if (_speakingL1CheckSource != null) _closeSpeakingL1Check();
        if (speakingActions.isOpen) await speakingActions.close(api);
        await _openReading();
        return;
      case ContentChannel.speaking:
        if (_writingTaskStudioSource != null) await _closeWritingTaskStudio();
        final service = api;
        if (service == null || !Platform.isMacOS) return;
        await speakingActions.openRetelling(
          service,
          fixedRubricPoints: listeningRetellTemplate(l),
          closeReading: _closeReading,
        );
        return;
      case ContentChannel.writing:
        await _openWritingTask(_writingKind);
        return;
    }
  }

  void _openRealtimeConversation() {
    final source = speakingTaskController.state.source;
    final modelId = speakingTaskController.state.asrModelId;
    if (source == null || modelId == null) return;
    setState(() => _realtimeConversationOpen = true);
  }

  Future<void> _closeRealtimeConversation() async {
    await realtimeConversationController.cancel();
    if (mounted) setState(() => _realtimeConversationOpen = false);
  }

  Future<void> _openWritingTask(String kind) async {
    final service = api;
    final track = subtitleController.primaryTrack;
    if (service == null || track == null) return;
    final paragraphs = deriveReadingParagraphs(
      track.cues,
    ).where((paragraph) => !paragraph.nonSpeech).toList(growable: false);
    if (paragraphs.isEmpty) return;
    final currentCueId = subtitleController.currentPrimaryCue?.id;
    final paragraph = paragraphs.firstWhere(
      (candidate) => candidate.sentences.any(
        (sentence) => sentence.cues.any((cue) => cue.id == currentCueId),
      ),
      orElse: () => paragraphs.first,
    );
    final cursor = subtitleController.primaryCursor;
    final anchor = Cue(
      id: paragraph.anchorCueId,
      index: 0,
      start: paragraph.start,
      end: paragraph.end,
      text: '',
      tokens: const [],
    );
    final language = settingsController.resolveLearningLanguage(track.language);
    final source = WritingTaskSource(
      anchorCueId: paragraph.anchorCueId,
      mediaId: track.mediaId ?? playerController.mediaId,
      trackId: track.id,
      startMs: cursor.mediaStart(anchor).inMilliseconds,
      endMs: cursor.mediaEnd(anchor).inMilliseconds,
      sourceLanguage: language,
      responseLanguage: language,
      transcriptSnapshot: paragraph.sentences
          .map((sentence) => sentence.text)
          .join(' '),
    );
    await _closeSlicePlayback();
    await adapter.pause();
    if (_speakingL1CheckSource != null) _closeSpeakingL1Check();
    if (speakingActions.isOpen) await speakingActions.close(api);
    await _closeReading();
    if (!mounted) return;
    setState(() {
      _writingKind = kind;
      _writingPlayCount = 0;
      _writingTaskStudioSource = source;
    });
    unawaited(
      writingTaskController.openTask(
        service,
        source: source,
        kind: kind,
        promptSnapshot: writingPrompt(l, kind),
        fixedRubricPoints: writingTaskTemplate(l),
      ),
    );
  }

  Future<void> _closeWritingTaskStudio() async {
    await auxiliaryAudioController.stop();
    await _closeSlicePlayback();
    writingTaskController.closeTask();
    if (mounted) setState(() => _writingTaskStudioSource = null);
  }

  Future<void> _speakWritingText(String text) async {
    final service = api;
    final source = _writingTaskStudioSource;
    if (service == null || source == null || text.trim().isEmpty) return;
    final asset = await auxiliaryAudioController.speak(
      service,
      text: text,
      language: source.responseLanguage,
      purpose: 'writing_readback',
      acquireAudioFocus: () async {
        await adapter.pause();
        await recordingAdapter.pause();
        await slicePlayerController.pause();
      },
    );
    if (asset == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).text('ttsUnavailable')),
        ),
      );
    }
  }

  void _playWritingSource() {
    final source = _writingTaskStudioSource;
    if (source == null) return;
    setState(() => _writingPlayCount++);
    unawaited(
      _openSlicePlayback(
        currentMediaSliceOccurrence(
          mediaId: source.mediaId,
          trackId: source.trackId,
          sentenceId: source.anchorCueId,
          textSnapshot: '',
          startMs: source.startMs,
          endMs: source.endMs,
          mediaFingerprint: playerController.mediaFingerprint,
        ),
      ),
    );
  }

  /// Opens the read-listen pairing card (Slice 4): both sides' facts over
  /// the same segment, reduced independently — never a causal claim.
  Future<void> _openReadingDiff(ReadingParagraph paragraph) async {
    final source = await _readingTaskSource(paragraph);
    final service = api;
    if (source == null || service == null || !mounted) return;
    setState(() {
      _readingDiffSource = source;
      _readingDiffParagraph = paragraph;
    });
    unawaited(readingDiffController.loadDiff(service, source));
  }

  void _closeReadingDiff() {
    setState(() {
      _readingDiffSource = null;
      _readingDiffParagraph = null;
    });
  }

  /// Swaps the reading view for the listening-retell surface. The reading
  /// rubric's points seed the retell template when they exist, so both
  /// sides interrogate the same content; otherwise the generic template
  /// applies. Text hidden by construction: the panel replaces the view.
  void _openListeningCheck(
    ReadingParagraph paragraph,
    ReadingTaskSource source,
  ) {
    final service = api;
    if (service == null) return;
    final l = AppLocalizations.of(context);
    final readingPoints = readingDiffController.state.read.rubric?.points;
    final template = readingPoints == null || readingPoints.isEmpty
        ? listeningRetellTemplate(l)
        : readingPoints;
    setState(() {
      _listeningCheckSource = source;
      _listeningPlayCount = 0;
    });
    unawaited(
      readingTaskController.openTask(
        service,
        source: source,
        templatePoints: template,
        purpose: ReadingTaskController.listeningPurpose,
      ),
    );
  }

  void _closeListeningCheck() {
    readingTaskController.closeTask();
    setState(() => _listeningCheckSource = null);
  }

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
      playerController.setStatus('$error');
    }
  }

  /// Replays a reading range through the slice window (3.5.7) so the primary
  /// playback position never moves while reading.
  Future<void> _playReadingRange(
    Duration start,
    Duration end,
    String anchorCueId,
    String textSnapshot,
  ) async {
    final track = subtitleController.primaryTrack;
    if (track == null) return;
    final cursor = subtitleController.primaryCursor;
    final anchor = Cue(
      id: anchorCueId,
      index: 0,
      start: start,
      end: end,
      text: textSnapshot,
      tokens: const [],
    );
    await _openSlicePlayback(
      currentMediaSliceOccurrence(
        mediaId: track.mediaId ?? playerController.mediaId,
        trackId: track.id,
        sentenceId: anchorCueId,
        textSnapshot: textSnapshot,
        startMs: cursor.mediaStart(anchor).inMilliseconds,
        endMs: cursor.mediaEnd(anchor).inMilliseconds,
        mediaFingerprint: playerController.mediaFingerprint,
      ),
    );
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
      playerController.setStatus('Specialty clips unavailable: $error');
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
        playerController.setStatus('Extensive listening started');
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
    final report = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('finishExtensiveListening')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.text('comprehensionReportPrompt')),
            if (huntingSummary != null) ...[
              const SizedBox(height: 12),
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
      playerController.setStatus('Extensive listening finished');
    }
  }

  Future<void> _hardInterruptListening() async {
    if (playerController.playing) await adapter.playOrPause();
    await inboxActions.captureListeningInbox();
    learningController.selectSidePanel(3);
    await _refreshDiagnosis();
    if (mounted) playerController.setStatus('Paused for quick listening check');
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
        'Review source media is unavailable for shadowing',
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
        'Delayed retelling source media is unavailable.',
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
      closeReading: _closeReading,
    );
  }

  Future<void> _closeSpeakingSurface() async {
    if (_speakingL1CheckSource != null) _closeSpeakingL1Check();
    final returnToReview = speakingActions.source?.recall == 'delayed';
    final personalPattern = _activePersonalPattern;
    final personalState = speakingTaskController.state;
    if (personalPattern != null &&
        personalState.phase == 'done' &&
        personalState.recording != null &&
        personalState.correctedTranscript.trim().isNotEmpty) {
      final verdicts =
          personalState.rubric?.points
              .map((point) => personalState.effectiveVerdict(point.pointId))
              .whereType<String>()
              .toList(growable: false) ??
          const <String>[];
      final assessment = verdicts.any((value) => value == 'missing')
          ? 'needs_work'
          : verdicts.isNotEmpty && verdicts.every((value) => value == 'covered')
          ? 'expressed'
          : 'partly_expressed';
      try {
        await api?.recordPersonalExpressionAttempt(
          patternId: personalPattern.id,
          patternVersionId: personalPattern.currentVersion.id,
          channel: 'speaking',
          assistance: 'no_text',
          responseText: personalState.correctedTranscript.trim(),
          rawTranscript: personalState.rawTranscript,
          recordingAssetId: personalState.recording!.id,
          selfAssessment: assessment,
        );
      } catch (error) {
        playerController.setStatus(
          'Could not save personal expression history: $error',
        );
      }
    }
    _activePersonalPattern = null;
    await speakingActions.close(api);
    if (returnToReview && mounted) {
      unawaited(_openReviewQueue());
    } else if (personalPattern != null && mounted) {
      unawaited(_openPersonalExpression());
    }
  }

  Future<void> _openSpeakingL1Check() async {
    final service = api;
    final speakingSource = speakingActions.source;
    final rubric = speakingTaskController.state.rubric;
    if (service == null || speakingSource == null || rubric == null) return;
    final profile = await service.learnerProfile();
    final l1 = profile.l1Language;
    if (l1 == null || l1.trim().isEmpty) {
      playerController.setStatus(
        'Set your L1 language before using the meaning check.',
      );
      return;
    }
    final source = ReadingTaskSource(
      anchorCueId: speakingSource.anchorCueId,
      mediaId: speakingSource.mediaId,
      trackId: speakingSource.trackId,
      startMs: speakingSource.startMs,
      endMs: speakingSource.endMs,
      sourceLanguage: speakingSource.language,
      responseLanguage: l1,
      transcriptSnapshot: speakingSource.transcriptSnapshot,
    );
    _speakingL1PlayCount = 0;
    setState(() => _speakingL1CheckSource = source);
    await readingTaskController.openTask(
      service,
      source: source,
      templatePoints: rubric.points,
      purpose: ReadingTaskController.listeningPurpose,
    );
  }

  void _closeSpeakingL1Check() {
    readingTaskController.closeTask();
    setState(() => _speakingL1CheckSource = null);
  }

  List<SpeakingTargetCandidate> _speakingTargetCandidates() {
    final transcript = speakingTaskController.state.correctedTranscript
        .toLowerCase();
    if (transcript.isEmpty ||
        speakingTaskController.state.asrReliability == 'unreliable') {
      return const [];
    }
    final entries = <LexicalEntry>{
      ...learningController.wordEntries.values,
      ...learningController.phraseEntries.values.map(
        (details) => details.entry,
      ),
    };
    return entries
        .where(
          (entry) =>
              entry.displayForm.trim().isNotEmpty &&
              _containsSpeakingTarget(
                transcript,
                entry.displayForm.trim().toLowerCase(),
              ),
        )
        .take(12)
        .map(
          (entry) => SpeakingTargetCandidate(
            lexicalEntryId: entry.id,
            surfaceForm: entry.displayForm.trim(),
          ),
        )
        .toList(growable: false);
  }

  bool _containsSpeakingTarget(String transcript, String surface) {
    if (surface.runes.any((rune) => rune > 0x7f)) {
      return transcript.contains(surface);
    }
    var start = transcript.indexOf(surface);
    while (start >= 0) {
      final before = start == 0 ? null : transcript.codeUnitAt(start - 1);
      final afterIndex = start + surface.length;
      final after = afterIndex == transcript.length
          ? null
          : transcript.codeUnitAt(afterIndex);
      bool isAlphaNumeric(int? code) =>
          code != null &&
          ((code >= 48 && code <= 57) ||
              (code >= 65 && code <= 90) ||
              (code >= 97 && code <= 122));
      if (!isAlphaNumeric(before) && !isAlphaNumeric(after)) return true;
      start = transcript.indexOf(surface, start + 1);
    }
    return false;
  }

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

  @override
  void dispose() {
    final currentMediaId = playerController.mediaId;
    final currentPosition = playerController.position;
    if (currentMediaId != null) {
      unawaited(api?.saveProgress(currentMediaId, currentPosition));
    }
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
    unawaited(api?.close());
    playerController.dispose();
    subtitleController.dispose();
    learningController.dispose();
    practiceController.dispose();
    slicePlayerController.dispose();
    auxiliaryAudioController.dispose();
    _readingSaveTimer?.cancel();
    readingController.removeListener(_scheduleReadingPositionSave);
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
              if (connectingApi) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(status, textAlign: TextAlign.center),
              if (!connectingApi) ...[
                const SizedBox(height: 12),
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
        practiceController,
        extensiveListeningController,
        huntingController,
        huntingSessionController,
        slicePlayerController,
        readingController,
        speakingTaskController,
        speakingActions,
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
            child: Scaffold(
              appBar: PlayerAppBar(
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
                onOpenLearningAssets: () => unawaited(_openLearningAssets()),
                onOpenLearningResources: () =>
                    unawaited(_openLearningResources()),
                onShowPhraseCandidates: () =>
                    unawaited(_showCurrentPhraseCandidates()),
                onCorrectLemma: () => unawaited(_correctCurrentLemma()),
                onSearchOpenSubtitles: () => unawaited(_searchOpenSubtitles()),
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
                              onOpenReview: () => unawaited(_openReviewQueue()),
                              onOpenCoach: () =>
                                  unawaited(_openCoachDashboard()),
                              onOpenSettings: () => unawaited(_openSettings()),
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
                              onSetLibraryIntent: (entry, intent) => unawaited(
                                mediaLibraryActions.setLibraryTriageIntent(
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
                                  mediaLibraryActions.savedVocabulary?.total ??
                                  0,
                              vocabularyCapped:
                                  mediaLibraryActions.savedVocabulary?.capped ??
                                  false,
                              vocabularyKnown:
                                  mediaLibraryActions.savedVocabulary != null,
                              listeningInboxCount:
                                  extensiveListeningController.activeItemCount,
                              statusText: playerController.status,
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
                                  selectedChannel:
                                      _writingTaskStudioSource != null
                                      ? ContentChannel.writing
                                      : speakingActions.isOpen
                                      ? ContentChannel.speaking
                                      : readingController.isOpen
                                      ? ContentChannel.reading
                                      : ContentChannel.listening,
                                  channelAvailability: {
                                    ContentChannel.listening:
                                        const ContentChannelAvailability.available(),
                                    ContentChannel.reading:
                                        subtitleController.primaryTrack == null
                                        ? ContentChannelAvailability.unavailable(
                                            l.text('channelNeedsTranscript'),
                                          )
                                        : const ContentChannelAvailability.available(),
                                    ContentChannel.speaking:
                                        subtitleController.primaryTrack == null
                                        ? ContentChannelAvailability.unavailable(
                                            l.text('channelNeedsTranscript'),
                                          )
                                        : !Platform.isMacOS
                                        ? ContentChannelAvailability.unavailable(
                                            l.text('channelUnavailable'),
                                          )
                                        : const ContentChannelAvailability.available(),
                                    ContentChannel.writing:
                                        subtitleController.primaryTrack == null
                                        ? ContentChannelAvailability.unavailable(
                                            l.text('channelNeedsTranscript'),
                                          )
                                        : const ContentChannelAvailability.available(),
                                  },
                                  onChannelSelected: (channel) =>
                                      unawaited(_selectContentChannel(channel)),
                                  immersiveStage:
                                      _writingTaskStudioSource != null
                                      ? WritingTaskStudio(
                                          controller: writingTaskController,
                                          api: api!,
                                          audioPlayCount: () =>
                                              _writingPlayCount,
                                          onKindChanged: (kind) =>
                                              unawaited(_openWritingTask(kind)),
                                          onPlaySource: _playWritingSource,
                                          onSpeakText: (text) => unawaited(
                                            _speakWritingText(text),
                                          ),
                                          onClose: () => unawaited(
                                            _closeWritingTaskStudio(),
                                          ),
                                        )
                                      : speakingActions.isOpen
                                      ? _realtimeConversationOpen
                                            ? RealtimeConversationPanel(
                                                controller:
                                                    realtimeConversationController,
                                                api: api!,
                                                source: speakingTaskController
                                                    .state
                                                    .source!,
                                                modelId: speakingTaskController
                                                    .state
                                                    .asrModelId!,
                                                acquireAudioFocus:
                                                    speakingActions
                                                        .acquireRecordingFocus,
                                                onClose: () => unawaited(
                                                  _closeRealtimeConversation(),
                                                ),
                                              )
                                            : _speakingL1CheckSource != null
                                            ? ListeningCheckPanel(
                                                controller:
                                                    readingTaskController,
                                                api: api!,
                                                audioPlayCount: () =>
                                                    _speakingL1PlayCount,
                                                onPlaySegment: () {
                                                  setState(
                                                    () =>
                                                        _speakingL1PlayCount++,
                                                  );
                                                  unawaited(
                                                    speakingActions
                                                        .playSource(),
                                                  );
                                                },
                                                onClose: _closeSpeakingL1Check,
                                              )
                                            : SpeakingTaskStudio(
                                                controller:
                                                    speakingTaskController,
                                                api: api!,
                                                onPlaySource:
                                                    speakingActions.playSource,
                                                onPlayRecording: speakingActions
                                                    .playRecording,
                                                onAcquireRecordingFocus:
                                                    speakingActions
                                                        .acquireRecordingFocus,
                                                onShowRetelling: () =>
                                                    speakingActions.showRetelling(
                                                      api!,
                                                      fixedRubricPoints:
                                                          listeningRetellTemplate(
                                                            l,
                                                          ),
                                                    ),
                                                onShowRoleReply: (assistance) =>
                                                    speakingActions
                                                        .showRoleReply(
                                                          api!,
                                                          assistance:
                                                              assistance,
                                                          fixedRubricPoints:
                                                              roleReplyTemplate(
                                                                l,
                                                              ),
                                                        ),
                                                onOpenL1Check:
                                                    _openSpeakingL1Check,
                                                onOpenRealtimeConversation:
                                                    _openRealtimeConversation,
                                                targetCandidates:
                                                    _speakingTargetCandidates(),
                                                onClose: _closeSpeakingSurface,
                                              )
                                      : readingController.isOpen
                                      ? _readingView()
                                      : null,
                                  mediaFraction:
                                      settingsController.workbenchMediaFraction,
                                  onMediaFractionChanged:
                                      _setWorkbenchMediaFraction,
                                  onCollapse: _collapseWorkbench,
                                ),
                              ),
                            // Keep the window mounted while a neighbouring
                            // sentence's item is still being created (draft is
                            // set synchronously; item is null in flight), so
                            // sentence navigation never unmounts the panel.
                            if (practiceController.item != null ||
                                practiceController.draft != null)
                              IntensivePracticeWindow(
                                controller: practiceController,
                                currentSentence:
                                    (subtitleController
                                            .currentPrimaryCue
                                            ?.index ??
                                        0) +
                                    1,
                                totalSentences:
                                    subtitleController
                                        .primaryTrack
                                        ?.cues
                                        .length ??
                                    0,
                                canGoPrevious:
                                    subtitleController.primaryCursor.previous(
                                      subtitleController.currentPrimaryCue,
                                    ) !=
                                    null,
                                canGoNext:
                                    subtitleController.primaryCursor.next(
                                      subtitleController.currentPrimaryCue,
                                    ) !=
                                    null,
                                showSentenceNavigation:
                                    practiceController
                                        .draft
                                        ?.referenceMediaPath ==
                                    null,
                                isPlaying:
                                    practiceController
                                            .draft
                                            ?.referenceMediaPath !=
                                        null
                                    ? slicePlayerController.state.playing
                                    : playerController.playing,
                                onReplay: practiceActions.replayPracticeWindow,
                                onTogglePlayback:
                                    practiceActions.togglePracticePlayback,
                                onNavigate:
                                    practiceActions.navigatePracticeSentence,
                                onSubmit: practiceActions.submitPractice,
                                onSaveReview:
                                    practiceActions.savePracticeReview,
                                onStartRecording:
                                    practiceActions.beginShadowingRecording,
                                onStopRecording:
                                    practiceActions.stopShadowingRecording,
                                onCancelRecording:
                                    practiceController.cancelShadowingRecording,
                                onOpenMicrophoneSettings:
                                    practiceController.openMicrophoneSettings,
                                onPlayReference:
                                    practiceActions.playShadowingReferenceOnce,
                                onPlayRecording:
                                    practiceActions.playShadowingRecording,
                                onPlayAba: practiceActions.playShadowingAba,
                                onDeleteRecording: () => practiceController
                                    .deleteCurrentRecording(api),
                                onShadowingRateChanged:
                                    practiceActions.setShadowingRate,
                                onShadowingStepChanged:
                                    practiceActions.setShadowingStep,
                                onClose: practiceActions.closePracticeWindow,
                              ),
                            Positioned(
                              top: 18,
                              left: 24,
                              right: 24,
                              child: Center(
                                child: HuntingPromptCard(
                                  controller: huntingSessionController,
                                  onAnswer: (answer) => unawaited(
                                    huntingActions.answerHuntingCheck(answer),
                                  ),
                                  onReindex: () => unawaited(
                                    huntingActions.reindexHuntingCorpus(),
                                  ),
                                ),
                              ),
                            ),
                            ListenableBuilder(
                              listenable: slicePlayerController.store,
                              builder: (context, _) =>
                                  slicePlayerController.state.open
                                  ? SlicePlaybackWindow(
                                      controller: slicePlayerController,
                                      onClose: _closeSlicePlayback,
                                      onShadowing: practiceActions
                                          .startSliceWindowShadowing,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                      if (downloadController.snapshot != null)
                        _downloadStatusBar(downloadController.snapshot!),
                      _controls(),
                    ],
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

  String _timingQuality(String sentenceId) {
    final first = subtitleController.timingsBySentence[sentenceId]!.first;
    return '${first.source.replaceAll('_', ' ')} · ${first.provider}';
  }

  Widget _readingView() {
    final taskSource = _readingTaskStudioSource;
    if (taskSource != null && api != null) {
      return ReadingTaskStudio(
        controller: readingTaskController,
        api: api!,
        source: taskSource,
        audioPlayCount: () =>
            readingController.slicePlayCount(taskSource.anchorCueId),
        onClose: _closeReadingTaskStudio,
      );
    }
    final diffSource = _readingDiffSource;
    final diffParagraph = _readingDiffParagraph;
    if (diffSource != null && diffParagraph != null) {
      return ReadingDiffPanel(
        controller: readingDiffController,
        onOpenReadingTask: () {
          _closeReadingDiff();
          unawaited(_openReadingTask(diffParagraph));
        },
        onOpenListeningCheck: () {
          _closeReadingDiff();
          _openListeningCheck(diffParagraph, diffSource);
        },
        onClose: _closeReadingDiff,
      );
    }
    final listeningSource = _listeningCheckSource;
    if (listeningSource != null && api != null) {
      return ListeningCheckPanel(
        controller: readingTaskController,
        api: api!,
        audioPlayCount: () => _listeningPlayCount,
        onPlaySegment: () {
          setState(() => _listeningPlayCount++);
          unawaited(
            _openSlicePlayback(
              currentMediaSliceOccurrence(
                mediaId: listeningSource.mediaId,
                trackId: listeningSource.trackId,
                sentenceId: listeningSource.anchorCueId,
                textSnapshot: '',
                startMs: listeningSource.startMs,
                endMs: listeningSource.endMs,
                mediaFingerprint: playerController.mediaFingerprint,
              ),
            ),
          );
        },
        onClose: _closeListeningCheck,
      );
    }
    final reader = ReadingView(
      controller: readingController,
      wordEntries: learningController.wordEntries,
      capabilityProfiles: learningController.capabilityProfiles,
      showStyles: settingsController.statusStylesVisible,
      onWord: _openReadingWord,
      onPlaySentence: (sentence) => _playReadingRange(
        sentence.start,
        sentence.end,
        sentence.cues.first.id,
        sentence.text,
      ),
      onPlayParagraph: (paragraph) => _playReadingRange(
        paragraph.start,
        paragraph.end,
        paragraph.anchorCueId,
        paragraph.sentences.first.text,
      ),
      onStartTask: _openReadingTask,
      onSaveSentencePattern: (sentence) => _openPersonalExpression(
        source: PersonalExpressionSourceView(
          kind: 'reading',
          text: sentence.text,
          title: playerController.mediaTitle,
          mediaId: playerController.mediaId,
          mediaFingerprint: playerController.mediaFingerprint,
          trackId: subtitleController.primaryTrack?.id,
          sentenceId: sentence.cues.first.id,
          startMs: sentence.start.inMilliseconds,
          endMs: sentence.end.inMilliseconds,
        ),
      ),
      onOpenDiff: _openReadingDiff,
      onClose: () => unawaited(_closeReading()),
    );
    return ReadingContextLayout(
      reader: reader,
      inspectorOpen: _readingWordInspectorOpen,
      inspector: ReadingWordInspector(
        learningController: learningController,
        onClose: () => setState(() => _readingWordInspectorOpen = false),
        onStatus: (selected) =>
            unawaited(vocabularyActions.setSelectedWordStatus(selected)),
        onSave: vocabularyActions.saveSelectedLearningContent,
        onSource: (occurrence) => unawaited(_openSlicePlayback(occurrence)),
        onHeard: () => unawaited(vocabularyActions.observeSelected(true)),
        onNotHeard: () => unawaited(vocabularyActions.observeSelected(false)),
        onCapabilityOverride: vocabularyActions.setCapabilityOverride,
        onRecordSource: () =>
            unawaited(vocabularyActions.recordCurrentSource()),
        onReadingMark: (understood) =>
            unawaited(_recordReadingMark(understood)),
        onOpenListeningDictionary: () {
          final entry = learningController.selectedLexicalDetails?.entry;
          if (entry != null) {
            unawaited(_openListeningDictionaryEntry(entry.id));
          }
        },
        onPlayPronunciationAudio: _playPronunciationAudio,
        hasSelectedCue: subtitleController.currentPrimaryCue != null,
      ),
    );
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
    onOpenReading: () => unawaited(_openReading()),
    onOpenDiagnosisView: _openDiagnosisView,
    onOpenSlicePlayback: _openSlicePlayback,
    onOpenListeningDictionary: _openListeningDictionaryEntry,
    onPlayPronunciationAudio: _playPronunciationAudio,
    onOpenL1Specialty: _openL1Specialty,
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
