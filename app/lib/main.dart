import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'localization.dart';
import 'm18_ui.dart';
import 'player_adapter.dart';
import 'settings.dart';
import 'theme/listen_theme.dart';

import 'controllers/app_controllers.dart';
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
import 'controllers/resource_actions_coordinator.dart';
import 'controllers/speech_enhancement_workflow_controller.dart';
import 'controllers/subtitle_controller.dart';
import 'controllers/subtitle_sources_coordinator.dart';
import 'controllers/vocabulary_actions_coordinator.dart';
import 'controllers/settings_controller.dart';
import 'controllers/slice_player_controller.dart';
import 'models/capability_readiness.dart';
import 'models/practice.dart';
import 'models/task_status.dart';
import 'models/timeline.dart';
import 'models/types.dart';
import 'services/api_service.dart';
import 'services/external_tools.dart';
import 'utils/word_list_parser.dart';
import 'widgets/panels/intensive_practice_window.dart';
import 'widgets/panels/l1_specialty_dialog.dart';
import 'widgets/panels/hunting_prompt_card.dart';
import 'widgets/panels/slice_playback_window.dart';
import 'widgets/coach/coach_dashboard_screen.dart';
import 'screens/vocabulary_screen.dart';
import 'screens/review_queue_screen.dart';
import 'widgets/player/download_status_bar.dart';
import 'widgets/app_bar/player_app_bar.dart';
import 'widgets/flows/manual_review_flow.dart';
import 'widgets/flows/media_import_flows.dart';
import 'widgets/flows/subtitle_resource_flows.dart';
import 'widgets/layout/playback_bar.dart';
import 'widgets/layout/media_workbench.dart';
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
  LocalApi? api;

  // ── Controllers ──
  final playerController = PlayerController();
  final subtitleController = SubtitleController();
  final learningController = LearningController();
  final practiceController = PracticeController();
  final slicePlayerController = SlicePlayerController();
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

  Future<void> _openLearningAssets() async {
    if (api == null) return;
    final occurrence = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => LearningAssetsScreen(
          api: api!,
          language: settingsController.resolveLearningLanguage(
            subtitleController.primaryTrack?.language,
          ),
        ),
      ),
    );
    if (occurrence != null) await _openSlicePlayback(occurrence);
  }

  Future<void> _openLearningResources() async {
    if (api == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => LearningResourceScreen(api: api!)),
    );
  }

  Future<void> _showCurrentPhraseCandidates() async {
    final cue = subtitleController.currentPrimaryCue;
    if (api == null ||
        cue == null ||
        playerController.mediaFingerprint == null) {
      return;
    }
    await showPhraseCandidates(
      context: context,
      api: api!,
      sentenceId: cue.id,
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
    );
  }

  Future<void> _openPhrase(PhraseCandidate candidate, Cue cue) async {
    if (api == null || playerController.mediaFingerprint == null) return;
    final canonical = candidate.canonicalForm;
    final details = await showPhraseCandidate(
      context: context,
      api: api!,
      candidate: candidate.toJson(),
      initialStatus: learningController.phraseEntries[canonical]?.entry.status,
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
    );
    if (details != null && mounted) {
      learningController.updateSinglePhraseEntry(
        canonical,
        LexicalEntryDetails.fromJson(details),
      );
      playerController.setStatus('Saved phrase "${candidate.displayForm}"');
    }
  }

  Future<void> _correctCurrentLemma() async {
    final token = learningController.selectedToken;
    if (api == null || token?.normalized == null) return;
    final controller = TextEditingController(text: token!.normalized);
    final corrected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct lemma'),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l.text('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (corrected == null || corrected.isEmpty) return;
    await api!.correctLemma(
      token.normalized!,
      corrected,
      language: settingsController.resolveLearningLanguage(
        subtitleController.primaryTrack?.language,
      ),
    );
    if (mounted) playerController.setStatus(l.text('lemmaCorrectionSaved'));
  }

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

  /// Opens the same-family clip aggregation for one L1 difficulty hint
  /// (Phase 3.9): listen goes through the slice playback window; practice is
  /// available for clips of the currently loaded track and seeds the
  /// practice window on that sentence.
  Future<void> _openL1Specialty(L1DiagnosisHint hint) async {
    final service = api;
    if (service == null || !mounted) return;
    final currentTrackId = subtitleController.primaryTrack?.id;
    Map<String, dynamic> payload;
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
      await _openSlicePlayback(action.occurrence);
      return;
    }
    final sentenceId = action.occurrence['sentence_id'] as String?;
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

  Future<void> _showVocabulary({String? initialEntryId}) async {
    final service = api;
    if (service == null) return;
    // The dictionary hosts its own slice playback; it only needs a way to
    // silence the primary player so a slice owns audio focus alone.
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => VocabularyScreen(
          api: service,
          language: settingsController.resolveLearningLanguage(
            subtitleController.primaryTrack?.language,
          ),
          onExport: playbackActions.exportVocabulary,
          onImport: playbackActions.importVocabulary,
          huntingController: huntingController,
          initialEntryId: initialEntryId,
          onPauseBackgroundPlayback: adapter.pause,
          onStartShadowing: practiceActions.startExternalShadowing,
        ),
      ),
    );
  }

  Future<void> _openReviewQueue() async {
    final service = api;
    if (service == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewQueueScreen(
          api: service,
          currentMediaId: playerController.mediaId,
          onPlayRange: (startMs, endMs) => playbackActions.loopRange(
            startMs,
            endMs,
            'Looping review card',
            labelKey: 'loopReview',
          ),
          onStartShadowing: _startReviewShadowing,
        ),
      ),
    );
  }

  Future<void> _openCoachDashboard() async {
    final service = api;
    if (service == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CoachDashboardScreen(
          api: service,
          onOpenReview: () => unawaited(_openReviewQueue()),
          onOpenHunting: _openVocabulary,
        ),
      ),
    );
  }

  Future<void> _startReviewShadowing(ReviewQueueEntry entry) async {
    final mediaId = entry.item.source.mediaId;
    final startMs = entry.playbackStartMs;
    final endMs = entry.playbackEndMs;
    if (mediaId == null || startMs == null || endMs == null) return;
    final media = await api?.readMedia(mediaId);
    final path = media?['path'] as String?;
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

  Future<void> _importWordList() async {
    final service = api;
    if (service == null) return;
    const group = XTypeGroup(label: 'word list', extensions: ['txt', 'csv']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    final content = await File(file.path).readAsString();
    final entries = <Map<String, dynamic>>[];
    var defaultStatus = 'known_recognized';
    var overwrite = false;
    try {
      entries.addAll(
        parseExternalWordList(
          content,
          csv: file.path.toLowerCase().endsWith('.csv'),
        ),
      );
    } on FormatException catch (error) {
      playerController.setStatus(error.message);
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(l.text('previewImport')),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(
              children: [
                Text(
                  '${entries.length} words · ${entries.take(8).map((e) => e['word']).join(', ')}',
                ),
                DropdownButtonFormField<String>(
                  initialValue: defaultStatus,
                  items:
                      const [
                            'unknown_meaning',
                            'known_not_recognized',
                            'known_recognized',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(l.status(value)),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => refresh(() => defaultStatus = value!),
                ),
                CheckboxListTile(
                  value: overwrite,
                  title: Text(l.text('overwriteExisting')),
                  onChanged: (value) =>
                      refresh(() => overwrite = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.text('close')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.text('import')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final result = await service.importExternalVocabulary(
      entries,
      language: settingsController.resolveLearningLanguage(
        subtitleController.primaryTrack?.language,
      ),
      defaultStatus: defaultStatus,
      overwriteExisting: overwrite,
    );
    await vocabularyActions.loadWordEntries();
    playerController.setStatus('Imported word list: $result');
  }

  Future<void> _refreshDiagnosis() async {
    final cue = subtitleController.currentPrimaryCue;
    final service = api;
    if (cue == null || service == null) {
      if (mounted) learningController.setDiagnosis(null);
      return;
    }
    await learningWorkflowController.refreshDiagnosis(
      cue: cue,
      diagnose: (cueId) async =>
          Diagnosis.fromJson(await service.diagnose(cueId)),
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
    unawaited(adapter.dispose());
    unawaited(recordingAdapter.dispose());
    unawaited(api?.close());
    playerController.dispose();
    subtitleController.dispose();
    learningController.dispose();
    practiceController.dispose();
    slicePlayerController.dispose();
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
                                  mediaFraction:
                                      settingsController.workbenchMediaFraction,
                                  onMediaFractionChanged:
                                      _setWorkbenchMediaFraction,
                                  onCollapse: _collapseWorkbench,
                                ),
                              ),
                            if (practiceController.item != null)
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
    onOpenDiagnosisView: _openDiagnosisView,
    onOpenSlicePlayback: _openSlicePlayback,
    onOpenListeningDictionary: _openListeningDictionaryEntry,
    onOpenL1Specialty: _openL1Specialty,
    onRefreshListeningInbox: inboxActions.refreshListeningInbox,
    onReplayListeningInboxItem: inboxActions.replayListeningInboxItem,
    onProcessListeningInboxItem: inboxActions.processListeningInboxItem,
    timingQuality: _timingQuality,
    onStartColdStart: _openColdStartMarking,
    onRecordCurrentSource: vocabularyActions.recordCurrentSource,
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
