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
import 'transcription_ui.dart';

import 'controllers/app_controllers.dart';
import 'controllers/backend_event_coordinator.dart';
import 'controllers/download_controller.dart';
import 'controllers/learning_controller.dart';
import 'controllers/learning_workflow_controller.dart';
import 'controllers/media_session_coordinator.dart';
import 'controllers/playback_actions_coordinator.dart';
import 'controllers/player_controller.dart';
import 'controllers/practice_controller.dart';
import 'controllers/resource_actions_coordinator.dart';
import 'controllers/speech_enhancement_workflow_controller.dart';
import 'controllers/subtitle_controller.dart';
import 'controllers/settings_controller.dart';
import 'models/capability_readiness.dart';
import 'models/practice.dart';
import 'models/task_status.dart';
import 'models/timeline.dart';
import 'models/types.dart';
import 'phonetic_analysis_ui.dart';
import 'services/api_service.dart';
import 'services/external_tools.dart';
import 'utils/word_list_parser.dart';
import 'screens/subtitle_resources_screen.dart';
import 'screens/vocabulary_screen.dart';
import 'widgets/player/download_status_bar.dart';
import 'widgets/app_bar/player_app_bar.dart';
import 'widgets/flows/manual_review_flow.dart';
import 'widgets/flows/media_import_flows.dart';
import 'widgets/layout/playback_bar.dart';
import 'widgets/layout/player_stage.dart';
import 'widgets/layout/side_panel.dart';
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff6dd6c3),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PlayerScreen(),
    ),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // ── Service / infrastructure handles ──
  final adapter = DesktopPlayerAdapter();
  final transcriptController = ScrollController();
  final subscriptions = <StreamSubscription<dynamic>>[];
  Timer? progressTimer;
  LocalApi? api;

  // ── Controllers ──
  final playerController = PlayerController();
  final subtitleController = SubtitleController();
  final learningController = LearningController();
  final practiceController = PracticeController();
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

  // ── Local UI state (not managed by controllers) ──
  String get status => playerController.status;
  final taskStatuses = <UserTaskKind, UserTaskStatus>{};
  bool dragging = false;
  bool connectingApi = true;

  // ── Convenience ──
  AppLocalizations get l => AppLocalizations.of(context);

  ExternalTools get tools => ExternalTools(
    ffmpegPath: settingsController.ffmpegPath,
    ffprobePath: settingsController.ffprobePath,
    ytDlpPath: settingsController.ytDlpPath,
  );
  double get transcriptItemExtent => 76;

  // Tracks the last primary cue id for de-duplicating async calls in _onPosition.
  String? _lastPrimaryCueId;

  @override
  void initState() {
    super.initState();
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
        await _loadWordEntries();
        await _loadPhraseEntries();
      },
    );
    mediaSession.bind(
      getApi: () => api,
      isMounted: () => mounted,
      text: (key) => l.text(key),
      confirmLLTimelineMismatch: _confirmLLTimelineMismatch,
      onMediaSwitched: () {
        setState(() {
          taskStatuses.clear();
        });
      },
      reloadLearningEntries: () async {
        await _loadWordEntries();
        await _loadPhraseEntries();
      },
      loadPhraseCandidates: _loadPhraseCandidates,
      generatedPrimaryStatus: _generatedPrimarySubtitleStatus,
    );
    playbackActions.bind(
      getApi: () => api,
      isMounted: () => mounted,
      reloadLearningEntries: () async {
        await _loadWordEntries();
        await _loadPhraseEntries();
      },
      openMediaPath: mediaSession.openMediaPath,
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
      ffmpegPath: settingsController.ffmpegPath,
      ffprobePath: settingsController.ffprobePath,
      ytDlpPath: settingsController.ytDlpPath,
      transcriptionQuality: settingsController.transcriptionQuality,
      transcriptionLanguage: settingsController.transcriptionLanguage,
      transcriptionDestination: settingsController.transcriptionDestination,
      openSubtitlesApiKey: settingsController.openSubtitlesApiKey,
      wordSyncVisible: settingsController.wordSyncVisible,
      showChunkGrouping: settingsController.showChunkGrouping,
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
    ),
  );

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
        }
      });
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
      loadWordEntries: _loadWordEntries,
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
      chunkEnabled:
          settingsController.showChunkGrouping &&
          settingsController.highlightCurrentChunk,
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
      _keepCurrentVisible(primaryCue);
      unawaited(_refreshDiagnosis());
      unawaited(_loadPhraseCandidates(primaryCue));
      unawaited(_ensureCurrentPronunciation(primaryCue));
    }
    playerController.setPosition(value);
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

  Future<void> _deleteSubtitleResource(SubtitleTrack track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('deleteResource')),
        content: Text(l.text('deleteSubtitleResourceBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.text('deleteResource')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await resourceActions.deleteSubtitleResource(track);
  }

  Future<void> _exportSubtitleResource(SubtitleTrack track) async {
    if (api == null) return;
    final format = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.text('exportSubtitleFormat')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'srt'),
            child: ListTile(
              leading: const Icon(Icons.subtitles_outlined),
              title: Text(l.text('exportSrt')),
              subtitle: const Text('.srt'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'lltimeline'),
            child: ListTile(
              leading: const Icon(Icons.timeline),
              title: Text(l.text('exportLLTimelineJson')),
              subtitle: const Text('.lltimeline.json'),
            ),
          ),
        ],
      ),
    );
    if (format == null) return;
    if (format == 'lltimeline') {
      await resourceActions.exportLLTimelineResource(track);
    } else {
      await resourceActions.exportSubtitleSrt(track);
    }
  }

  Future<void> _openManualReviewTimeline() => openManualReviewFlow(
    context: context,
    api: api,
    adapter: adapter,
    playerController: playerController,
    subtitleController: subtitleController,
    resourceActions: resourceActions,
    mediaSession: mediaSession,
  );

  Future<void> _ensureCurrentPronunciation(Cue? cue) async {
    final service = api;
    if (cue == null ||
        service == null ||
        subtitleController.pronunciationBySentence.containsKey(cue.id)) {
      return;
    }
    try {
      final value = await service.analyzePronunciation(cue.id);
      if (mounted && subtitleController.currentPrimaryCue?.id == cue.id) {
        subtitleController.setSentencePronunciation(
          cue.id,
          PronunciationAnalysis.fromJson(value),
        );
      }
    } catch (_) {
      // Pronunciation is optional and must never block playback.
    }
  }

  Future<void> _analyzePhonetics({required bool wholeTrack}) async {
    final service = api;
    final track = subtitleController.primaryTrack;
    final cue = subtitleController.currentPrimaryCue;
    if (service == null || track == null || (!wholeTrack && cue == null)) {
      _showSnackBar('No media or subtitle loaded');
      return;
    }
    try {
      final models = await service.phoneticAnalysisModels();
      final preferred = settingsController.settings.phoneticModelId;
      final model = models.cast<Map<String, dynamic>?>().firstWhere(
        (value) =>
            value != null &&
            (value['id'] == preferred ||
                (preferred.isEmpty &&
                    (value['state'] == 'installed' ||
                        value['state'] == 'custom'))),
        orElse: () => null,
      );
      if (model == null) {
        throw StateError('No compatible phonetic analysis model is available');
      }
      final job = await service.createPhoneticAnalysisJob(
        trackId: track.id,
        sentenceId: wholeTrack ? null : cue!.id,
        modelId: model['id'] as String,
      );
      if (mounted) {
        _setTaskStatus(
          UserTaskStatus(
            kind: UserTaskKind.audioAnalysis,
            state: UserTaskState.working,
            rawStatus: job['status'] as String? ?? 'queued',
            progress: 0,
            targetId: track.id,
          ),
        );
        _showSnackBar('Audio analysis ${job['status']}');
      }
    } catch (error) {
      if (mounted) {
        _setTaskStatus(
          UserTaskStatus(
            kind: UserTaskKind.audioAnalysis,
            state: UserTaskState.error,
            rawStatus: 'failed',
            progress: 0,
            targetId: track.id,
          ),
        );
        _showSnackBar('Audio analysis failed: $error');
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _generateSubtitles({required bool secondary}) async {
    if (api == null || playerController.mediaId == null) {
      playerController.setStatus('Open media and connect the local core first');
      return;
    }
    final created = await showGenerateSubtitles(
      context: context,
      api: api!,
      mediaId: playerController.mediaId!,
      secondary: secondary,
      preferredQuality: settingsController.transcriptionQuality,
      preferredLanguage: settingsController.transcriptionLanguage,
    );
    if (created && mounted) {
      playerController.setStatus(
        secondary
            ? l.text('secondarySubtitleGenerationStarted')
            : l.text('primarySubtitleGenerationStarted'),
      );
      setState(() {
        taskStatuses[UserTaskKind.subtitleGeneration] = UserTaskStatus(
          kind: UserTaskKind.subtitleGeneration,
          state: UserTaskState.working,
          rawStatus: 'queued',
          progress: 0,
          targetId: playerController.mediaId,
        );
      });
    }
  }

  Future<void> _openTranscriptionCenter() async {
    if (api == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TranscriptionCenter(
          api: api!,
          loadTrack: mediaSession.loadGeneratedTrack,
        ),
      ),
    );
  }

  Future<void> _openPhoneticAnalysisCenter() async {
    if (api == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => PhoneticAnalysisCenter(api: api!)),
    );
  }

  Future<void> _handleDrop(List<String> paths) async {
    final media = paths.where(_isMediaPath).toList(growable: false);
    final subtitles = paths.where(_isSubtitlePath).toList(growable: false);
    if (media.isNotEmpty) await mediaSession.openMediaPath(media.first);
    for (final path in subtitles) {
      if (playerController.mediaId == null || api == null) {
        playerController.setStatus('Drop or open media before subtitles');
        return;
      }
      await mediaSession.openSubtitlePath(
        path,
        secondary: subtitleController.primaryTrack != null,
      );
    }
    if (media.isEmpty && subtitles.isEmpty) {
      playerController.setStatus('Unsupported dropped file type');
    }
  }

  bool _isMediaPath(String path) => const {
    'mp4',
    'mkv',
    'mov',
    'webm',
    'm4a',
    'mp3',
    'wav',
    'flac',
  }.contains(path.split('.').last.toLowerCase());

  bool _isSubtitlePath(String path) =>
      const {'srt', 'vtt'}.contains(path.split('.').last.toLowerCase());

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
      });
    },
  );

  Future<void> _importEmbeddedSubtitle() => importEmbeddedSubtitleFlow(
    context: context,
    playerController: playerController,
    mediaSession: mediaSession,
    tools: tools,
    api: api,
    isMediaPath: _isMediaPath,
  );

  Future<void> _openSettings() => showAppSettings(
    context: context,
    settingsController: settingsController,
    subtitleController: subtitleController,
    playerController: playerController,
    learningController: learningController,
    saveSettings: _saveSettings,
  );

  Future<void> _openLearningAssets() async {
    if (api == null) return;
    final occurrence = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) =>
            LearningAssetsScreen(api: api!, language: _learningLanguage),
      ),
    );
    if (occurrence != null) await playbackActions.playOccurrence(occurrence);
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
        'language': _learningLanguage,
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

  Future<void> _loadPhraseCandidates(Cue? cue) async {
    await learningWorkflowController.loadPhraseCandidates(
      api: api,
      cue: cue,
      learning: learningController,
      isMounted: () => mounted,
      currentCueId: () => subtitleController.currentPrimaryCue?.id,
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
        'language': _learningLanguage,
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
      language: _learningLanguage,
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

  Future<void> _markFirstWord(String? wordStatus) async {
    await learningWorkflowController.markFirstWord(
      api: api,
      cue: subtitleController.currentPrimaryCue,
      wordStatus: wordStatus,
      language: _learningLanguage,
      learning: learningController,
      isMounted: () => mounted,
      sourceFor: _sourceFor,
    );
    await _refreshDiagnosis();
  }

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

  Future<void> _loadWordEntries() async {
    await learningWorkflowController.loadWordEntries(
      api: api,
      track: subtitleController.primaryTrack,
      language: _learningLanguage,
      learning: learningController,
      isMounted: () => mounted,
    );
  }

  Future<void> _loadPhraseEntries() async {
    await learningWorkflowController.loadPhraseEntries(
      api: api,
      language: _learningLanguage,
      learning: learningController,
      isMounted: () => mounted,
    );
  }

  Future<void> _openWord(SubtitleToken token, Cue cue) async {
    try {
      await learningWorkflowController.openWord(
        api: api,
        token: token,
        cue: cue,
        language: _learningLanguage,
        learning: learningController,
        isMounted: () => mounted,
      );
    } catch (error) {
      if (mounted) playerController.setStatus('Dictionary unavailable: $error');
    }
  }

  Future<void> _setSelectedWordStatus(String? selected) async {
    try {
      final update = await learningWorkflowController.setSelectedWordStatus(
        api: api,
        selected: selected,
        language: _learningLanguage,
        learning: learningController,
        isMounted: () => mounted,
        sourceFor: _sourceFor,
      );
      if (mounted && update != null) {
        playerController.setStatus(
          'Updated global status for "${update.tokenText}"',
        );
      }
      await _refreshDiagnosis();
    } catch (error) {
      if (mounted) playerController.setStatus('Word update failed: $error');
    }
  }

  Future<void> _saveSelectedLearningContent(
    String? definition,
    String? note,
  ) async {
    await learningWorkflowController.saveSelectedLearningContent(
      api: api,
      definition: definition,
      note: note,
      learning: learningController,
      isMounted: () => mounted,
    );
  }

  Future<void> _observeSelected(bool heard) async {
    final observed = await learningWorkflowController.observeSelected(
      api: api,
      heard: heard,
      learning: learningController,
      sourceFor: _sourceFor,
    );
    if (!observed) return;
    if (mounted) {
      playerController.setStatus(heard ? l.text('heard') : l.text('notHeard'));
    }
    await _refreshDiagnosis();
  }

  Future<void> _startClozePractice() async {
    learningController.selectSidePanel(4);
    final cue = subtitleController.currentPrimaryCue;
    await practiceController.startCloze(
      api: api,
      cue: cue,
      mediaId: playerController.mediaId,
      trackId: subtitleController.primaryTrack?.id,
      wordTimings: cue == null
          ? const []
          : subtitleController.timingsBySentence[cue.id] ?? const [],
      wordEntries: learningController.wordEntries,
      mediaTimeMs: _mediaTimeMs,
    );
    if (practiceController.item != null) {
      await _replayPracticeWindow();
    }
  }

  Future<void> _startChunkDictationPractice() async {
    learningController.selectSidePanel(4);
    await practiceController.startChunkDictation(
      api: api,
      cue: subtitleController.currentPrimaryCue,
      chunk: _currentPracticeChunk(),
      mediaId: playerController.mediaId,
      trackId: subtitleController.primaryTrack?.id,
      mediaTimeMs: _mediaTimeMs,
    );
    if (practiceController.item != null) {
      await _replayPracticeWindow();
    }
  }

  Future<void> _startSentenceDictationPractice() async {
    learningController.selectSidePanel(4);
    await practiceController.startSentenceDictation(
      api: api,
      cue: subtitleController.currentPrimaryCue,
      mediaId: playerController.mediaId,
      trackId: subtitleController.primaryTrack?.id,
      mediaTimeMs: _mediaTimeMs,
    );
    if (practiceController.item != null) {
      await _replayPracticeWindow();
    }
  }

  Future<void> _replayPracticeWindow() async {
    final draft = practiceController.draft;
    if (draft == null) return;
    await playbackActions.loopRange(
      draft.playbackStartMs,
      draft.playbackEndMs,
      'Looping practice window',
    );
  }

  Future<void> _submitPractice() async {
    await practiceController.submit(api);
    final attempt = practiceController.attempt;
    if (attempt != null && mounted) {
      playerController.setStatus(
        'Practice ${attempt.result}; ${attempt.evaluation.summary}',
      );
    }
    await _refreshDiagnosis();
  }

  Future<void> _savePracticeReview() async {
    await practiceController.saveCurrentFailureToReview(api);
    if (practiceController.attempt?.generatedReviewItemIds.isNotEmpty == true &&
        mounted) {
      playerController.setStatus('Practice failure saved to review');
    }
  }

  Future<void> _markStuckPoint() async {
    final marked = await practiceController.markCurrentStuckPoint(
      api: api,
      cue: subtitleController.currentPrimaryCue,
      chunk: _currentPracticeChunk(),
      mediaId: playerController.mediaId,
      trackId: subtitleController.primaryTrack?.id,
      mediaTimeMs: _mediaTimeMs,
      diagnosis: learningController.diagnosis,
    );
    if (marked && mounted) playerController.setStatus('Stuck point marked');
  }

  Future<void> _skipStuckPoint() async {
    final skipped = await practiceController.skipCurrentStuckPoint(
      api: api,
      cue: subtitleController.currentPrimaryCue,
      chunk: _currentPracticeChunk(),
      mediaId: playerController.mediaId,
      trackId: subtitleController.primaryTrack?.id,
      mediaTimeMs: _mediaTimeMs,
      diagnosis: learningController.diagnosis,
    );
    if (skipped && mounted) playerController.setStatus('Stuck point skipped');
  }

  Future<void> _openDiagnosisView() async {
    learningController.selectSidePanel(3);
    await _refreshDiagnosis();
    final recorded = await practiceController.recordDiagnosisView(
      api: api,
      cue: subtitleController.currentPrimaryCue,
      chunk: _currentPracticeChunk(),
      mediaId: playerController.mediaId,
      trackId: subtitleController.primaryTrack?.id,
      mediaTimeMs: _mediaTimeMs,
      diagnosis: learningController.diagnosis,
    );
    if (recorded && mounted) {
      playerController.setStatus('Diagnosis view recorded');
    }
  }

  Future<void> _completePracticeSession() async {
    final openCount = practiceController.summary?.openCount ?? 0;
    if (openCount > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.text('finishIntensive')),
          content: Text(
            l
                .text('finishIntensiveWithOpen')
                .replaceFirst('{count}', '$openCount'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.text('close')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.text('finishIntensive')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final completed = await practiceController.completeSession(api);
    if (completed && mounted) {
      playerController.setStatus('Intensive session completed');
    }
  }

  Future<void> _replayStuckPoint(StuckPointSummary point) async {
    final start = point.playbackStartMs;
    final end = point.playbackEndMs;
    if (start == null || end == null) {
      playerController.setStatus('No playable range for this stuck point');
      return;
    }
    await playbackActions.loopRange(start, end, 'Looping stuck point');
  }

  Future<void> _closeStuckPoint(StuckPointSummary point) async {
    final closed = await practiceController.closeStuckPoint(
      api,
      point.targetKey,
    );
    if (closed && mounted) playerController.setStatus('Stuck point closed');
  }

  int _mediaTimeMs(Duration subtitleTime) =>
      playbackActions.mediaTime(subtitleTime).inMilliseconds;

  DisplayChunk? _currentPracticeChunk() {
    final cue = subtitleController.currentPrimaryCue;
    if (cue == null) return null;
    final current = playbackActions.currentChunkRef();
    if (current?.cue.id == cue.id) return current!.chunk;
    final partition = subtitleController.chunkPartitionsBySentence[cue.id];
    if (partition == null || partition.chunks.isEmpty) return null;
    final currentIndex = subtitleController.currentChunkIndex;
    if (currentIndex != null) {
      for (final chunk in partition.chunks) {
        if (chunk.index == currentIndex) return chunk;
      }
    }
    return partition.chunks.first;
  }

  /// Resolves the learning language for vocabulary, dictionary, source-snapshot
  /// and diagnosis queries. Priority: user setting > active subtitle track
  /// language > en fallback.
  String get _learningLanguage {
    final preferred = settingsController.learningLanguage;
    if (preferred != 'auto') return preferred;
    return subtitleController.primaryTrack?.language ?? 'en';
  }

  Map<String, dynamic>? _sourceFor(SubtitleToken token, Cue cue) {
    if (playerController.mediaFingerprint == null) return null;
    return {
      'media_id': playerController.mediaId,
      'sentence_id': cue.id,
      'original_form': token.text,
      'sentence_text': cue.text,
      'media_title': playerController.mediaTitle ?? '',
      'media_fingerprint': playerController.mediaFingerprint,
      'start_ms': cue.start.inMilliseconds,
      'end_ms': cue.end.inMilliseconds,
      'token_start': token.index,
      'token_end': token.index,
    };
  }

  Future<void> _openVocabulary() async {
    final service = api;
    if (service == null) return;
    final occurrence = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => VocabularyScreen(
          api: service,
          language: _learningLanguage,
          onExport: playbackActions.exportVocabulary,
          onImport: playbackActions.importVocabulary,
        ),
      ),
    );
    if (occurrence == null) return;
    await playbackActions.playOccurrence(
      occurrence,
      statusBeforeLoop: 'Looping vocabulary source sentence',
      filterMediaExtensions: true,
    );
  }

  Future<void> _openSubtitleResources() async {
    if (api == null) return;
    await resourceActions.loadSubtitleResources(updateStatus: false);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SubtitleResourcesScreen(
          playerController: playerController,
          subtitleController: subtitleController,
          onImportSubtitle: () => mediaSession.openSubtitle(secondary: false),
          onImportLLTimeline: mediaSession.openLLTimelineResource,
          onRefreshResources: resourceActions.refreshSubtitleResources,
          onActivateSubtitle: resourceActions.activateSubtitleResource,
          onArchiveSubtitle: resourceActions.archiveSubtitleResource,
          onRestoreSubtitle: resourceActions.restoreSubtitleResource,
          onDeleteSubtitle: _deleteSubtitleResource,
          onExportSubtitle: _exportSubtitleResource,
          onLanguageChanged: resourceActions.changeTrackLanguage,
          availableLanguages: learningController.availableLanguages,
          onExportLLTimeline: resourceActions.exportLLTimelineResource,
          onActivateWordTimeline: resourceActions.activateWordTimeline,
          onManualReviewTimeline: _openManualReviewTimeline,
          onActivatePhoneTimeline: resourceActions.activatePhoneTimeline,
          onArchivePhoneTimeline: resourceActions.archivePhoneTimeline,
          onDeletePhoneTimeline: resourceActions.deletePhoneTimeline,
          onGenerateChunkTimeline: resourceActions.generateChunkTimeline,
          onActivateChunkTimeline: resourceActions.activateChunkTimeline,
          onArchiveChunkTimeline: resourceActions.archiveChunkTimeline,
          onDeleteChunkTimeline: resourceActions.deleteChunkTimeline,
        ),
      ),
    );
  }

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
    await playbackActions.loopRange(start, end, 'Looping sound-line evidence');
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
      language: _learningLanguage,
      defaultStatus: defaultStatus,
      overwriteExisting: overwrite,
    );
    await _loadWordEntries();
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

  void _keepCurrentVisible(Cue? cue) {
    if (cue == null || !transcriptController.hasClients) return;
    final target = (cue.index * transcriptItemExtent).clamp(
      0,
      transcriptController.position.maxScrollExtent,
    );
    transcriptController.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    final currentMediaId = playerController.mediaId;
    final currentPosition = playerController.position;
    if (currentMediaId != null) {
      unawaited(api?.saveProgress(currentMediaId, currentPosition));
    }
    downloadController.dispose();
    unawaited(_saveSettings());
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    transcriptController.dispose();
    progressTimer?.cancel();
    unawaited(adapter.dispose());
    unawaited(api?.close());
    playerController.dispose();
    subtitleController.dispose();
    learningController.dispose();
    practiceController.dispose();
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
        settingsController,
        downloadController,
      ]),
      builder: (context, _) => AppControllers(
        player: playerController,
        subtitle: subtitleController,
        learning: learningController,
        practice: practiceController,
        settings: settingsController,
        api: api!,
        child: PlayerGlobalShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.space):
                adapter.playOrPause,
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekCue(
              subtitleController.primaryCursor.previous(
                subtitleController.currentPrimaryCue,
              ),
            ),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _seekCue(
                  subtitleController.primaryCursor.next(
                    subtitleController.currentPrimaryCue,
                  ),
                ),
            const SingleActivator(LogicalKeyboardKey.keyL): () =>
                subtitleController.setLoopCue(!subtitleController.loopCue),
            const SingleActivator(LogicalKeyboardKey.keyH): () =>
                subtitleController.setVisible(!subtitleController.visible),
            const SingleActivator(LogicalKeyboardKey.digit1): () =>
                _markFirstWord('unknown_meaning'),
            const SingleActivator(LogicalKeyboardKey.digit2): () =>
                _markFirstWord('known_not_recognized'),
            const SingleActivator(LogicalKeyboardKey.digit3): () =>
                _markFirstWord('known_recognized'),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: PlayerAppBar(
                onOpenSubtitleResources: () =>
                    unawaited(_openSubtitleResources()),
                onOpenVocabulary: _openVocabulary,
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
                    _handleDrop(
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
                        child: Row(
                          children: [
                            Expanded(flex: 3, child: _playerStage()),
                            if (subtitleController.primaryTrack != null ||
                                learningController.selectedLexicalDetails !=
                                    null ||
                                learningController.sidePanel == 1 ||
                                learningController.sidePanel == 4 ||
                                practiceController.draft != null)
                              SizedBox(
                                width: settingsController.transcriptWidth,
                                child: _sidePanel(),
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
    onOpenWord: _openWord,
    onOpenPhrase: _openPhrase,
    onLoopSoundRibbonFinding: _loopSoundRibbonFinding,
    onLoopRhythmCue: _loopRhythmCue,
    onSetSoundPatternDisplayMode: _setSoundPatternDisplayMode,
    onSaveSettings: _saveSettings,
    onOpenMedia: mediaSession.openMedia,
  );

  String _timingQuality(String sentenceId) {
    final first = subtitleController.timingsBySentence[sentenceId]!.first;
    return '${first.source.replaceAll('_', ' ')} · ${first.provider}';
  }

  Widget _sidePanel() => SidePanel(
    playerController: playerController,
    subtitleController: subtitleController,
    learningController: learningController,
    practiceController: practiceController,
    settingsController: settingsController,
    resourceActions: resourceActions,
    mediaSession: mediaSession,
    playbackActions: playbackActions,
    transcriptController: transcriptController,
    transcriptItemExtent: transcriptItemExtent,
    onOpenWord: _openWord,
    onSeekCue: _seekCue,
    onSetSelectedWordStatus: _setSelectedWordStatus,
    onSaveSelectedLearningContent: _saveSelectedLearningContent,
    onObserveSelected: _observeSelected,
    onManualReviewTimeline: _openManualReviewTimeline,
    onDeleteSubtitle: _deleteSubtitleResource,
    onExportSubtitle: _exportSubtitleResource,
    onAnalyzePhonetics: _analyzePhonetics,
    onStartClozePractice: _startClozePractice,
    onStartChunkDictationPractice: _startChunkDictationPractice,
    onStartSentenceDictationPractice: _startSentenceDictationPractice,
    onMarkStuckPoint: _markStuckPoint,
    onSkipStuckPoint: _skipStuckPoint,
    onReplayPracticeWindow: _replayPracticeWindow,
    onSubmitPractice: _submitPractice,
    onSavePracticeReview: _savePracticeReview,
    onCompletePracticeSession: _completePracticeSession,
    onReplayStuckPoint: _replayStuckPoint,
    onCloseStuckPoint: _closeStuckPoint,
    onOpenDiagnosisView: _openDiagnosisView,
    timingQuality: _timingQuality,
  );

  Widget _controls() => PlaybackBar(
    adapter: adapter,
    playerController: playerController,
    subtitleController: subtitleController,
    mediaSession: mediaSession,
    playbackActions: playbackActions,
    taskStatuses: taskStatuses.values.toList(growable: false),
    onSeekCue: _seekCue,
    onSaveSettings: _saveSettings,
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
