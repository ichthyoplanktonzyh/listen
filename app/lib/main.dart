import 'dart:async';
import 'dart:convert';
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
import 'controllers/manual_review_controller.dart';
import 'controllers/player_controller.dart';
import 'controllers/speech_enhancement_workflow_controller.dart';
import 'controllers/subtitle_controller.dart';
import 'controllers/settings_controller.dart';
import 'models/capability_readiness.dart';
import 'models/task_status.dart';
import 'models/timeline.dart';
import 'models/types.dart';
import 'phonetic_analysis_ui.dart';
import 'services/api_service.dart';
import 'services/external_tools.dart';
import 'utils/subtitle_style.dart';
import 'utils/word_list_parser.dart';
import 'widgets/subtitle/connected_speech_reference_ribbon.dart';
import 'widgets/subtitle/expected_pronunciation_reference.dart';
import 'widgets/subtitle/phoneme_ribbon.dart';
import 'widgets/subtitle/rhythm_frame_ribbon.dart';
import 'widgets/subtitle/sound_pattern_mode_toggle.dart';
import 'widgets/subtitle/token_line.dart';
import 'widgets/panels/word_learning_panel.dart';
import 'screens/subtitle_resources_screen.dart';
import 'screens/vocabulary_screen.dart';
import 'widgets/panels/diagnosis_card.dart';
import 'widgets/panels/manual_timeline_review_dialog.dart';
import 'widgets/panels/subtitle_resource_manager_panel.dart';
import 'widgets/panels/transcript_panel.dart';
import 'widgets/player/download_status_bar.dart';
import 'widgets/app_bar/player_app_bar.dart';
import 'widgets/player/playback_controls.dart';
import 'widgets/settings/settings_dialog.dart';

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
  runApp(const LLPlayerNextApp());
}

class LLPlayerNextApp extends StatelessWidget {
  const LLPlayerNextApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: appLanguage,
    builder: (context, language, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LLPlayerNext',
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
  final learningWorkflowController = LearningWorkflowController();
  final speechEnhancementWorkflowController =
      SpeechEnhancementWorkflowController();
  final settingsController = SettingsController();
  final downloadController = DownloadController();

  // ── Local UI state (not managed by controllers) ──
  String status = 'Starting local core...';
  // True while the manual-review status text has not been superseded by a more
  // specific message (e.g. a save result). Replaces a fragile magic-string
  // comparison so that a free-form status string no longer drives behavior.
  bool _manualReviewStatusPristine = false;
  final taskStatuses = <UserTaskKind, UserTaskStatus>{};
  bool dragging = false;
  bool connectingApi = true;
  bool _phoneEvidenceExpanded = false;

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
        setState(() => status = value);
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
      setState(() {
        connectingApi = true;
        status = 'Starting local core...';
      });
    }
    try {
      final value = await LocalApi.connect();
      if (!mounted) return value.close();
      setState(() {
        api = value;
        connectingApi = false;
        status = 'Local core connected';
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
        setState(() {
          connectingApi = false;
          status = 'Core unavailable: $error';
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
    await _openMediaPath(media);
    if (subtitle != null) await _openSubtitlePath(subtitle, secondary: false);
    if (secondary != null) await _openSubtitlePath(secondary, secondary: true);
  }

  void _onEvent(Map<String, dynamic> event) {
    BackendEventCoordinator(
      currentMediaId: () => playerController.mediaId,
      currentPrimaryTrackId: () => subtitleController.primaryTrack?.id,
      loadWordEntries: _loadWordEntries,
      loadTimelineResource: _loadTimelineResource,
      readSubtitle: (trackId) => api!.readSubtitle(trackId),
      loadGeneratedTrack: _loadGeneratedTrack,
      loadSpeechEnhancements: (trackId) async {
        await _loadSpeechEnhancements(trackId);
      },
      setStatus: (value) {
        if (mounted) setState(() => status = value);
      },
      setTaskStatus: _setTaskStatus,
      updateWordEntry: learningController.updateSingleWordEntry,
    ).handle(event);
  }

  void _setTaskStatus(UserTaskStatus value) {
    if (!mounted) return;
    setState(() {
      taskStatuses[value.kind] = value;
      status = _taskStatusText(value);
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
      _phoneEvidenceExpanded = false;
      _keepCurrentVisible(primaryCue);
      unawaited(_refreshDiagnosis());
      unawaited(_loadPhraseCandidates(primaryCue));
      unawaited(_ensureCurrentPronunciation(primaryCue));
    }
    playerController.setPosition(value);
  }

  Future<void> _openMedia() async {
    const group = XTypeGroup(
      label: 'media',
      extensions: ['mp4', 'mkv', 'mov', 'webm', 'm4a', 'mp3', 'wav', 'flac'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    await _openMediaPath(file.path);
  }

  Future<void> _openMediaPath(String path) async {
    final previousMediaId = playerController.mediaId;
    final previousPosition = playerController.position;
    final previousProgressSave = previousMediaId == null
        ? Future<void>.value()
        : api?.saveProgress(previousMediaId, previousPosition) ??
              Future<void>.value();
    setState(() {
      status = 'Opening ${path.split(Platform.pathSeparator).last}';
      taskStatuses.clear();
    });
    playerController.clearMedia();
    playerController.setMediaPath(path);
    playerController.setPosition(Duration.zero);
    playerController.setDuration(Duration.zero);
    subtitleController.setPrimaryTrack(null);
    subtitleController.setSecondaryTrack(null);
    subtitleController.setCurrentPrimaryCue(null);
    subtitleController.setCurrentSecondaryCue(null);
    subtitleController.setSubtitleResources(const []);
    subtitleController.setSubtitleResourceCapabilities(const {});
    subtitleController.clearSpeechEnhancements();
    playerController.setSourceLoop(null, null);
    try {
      await adapter.open(path, play: false);
    } catch (error) {
      if (mounted) setState(() => status = 'Playback failed: $error');
      return;
    }
    Object? coreError;
    try {
      await previousProgressSave;
      final media = await api?.registerMedia(path);
      if (media != null) {
        final id = media['id'] as String;
        final saved = await api?.readProgress(id);
        playerController.setMedia(
          id: id,
          path: path,
          title: media['title'] as String,
          fingerprint: media['fingerprint'] as String,
        );
        if (saved != null && saved > Duration.zero) {
          await adapter.seek(saved);
          playerController.setPosition(saved);
        }
        await _loadSubtitleResources(updateStatus: false);
      }
    } catch (error) {
      coreError = error;
    }
    try {
      await adapter.play();
      if (mounted) {
        setState(
          () => status = coreError == null
              ? 'Playing ${path.split(Platform.pathSeparator).last}'
              : 'Playing locally; core unavailable: $coreError',
        );
      }
    } catch (error) {
      if (mounted) setState(() => status = 'Playback failed: $error');
    }
  }

  Future<void> _openSubtitle({required bool secondary}) async {
    if (playerController.mediaId == null || api == null) {
      setState(() => status = 'Open media and connect the local core first');
      return;
    }
    const group = XTypeGroup(label: 'subtitles', extensions: ['srt', 'vtt']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    await _openSubtitlePath(file.path, secondary: secondary);
  }

  Future<void> _openSubtitlePath(String path, {required bool secondary}) async {
    try {
      final value = await api!.importSubtitle(playerController.mediaId!, path);
      await adapter.disableNativeSubtitles();
      final imported = SubtitleTrack.fromJson(value);
      if (secondary) {
        subtitleController.setSecondaryTrack(imported);
        subtitleController.setCurrentSecondaryCue(
          subtitleController.secondaryCursor.current(playerController.position),
        );
      } else {
        await _usePrimarySubtitleTrack(
          imported,
          nextStatus:
              'Loaded primary subtitle: '
              '${path.split(Platform.pathSeparator).last}',
        );
      }
      if (secondary) {
        setState(() {
          status =
              'Loaded secondary subtitle: '
              '${path.split(Platform.pathSeparator).last}';
        });
      }
      await _loadSubtitleResources(updateStatus: false);
    } catch (error) {
      setState(() => status = 'Subtitle import failed: $error');
    }
  }

  Future<void> _openLLTimelineResource() async {
    final service = api;
    final mediaId = playerController.mediaId;
    if (service == null || mediaId == null) {
      setState(() => status = 'Open media and connect the local core first');
      return;
    }
    const group = XTypeGroup(label: 'LLTimeline', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    try {
      setState(() => status = 'Importing LLTimeline resource...');
      final decoded = jsonDecode(await File(file.path).readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('LLTimeline JSON must be an object');
      }
      final resourceFingerprint = _llTimelineMediaFingerprint(decoded);
      final currentFingerprint = playerController.mediaFingerprint;
      var allowMismatch = false;
      if (resourceFingerprint != null &&
          currentFingerprint != null &&
          resourceFingerprint != currentFingerprint) {
        allowMismatch = await _confirmLLTimelineMismatch(
          resourceFingerprint: resourceFingerprint,
          currentFingerprint: currentFingerprint,
        );
        if (!allowMismatch) {
          if (mounted) setState(() => status = 'LLTimeline import cancelled');
          return;
        }
      }
      final value = await service.importLLTimelineForMedia(
        mediaId,
        decoded,
        allowMismatch: allowMismatch,
      );
      final imported = SubtitleTrack.fromJson(value);
      await _usePrimarySubtitleTrack(
        imported,
        nextStatus:
            'Imported LLTimeline resource: '
            '${file.path.split(Platform.pathSeparator).last}',
      );
      subtitleController.setTimelineResource(
        summaries: subtitleController.wordTimelineSummaries,
        phoneSummaries: subtitleController.phoneTimelineSummaries,
        chunkSummaries: subtitleController.chunkTimelineSummaries,
        document: LLTimelineDocument.fromJson(decoded),
        error: subtitleController.timelineResourceError,
      );
      await _loadSubtitleResources(updateStatus: false);
      learningController.selectSidePanel(1);
    } catch (error) {
      setState(() => status = 'LLTimeline import failed: $error');
    }
  }

  Future<SpeechEnhancementLoadResult?> _usePrimarySubtitleTrack(
    SubtitleTrack track, {
    required String nextStatus,
  }) async {
    await adapter.disableNativeSubtitles();
    if (!mounted) return null;
    subtitleController.clearSpeechEnhancements();
    subtitleController.setPrimaryTrack(track);
    subtitleController.setCurrentPrimaryCue(
      subtitleController.primaryCursor.current(playerController.position),
    );
    setState(() => status = nextStatus);
    await _loadWordEntries();
    await _loadPhraseEntries();
    await _loadPhraseCandidates(subtitleController.currentPrimaryCue);
    return _loadSpeechEnhancements(track.id);
  }

  String? _llTimelineMediaFingerprint(Map<String, dynamic> document) {
    final metadata = document['metadata'];
    if (metadata is! Map<String, dynamic>) return null;
    final media = metadata['media'];
    if (media is! Map<String, dynamic>) return null;
    final fingerprint = media['fingerprint'];
    return fingerprint is String && fingerprint.trim().isNotEmpty
        ? fingerprint
        : null;
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

  Future<void> _loadGeneratedTrack(
    Map<String, dynamic> value,
    bool secondary,
  ) async {
    await adapter.disableNativeSubtitles();
    if (!mounted) return;
    final imported = SubtitleTrack.fromJson(value);
    if (secondary) {
      subtitleController.setSecondaryTrack(imported);
      subtitleController.setCurrentSecondaryCue(
        subtitleController.secondaryCursor.current(playerController.position),
      );
      setState(() {
        status = l.text('generatedSecondarySubtitleLoaded');
      });
    } else {
      final result = await _usePrimarySubtitleTrack(
        imported,
        nextStatus: l.text('loadingGeneratedPrimarySubtitle'),
      );
      if (mounted && subtitleController.primaryTrack?.id == imported.id) {
        setState(() => status = _generatedPrimarySubtitleStatus(result));
      }
    }
    await _loadSubtitleResources(updateStatus: false);
  }

  Future<SpeechEnhancementLoadResult?> _loadSpeechEnhancements(
    String trackId,
  ) async {
    final service = api;
    if (service == null) return null;
    final result = await speechEnhancementWorkflowController
        .loadSpeechEnhancements(
          service: service,
          trackId: trackId,
          previousTimeline: _existingTimelineResourceState(),
        );
    if (!mounted || subtitleController.primaryTrack?.id != trackId) {
      return null;
    }
    _applyTimelineResource(result.timeline);
    subtitleController.setSpeechEnhancements(
      timingsBySentence: result.timingsBySentence,
      chunkPartitionsBySentence: result.chunkPartitionsBySentence,
      pronunciationBySentence: result.pronunciationBySentence,
      pronunciationProviders: result.pronunciationProviders,
      phoneticAnalysisBySentence: result.phoneticAnalysisBySentence,
    );
    subtitleController.updateCurrentWord(
      playerController.position,
      enabled: settingsController.wordSyncVisible,
      chunkEnabled:
          settingsController.showChunkGrouping &&
          settingsController.highlightCurrentChunk,
    );
    subtitleController.updateCurrentDetectedPhone(
      playerController.position,
      enabled:
          settingsController.settings.phonemeRibbonVisible ||
          settingsController.settings.soundPatternRibbonVisible,
    );
    if (result.errors.isNotEmpty && mounted) {
      setState(
        () => status =
            'Speech enhancements partially unavailable: '
            '${result.errors.join('; ')}',
      );
    }
    return result;
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
        activeWordTimingCount: _activeWordTimingCount(),
        timelineResourceError: subtitleController.timelineResourceError,
      );

  int _activeWordTimingCount() => subtitleController.timingsBySentence.values
      .fold<int>(0, (total, timings) => total + timings.length);

  String _capabilityStatusSegment(CapabilityReadiness readiness) =>
      '${l.text(readiness.titleKey)}: ${l.text(readiness.stateKey)}';

  Future<void> _loadTimelineResource(String trackId) async {
    final service = api;
    if (service == null) return;
    final result = await speechEnhancementWorkflowController
        .loadTimelineResource(
          service: service,
          trackId: trackId,
          previous: _existingTimelineResourceState(),
        );
    if (!mounted || subtitleController.primaryTrack?.id != trackId) return;
    _applyTimelineResource(result);
  }

  ExistingTimelineResourceState _existingTimelineResourceState() =>
      ExistingTimelineResourceState(
        wordSummaries: subtitleController.wordTimelineSummaries,
        phoneSummaries: subtitleController.phoneTimelineSummaries,
        chunkSummaries: subtitleController.chunkTimelineSummaries,
        document: subtitleController.llTimelineDocument,
      );

  void _applyTimelineResource(TimelineResourceLoadResult result) {
    if (result.unavailable) {
      subtitleController.setTimelineResourceError(result.error ?? '');
      return;
    }
    subtitleController.setTimelineResource(
      summaries: result.wordSummaries,
      phoneSummaries: result.phoneSummaries,
      chunkSummaries: result.chunkSummaries,
      document: result.document,
      error: result.error,
    );
  }

  Future<void> _refreshTimelineResource() async {
    final trackId = subtitleController.primaryTrack?.id;
    if (trackId == null) return;
    await _loadTimelineResource(trackId);
    if (mounted) setState(() => status = 'Timeline resource refreshed');
  }

  Future<void> _loadSubtitleResources({bool updateStatus = true}) async {
    final service = api;
    final mediaId = playerController.mediaId;
    if (service == null || mediaId == null) {
      subtitleController.setSubtitleResources(const []);
      subtitleController.setSubtitleResourceCapabilities(const {});
      return;
    }
    try {
      final values = await service.mediaSubtitles(mediaId);
      final tracks = values
          .map((raw) => SubtitleTrack.fromJson(raw))
          .toList(growable: false);
      final capabilities = await _loadSubtitleResourceCapabilities(
        service,
        tracks,
      );
      if (!mounted || playerController.mediaId != mediaId) return;
      subtitleController.setSubtitleResources(tracks);
      subtitleController.setSubtitleResourceCapabilities(capabilities);
      if (updateStatus) setState(() => status = 'Subtitle resources refreshed');
    } catch (error) {
      if (mounted && updateStatus) {
        setState(() => status = 'Subtitle resources unavailable: $error');
      }
    }
  }

  Future<Map<String, SubtitleResourceCapabilities>>
  _loadSubtitleResourceCapabilities(
    LocalApi service,
    List<SubtitleTrack> tracks,
  ) async {
    final entries = await Future.wait(
      tracks.map((track) async {
        final errors = <String>[];
        final wordTimings = await _loadOptionalResourceCapability(
          () => service.trackWordTimings(track.id),
          'word',
          errors,
        );
        final phoneSummaries = await _loadOptionalResourceCapability(
          () => service.trackPhoneTimelineSummaries(track.id),
          'phone timeline',
          errors,
        );
        final chunkSummaries = await _loadOptionalResourceCapability(
          () => service.trackChunkTimelineSummaries(track.id),
          'chunk timeline',
          errors,
        );
        return MapEntry(
          track.id,
          SubtitleResourceCapabilities.fromCounts(
            sentenceCount: track.cues.length,
            wordTimingCount: wordTimings.length,
            chunkCount: chunkSummaries.fold<int>(
              0,
              (total, raw) => total + (raw['chunk_count'] as int? ?? 0),
            ),
            phoneCount: phoneSummaries.fold<int>(
              0,
              (total, raw) => total + (raw['phone_count'] as int? ?? 0),
            ),
            error: errors.isEmpty ? null : errors.join('; '),
          ),
        );
      }),
    );
    return Map<String, SubtitleResourceCapabilities>.fromEntries(entries);
  }

  Future<List<Map<String, dynamic>>> _loadOptionalResourceCapability(
    Future<List<Map<String, dynamic>>> Function() loader,
    String label,
    List<String> errors,
  ) async {
    try {
      return await loader();
    } catch (error) {
      errors.add('$label: $error');
      return const [];
    }
  }

  Future<void> _refreshSubtitleResources() async {
    await _loadSubtitleResources();
    await _refreshTimelineResource();
  }

  Future<void> _activateSubtitleResource(SubtitleTrack track) async {
    try {
      await _usePrimarySubtitleTrack(
        track,
        nextStatus: 'Activated subtitle resource',
      );
      await _loadSubtitleResources(updateStatus: false);
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Subtitle activation failed: $error');
      }
    }
  }

  Future<void> _archiveSubtitleResource(SubtitleTrack track) async {
    final service = api;
    if (service == null) return;
    try {
      await service.archiveSubtitle(track.id);
      if (subtitleController.primaryTrack?.id == track.id) {
        subtitleController.setPrimaryTrack(null);
        subtitleController.setCurrentPrimaryCue(null);
        subtitleController.clearSpeechEnhancements();
      }
      await _loadSubtitleResources(updateStatus: false);
      if (mounted) setState(() => status = 'Archived subtitle resource');
    } catch (error) {
      if (mounted) setState(() => status = 'Subtitle archive failed: $error');
    }
  }

  Future<void> _restoreSubtitleResource(SubtitleTrack track) async {
    final service = api;
    if (service == null) return;
    try {
      await service.restoreSubtitle(track.id);
      await _loadSubtitleResources(updateStatus: false);
      if (mounted) setState(() => status = 'Restored subtitle resource');
    } catch (error) {
      if (mounted) setState(() => status = 'Subtitle restore failed: $error');
    }
  }

  Future<void> _deleteSubtitleResource(SubtitleTrack track) async {
    final service = api;
    if (service == null) return;
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
    try {
      await service.deleteSubtitle(track.id);
      if (subtitleController.primaryTrack?.id == track.id) {
        subtitleController.setPrimaryTrack(null);
        subtitleController.setCurrentPrimaryCue(null);
        subtitleController.clearSpeechEnhancements();
      }
      await _loadSubtitleResources(updateStatus: false);
      if (mounted) setState(() => status = 'Deleted subtitle resource');
    } catch (error) {
      if (mounted) setState(() => status = 'Subtitle delete failed: $error');
    }
  }

  Future<void> _exportSubtitleResource(SubtitleTrack track) async {
    final service = api;
    if (service == null) return;
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
    try {
      if (format == 'lltimeline') {
        await _exportLLTimelineResource(track);
      } else {
        final location = await getSaveLocation(
          suggestedName: '${track.source}-${track.id}.srt',
        );
        if (location == null) return;
        final srt = await service.exportSubtitleSrt(track.id);
        await File(location.path).writeAsString(srt);
        if (mounted) setState(() => status = 'Exported SRT subtitle resource');
      }
    } catch (error) {
      if (mounted) setState(() => status = 'Subtitle export failed: $error');
    }
  }

  Future<void> _changeTrackLanguage(
    SubtitleTrack track,
    String language,
  ) async {
    final service = api;
    if (service == null) return;
    try {
      await service.updateTrackLanguage(track.id, language);
      await _loadSubtitleResources(updateStatus: false);
      if (subtitleController.primaryTrack?.id == track.id) {
        final updated = subtitleController.subtitleResources
            .where((t) => t.id == track.id)
            .firstOrNull;
        if (updated != null) {
          subtitleController.setPrimaryTrack(updated);
        }
        await _loadWordEntries();
        await _loadPhraseEntries();
      }
      if (mounted) setState(() => status = 'Language set to $language');
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Failed to update language: $error');
      }
    }
  }

  Future<void> _exportLLTimelineResource(SubtitleTrack track) async {
    final service = api;
    if (service == null) return;
    try {
      final location = await getSaveLocation(
        suggestedName: '${track.source}-${track.id}.lltimeline.json',
      );
      if (location == null) return;
      final document = await service.exportTrackLLTimeline(track.id);
      await File(
        location.path,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(document));
      if (mounted) setState(() => status = 'Exported LLTimeline resource');
    } catch (error) {
      if (mounted) setState(() => status = 'LLTimeline export failed: $error');
    }
  }

  Future<void> _activateWordTimeline(String timelineId) async {
    final service = api;
    final trackId = subtitleController.primaryTrack?.id;
    if (service == null || trackId == null) return;
    try {
      setState(() => status = 'Activating WordTimeline...');
      await service.activateWordTimeline(timelineId);
      if (!mounted || subtitleController.primaryTrack?.id != trackId) return;
      await _loadSpeechEnhancements(trackId);
      if (mounted) setState(() => status = 'WordTimeline activated');
    } catch (error) {
      if (mounted) {
        setState(() => status = 'WordTimeline activation failed: $error');
      }
    }
  }

  Future<void> _generateChunkTimeline() async {
    final service = api;
    final trackId = subtitleController.primaryTrack?.id;
    if (service == null || trackId == null) return;
    try {
      setState(() => status = 'Generating ChunkTimeline...');
      await service.generateChunkTimeline(trackId, status: 'active');
      if (!mounted || subtitleController.primaryTrack?.id != trackId) return;
      await _loadSpeechEnhancements(trackId);
      await _loadSubtitleResources(updateStatus: false);
      if (mounted) setState(() => status = 'ChunkTimeline generated');
    } catch (error) {
      if (mounted) {
        setState(() => status = 'ChunkTimeline generation failed: $error');
      }
    }
  }

  Future<void> _activateChunkTimeline(String timelineId) async {
    final service = api;
    final trackId = subtitleController.primaryTrack?.id;
    if (service == null || trackId == null) return;
    try {
      setState(() => status = 'Activating ChunkTimeline...');
      await service.activateChunkTimeline(timelineId);
      if (!mounted || subtitleController.primaryTrack?.id != trackId) return;
      await _loadSpeechEnhancements(trackId);
      await _loadSubtitleResources(updateStatus: false);
      if (mounted) setState(() => status = 'ChunkTimeline activated');
    } catch (error) {
      if (mounted) {
        setState(() => status = 'ChunkTimeline activation failed: $error');
      }
    }
  }

  Future<void> _archiveChunkTimeline(String timelineId) async {
    final service = api;
    final trackId = subtitleController.primaryTrack?.id;
    if (service == null || trackId == null) return;
    try {
      await service.archiveChunkTimeline(timelineId);
      if (!mounted || subtitleController.primaryTrack?.id != trackId) return;
      await _loadSpeechEnhancements(trackId);
      await _loadSubtitleResources(updateStatus: false);
      if (mounted) setState(() => status = 'ChunkTimeline archived');
    } catch (error) {
      if (mounted) {
        setState(() => status = 'ChunkTimeline archive failed: $error');
      }
    }
  }

  Future<void> _deleteChunkTimeline(String timelineId) async {
    final service = api;
    final trackId = subtitleController.primaryTrack?.id;
    if (service == null || trackId == null) return;
    try {
      await service.deleteChunkTimeline(timelineId);
      if (!mounted || subtitleController.primaryTrack?.id != trackId) return;
      await _loadSpeechEnhancements(trackId);
      await _loadSubtitleResources(updateStatus: false);
      if (mounted) setState(() => status = 'ChunkTimeline deleted');
    } catch (error) {
      if (mounted) {
        setState(() => status = 'ChunkTimeline delete failed: $error');
      }
    }
  }

  Future<void> _activatePhoneTimeline(String timelineId) async {
    final service = api;
    final trackId = subtitleController.primaryTrack?.id;
    if (service == null || trackId == null) return;
    try {
      setState(() => status = 'Activating PhoneTimeline...');
      await service.activatePhoneTimeline(timelineId);
      if (!mounted || subtitleController.primaryTrack?.id != trackId) return;
      await _loadSpeechEnhancements(trackId);
      await _loadSubtitleResources(updateStatus: false);
      if (mounted) setState(() => status = 'PhoneTimeline activated');
    } catch (error) {
      if (mounted) {
        setState(() => status = 'PhoneTimeline activation failed: $error');
      }
    }
  }

  Future<void> _archivePhoneTimeline(String timelineId) async {
    final service = api;
    final trackId = subtitleController.primaryTrack?.id;
    if (service == null || trackId == null) return;
    try {
      await service.archivePhoneTimeline(timelineId);
      if (!mounted || subtitleController.primaryTrack?.id != trackId) return;
      await _loadSpeechEnhancements(trackId);
      await _loadSubtitleResources(updateStatus: false);
      if (mounted) setState(() => status = 'PhoneTimeline archived');
    } catch (error) {
      if (mounted) {
        setState(() => status = 'PhoneTimeline archive failed: $error');
      }
    }
  }

  Future<void> _deletePhoneTimeline(String timelineId) async {
    final service = api;
    final trackId = subtitleController.primaryTrack?.id;
    if (service == null || trackId == null) return;
    try {
      await service.deletePhoneTimeline(timelineId);
      if (!mounted || subtitleController.primaryTrack?.id != trackId) return;
      await _loadSpeechEnhancements(trackId);
      await _loadSubtitleResources(updateStatus: false);
      if (mounted) setState(() => status = 'PhoneTimeline deleted');
    } catch (error) {
      if (mounted) {
        setState(() => status = 'PhoneTimeline delete failed: $error');
      }
    }
  }

  Future<void> _openManualReviewTimeline() async {
    final service = api;
    final track = subtitleController.primaryTrack;
    if (service == null || track == null) return;
    try {
      setState(() {
        status = 'Loading manual review timeline...';
        _manualReviewStatusPristine = true;
      });
      await _loadTimelineResource(track.id);
      final active = subtitleController.wordTimelineSummaries
          .where((summary) => summary.isActive)
          .firstOrNull;
      final activeTimelineId =
          active?.id ??
          subtitleController.llTimelineDocument?.activeWordTimelineId;
      if (activeTimelineId == null) {
        if (mounted) {
          setState(() => status = 'No active WordTimeline to review');
        }
        return;
      }
      final timeline = WordTimeline.fromJson(
        await service.wordTimeline(activeTimelineId),
      );
      final initialCue = _manualReviewInitialCue(track, timeline);
      if (initialCue == null) {
        if (mounted) setState(() => status = 'No sentence words to review');
        return;
      }
      final draft = ManualReviewDraft(
        track: track,
        sourceTimeline: timeline,
        words: timeline.words,
        initialCue: initialCue,
      );
      if (!mounted) return;
      final previousLoopStart = playerController.sourceLoopStart;
      final previousLoopEnd = playerController.sourceLoopEnd;
      try {
        await showDialog<void>(
          context: context,
          builder: (_) => ManualTimelineReviewDialog(
            draft: draft,
            onPlayRange: _playManualReviewRange,
            onSave: _saveManualReviewDraft,
          ),
        );
      } finally {
        playerController.setSourceLoop(previousLoopStart, previousLoopEnd);
      }
      if (mounted && _manualReviewStatusPristine) {
        setState(() => status = 'Manual review closed');
      }
    } catch (error) {
      if (mounted) setState(() => status = 'Manual review failed: $error');
    }
  }

  Cue? _manualReviewInitialCue(SubtitleTrack track, WordTimeline timeline) {
    final sentenceIds = timeline.words.map((word) => word.sentenceId).toSet();
    final current = subtitleController.currentPrimaryCue;
    if (current != null && sentenceIds.contains(current.id)) return current;
    for (final cue in track.cues) {
      if (sentenceIds.contains(cue.id)) return cue;
    }
    return null;
  }

  Future<void> _playManualReviewRange(Duration start, Duration end) async {
    if (end <= start) return;
    playerController.setSourceLoop(start, end);
    subtitleController.setLoopCue(false);
    await adapter.seek(start);
    await adapter.play();
  }

  Future<void> _saveManualReviewDraft(ManualReviewDraft draft) async {
    final service = api;
    final trackId = subtitleController.primaryTrack?.id;
    if (service == null || trackId == null) return;
    final errors = draft.validateAll();
    if (errors.isNotEmpty) {
      throw StateError(errors.join('; '));
    }
    setState(() {
      status = 'Saving manual review timeline...';
      _manualReviewStatusPristine = false;
    });
    await service.createTrackWordTimeline(trackId, draft.createPayload());
    if (!mounted || subtitleController.primaryTrack?.id != trackId) return;
    await _loadSpeechEnhancements(trackId);
    if (mounted) setState(() => status = 'Manual review timeline saved');
  }

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
      setState(() => status = 'Open media and connect the local core first');
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
      setState(() {
        taskStatuses[UserTaskKind.subtitleGeneration] = UserTaskStatus(
          kind: UserTaskKind.subtitleGeneration,
          state: UserTaskState.working,
          rawStatus: 'queued',
          progress: 0,
          targetId: playerController.mediaId,
        );
        status = secondary
            ? l.text('secondarySubtitleGenerationStarted')
            : l.text('primarySubtitleGenerationStarted');
      });
    }
  }

  Future<void> _openTranscriptionCenter() async {
    if (api == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            TranscriptionCenter(api: api!, loadTrack: _loadGeneratedTrack),
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
    if (media.isNotEmpty) await _openMediaPath(media.first);
    for (final path in subtitles) {
      if (playerController.mediaId == null || api == null) {
        setState(() => status = 'Drop or open media before subtitles');
        return;
      }
      await _openSubtitlePath(
        path,
        secondary: subtitleController.primaryTrack != null,
      );
    }
    if (media.isEmpty && subtitles.isEmpty) {
      setState(() => status = 'Unsupported dropped file type');
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

  Future<void> _openOnline() async {
    final controller = TextEditingController();
    final pageUrl = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('openOnlineTitle')),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l.text('pageUrl'),
              helperText: 'Only open content you are authorized to access.',
            ),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.text('cancel')),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(context, 'download:$value');
            },
            icon: const Icon(Icons.download),
            label: Text(l.text('downloadVideo')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l.text('resolvePlay')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pageUrl == null || pageUrl.isEmpty) return;
    if (pageUrl.startsWith('download:')) {
      await _downloadOnline(pageUrl.substring('download:'.length));
      return;
    }
    setState(() => status = 'Resolving online media...');
    try {
      final resolved = await tools.resolveOnlineMedia(pageUrl);
      await adapter.open(resolved);
      playerController.clearMedia();
      playerController.setMediaPath(pageUrl);
      subtitleController.setPrimaryTrack(null);
      subtitleController.setSecondaryTrack(null);
      subtitleController.setCurrentPrimaryCue(null);
      subtitleController.setCurrentSecondaryCue(null);
      subtitleController.clearSpeechEnhancements();
      subtitleController.setCurrentPrimaryCue(null);
      subtitleController.setCurrentSecondaryCue(null);
      setState(() {
        taskStatuses.clear();
        status = 'Playing online media';
      });
    } catch (error) {
      setState(() => status = 'Online media failed: $error');
    }
  }

  Future<void> _downloadOnline(String pageUrl) async {
    final directory = await getDirectoryPath(
      confirmButtonText: l.text('downloadHere'),
    );
    if (directory == null) return;
    downloadController.starting();
    setState(() => status = l.text('startingDownload'));
    try {
      final download = await tools.downloadOnlineMedia(pageUrl, directory);
      if (!mounted) {
        download.cancel();
        return;
      }
      downloadController.attach(
        progress: download.progress,
        completed: download.completed,
        cancel: download.cancel,
        onCompleted: (path) =>
            setState(() => status = '${l.text('downloadComplete')}: $path'),
        onFailed: (error) =>
            setState(() => status = '${l.text('downloadFailed')}: $error'),
      );
      setState(() => status = l.text('downloadingInBackground'));
    } catch (error) {
      if (mounted) {
        downloadController.fail(error.toString());
        setState(() => status = '${l.text('downloadFailed')}: $error');
      }
    }
  }

  Future<void> _importEmbeddedSubtitle() async {
    final path = playerController.mediaPath;
    if (path == null ||
        !_isMediaPath(path) ||
        playerController.mediaId == null ||
        api == null) {
      setState(() => status = 'Open a local media file first');
      return;
    }
    setState(() => status = 'Inspecting embedded subtitles...');
    try {
      final subtitles = await tools.probeSubtitles(path);
      if (!mounted) return;
      if (subtitles.isEmpty) {
        setState(() => status = 'No embedded subtitles found');
        return;
      }
      final choice = await showDialog<(EmbeddedSubtitle, bool)>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(l.text('importEmbeddedText')),
          children: [
            for (final subtitle in subtitles)
              ListTile(
                enabled: subtitle.isText,
                title: Text(subtitle.label),
                subtitle: Text(
                  subtitle.isText
                      ? 'Import as an interactive learning subtitle'
                      : 'Bitmap subtitle: learning interaction is deferred',
                ),
                trailing: subtitle.isText
                    ? PopupMenuButton<bool>(
                        onSelected: (secondary) =>
                            Navigator.pop(context, (subtitle, secondary)),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: false,
                            child: Text(l.text('usePrimary')),
                          ),
                          PopupMenuItem(
                            value: true,
                            child: Text(l.text('useSecondary')),
                          ),
                        ],
                      )
                    : null,
              ),
          ],
        ),
      );
      if (choice == null) {
        setState(() => status = 'Embedded subtitle import cancelled');
        return;
      }
      setState(() => status = 'Extracting embedded text subtitle...');
      final extracted = await tools.extractTextSubtitle(path, choice.$1);
      await _openSubtitlePath(extracted, secondary: choice.$2);
    } catch (error) {
      setState(() => status = 'Embedded subtitle import failed: $error');
    }
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(
        language: settingsController.language,
        subtitlePreset: subtitleController.preset,
        primaryFontSize: subtitleController.primaryFontSize,
        primaryFontFamily: subtitleController.primaryFontFamily,
        secondaryFontSize: subtitleController.secondaryFontSize,
        secondaryFontFamily: subtitleController.secondaryFontFamily,
        subtitlePositionX: subtitleController.positionX,
        subtitlePositionY: subtitleController.positionY,
        subtitleBackgroundOpacity: subtitleController.backgroundOpacity,
        transcriptWidth: settingsController.transcriptWidth,
        primaryColor: settingsController.primaryColor,
        secondaryColor: settingsController.secondaryColor,
        transcriptionQuality: settingsController.transcriptionQuality,
        transcriptionLanguage: settingsController.transcriptionLanguage,
        transcriptionDestination: settingsController.transcriptionDestination,
        ffmpegPath: settingsController.ffmpegPath,
        ffprobePath: settingsController.ffprobePath,
        ytDlpPath: settingsController.ytDlpPath,
        openSubtitlesApiKey: settingsController.openSubtitlesApiKey,
        wordSyncVisible: settingsController.wordSyncVisible,
        showChunkGrouping: settingsController.showChunkGrouping,
        chunkDisplayStyle: settingsController.chunkDisplayStyle,
        highlightCurrentChunk: settingsController.highlightCurrentChunk,
        chunkHighlightStyle: settingsController.chunkHighlightStyle,
        wordHighlightStyle: settingsController.wordHighlightStyle,
        wordAnimationIntensity: settingsController.wordAnimationIntensity,
        ruleHintsLevel: settingsController.ruleHintsLevel,
        phoneticAnalysisPreference:
            settingsController.phoneticAnalysisPreference,
        phonemeRibbonVisible: settingsController.phonemeRibbonVisible,
        soundPatternRibbonVisible: settingsController.soundPatternRibbonVisible,
        soundPatternDisplayMode: settingsController.soundPatternDisplayMode,
        phonemeRibbonStyle: settingsController.phonemeRibbonStyle,
        learningLanguage: settingsController.learningLanguage,
        availableLanguages: learningController.availableLanguages,
        onLearningLanguageChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(learningLanguage: v),
          );
        },
        onLanguageChanged: (v) {
          appLanguage.value = v;
          settingsController.update(
            settingsController.settings.copyWith(language: v),
          );
        },
        onSubtitlePresetChanged: (v) {
          subtitleController.setPreset(v);
          unawaited(_saveSettings());
        },
        onPrimaryFontSizeChanged: (v) {
          subtitleController.setPrimaryFontSize(v);
          unawaited(_saveSettings());
        },
        onPrimaryFontFamilyChanged: (v) {
          subtitleController.setPrimaryFontFamily(v);
          unawaited(_saveSettings());
        },
        onSecondaryFontSizeChanged: (v) {
          subtitleController.setSecondaryFontSize(v);
          unawaited(_saveSettings());
        },
        onSecondaryFontFamilyChanged: (v) {
          subtitleController.setSecondaryFontFamily(v);
          unawaited(_saveSettings());
        },
        onSubtitlePositionXChanged: (v) {
          subtitleController.setPositionX(v);
          unawaited(_saveSettings());
        },
        onSubtitlePositionYChanged: (v) {
          subtitleController.setPositionY(v);
          unawaited(_saveSettings());
        },
        onSubtitlePositionReset: () {
          subtitleController.setPositionX(0.5);
          subtitleController.setPositionY(0.82);
          unawaited(_saveSettings());
        },
        onBackgroundOpacityChanged: (v) {
          subtitleController.setBackgroundOpacity(v);
          unawaited(_saveSettings());
        },
        onTranscriptWidthChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(transcriptWidth: v),
          );
        },
        onPrimaryColorChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(primaryColor: v.toARGB32()),
          );
        },
        onSecondaryColorChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(secondaryColor: v.toARGB32()),
          );
        },
        onTranscriptionQualityChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(transcriptionQuality: v),
          );
        },
        onTranscriptionLanguageChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(transcriptionLanguage: v),
          );
        },
        onTranscriptionDestinationChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(transcriptionDestination: v),
          );
        },
        onWordSyncVisibleChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(wordSyncVisible: v),
          );
          subtitleController.updateCurrentWord(
            playerController.position,
            enabled: v,
            chunkEnabled:
                settingsController.showChunkGrouping &&
                settingsController.highlightCurrentChunk,
          );
        },
        onShowChunkGroupingChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(showChunkGrouping: v),
          );
          subtitleController.updateCurrentWord(
            playerController.position,
            enabled: settingsController.wordSyncVisible,
            chunkEnabled: v && settingsController.highlightCurrentChunk,
          );
        },
        onChunkDisplayStyleChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(chunkDisplayStyle: v),
          );
        },
        onHighlightCurrentChunkChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(highlightCurrentChunk: v),
          );
          subtitleController.updateCurrentWord(
            playerController.position,
            enabled: settingsController.wordSyncVisible,
            chunkEnabled: settingsController.showChunkGrouping && v,
          );
        },
        onChunkHighlightStyleChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(chunkHighlightStyle: v),
          );
        },
        onWordHighlightStyleChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(wordHighlightStyle: v),
          );
        },
        onWordAnimationIntensityChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(wordAnimationIntensity: v),
          );
        },
        onRuleHintsLevelChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(ruleHintsLevel: v),
          );
        },
        onPhoneticAnalysisPreferenceChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(phoneticAnalysisPreference: v),
          );
        },
        onPhonemeRibbonStyleChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(phonemeRibbonStyle: v),
          );
        },
        onPhonemeRibbonVisibleChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(
              phonemeRibbonVisible: v,
              phonemeHighlightVisible:
                  v || settingsController.settings.soundPatternRibbonVisible,
            ),
          );
          subtitleController.updateCurrentDetectedPhone(
            playerController.position,
            enabled: v || settingsController.settings.soundPatternRibbonVisible,
          );
        },
        onSoundPatternRibbonVisibleChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(
              soundPatternRibbonVisible: v,
              phonemeHighlightVisible:
                  v || settingsController.settings.phonemeRibbonVisible,
            ),
          );
          subtitleController.updateCurrentDetectedPhone(
            playerController.position,
            enabled: v || settingsController.settings.phonemeRibbonVisible,
          );
        },
        onSoundPatternDisplayModeChanged: (v) {
          settingsController.update(
            settingsController.settings.copyWith(soundPatternDisplayMode: v),
          );
        },
        onSave:
            ({
              required String ffmpegPath,
              required String ffprobePath,
              required String ytDlpPath,
              required String openSubtitlesApiKey,
            }) async {
              await settingsController.update(
                settingsController.settings.copyWith(
                  ffmpegPath: ffmpegPath,
                  ffprobePath: ffprobePath,
                  ytDlpPath: ytDlpPath,
                  openSubtitlesApiKey: openSubtitlesApiKey,
                ),
              );
            },
      ),
    );
  }

  Future<void> _openLearningAssets() async {
    if (api == null) return;
    final occurrence = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) =>
            LearningAssetsScreen(api: api!, language: _learningLanguage),
      ),
    );
    if (occurrence != null) await _playOccurrence(occurrence);
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
      setState(() {
        status = 'Saved phrase "${candidate.displayForm}"';
      });
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
    if (mounted) setState(() => status = l.text('lemmaCorrectionSaved'));
  }

  Future<void> _searchOpenSubtitles({bool? secondary}) async {
    if (api == null) return;
    if (playerController.mediaId == null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.text('openSubtitles')),
          content: Text(l.text('openMediaForSubtitles')),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.text('close')),
            ),
          ],
        ),
      );
      return;
    }
    if (settingsController.openSubtitlesApiKey.isEmpty) {
      final controller = TextEditingController();
      final configured = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.text('openSubtitles')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.text('configureOpenSubtitlesNow')),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l.text('openSubtitlesApiKey'),
                ),
              ),
            ],
          ),
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
      if (configured == null || configured.isEmpty) return;
      await settingsController.update(
        settingsController.settings.copyWith(openSubtitlesApiKey: configured),
      );
    }
    if (!mounted) return;
    final path = await showOpenSubtitlesSearch(
      context: context,
      api: api!,
      apiKey: settingsController.openSubtitlesApiKey,
      initialTitle: playerController.mediaTitle ?? '',
      initialFilename: playerController.mediaPath == null
          ? ''
          : playerController.mediaPath!.split(Platform.pathSeparator).last,
      mediaPath: playerController.mediaPath,
    );
    if (path == null || !mounted) return;
    final destination =
        secondary ??
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.text('openSubtitles')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.text('usePrimary')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.text('useSecondary')),
              ),
            ],
          ),
        );
    if (destination != null) {
      await _openSubtitlePath(path, secondary: destination);
    }
  }

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
      setState(() => status = 'No core log is available yet');
      return;
    }
    final location = await getSaveLocation(
      suggestedName: 'LLPlayerNext-core.log',
    );
    if (location == null) return;
    await File(source).copy(location.path);
    setState(() => status = 'Exported diagnostics to ${location.path}');
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
      if (mounted) setState(() => status = 'Dictionary unavailable: $error');
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
        setState(() {
          status = 'Updated global status for "${update.tokenText}"';
        });
      }
      await _refreshDiagnosis();
    } catch (error) {
      if (mounted) setState(() => status = 'Word update failed: $error');
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
      setState(() => status = heard ? l.text('heard') : l.text('notHeard'));
    }
    await _refreshDiagnosis();
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
          onExport: _exportVocabulary,
          onImport: _importVocabulary,
        ),
      ),
    );
    if (occurrence == null) return;
    final expectedFingerprint =
        occurrence['media_fingerprint_snapshot'] as String;
    if (expectedFingerprint != playerController.mediaFingerprint) {
      String? sourcePath;
      final linkedMediaId = occurrence['media_id'] as String?;
      if (linkedMediaId != null) {
        try {
          final linkedMedia = await api!.readMedia(linkedMediaId);
          final linkedPath = linkedMedia['path'] as String;
          if (await File(linkedPath).exists()) sourcePath = linkedPath;
        } catch (_) {
          sourcePath = null;
        }
      }
      if (sourcePath == null) {
        const group = XTypeGroup(
          label: 'source media',
          extensions: [
            'mp4',
            'mkv',
            'mov',
            'webm',
            'm4a',
            'mp3',
            'wav',
            'flac',
          ],
        );
        final file = await openFile(acceptedTypeGroups: [group]);
        if (file == null) return;
        final fingerprint = await api!.fingerprintFile(file.path);
        if (fingerprint != expectedFingerprint) {
          setState(
            () =>
                status = 'Selected file does not match the source fingerprint',
          );
          return;
        }
        await api!.registerMedia(file.path);
        sourcePath = file.path;
      }
      await _openMediaPath(sourcePath);
    }
    final start = Duration(
      milliseconds: occurrence['start_ms_snapshot'] as int,
    );
    final end = Duration(milliseconds: occurrence['end_ms_snapshot'] as int);
    setState(() {
      status = 'Looping vocabulary source sentence';
    });
    playerController.setSourceLoop(start, end);
    subtitleController.setLoopCue(false);
    await adapter.seek(start);
    await adapter.play();
  }

  Future<void> _openSubtitleResources() async {
    if (api == null) return;
    await _loadSubtitleResources(updateStatus: false);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SubtitleResourcesScreen(
          playerController: playerController,
          subtitleController: subtitleController,
          onImportSubtitle: () => _openSubtitle(secondary: false),
          onImportLLTimeline: _openLLTimelineResource,
          onRefreshResources: _refreshSubtitleResources,
          onActivateSubtitle: _activateSubtitleResource,
          onArchiveSubtitle: _archiveSubtitleResource,
          onRestoreSubtitle: _restoreSubtitleResource,
          onDeleteSubtitle: _deleteSubtitleResource,
          onExportSubtitle: _exportSubtitleResource,
          onLanguageChanged: _changeTrackLanguage,
          availableLanguages: learningController.availableLanguages,
          onExportLLTimeline: _exportLLTimelineResource,
          onActivateWordTimeline: _activateWordTimeline,
          onManualReviewTimeline: _openManualReviewTimeline,
          onActivatePhoneTimeline: _activatePhoneTimeline,
          onArchivePhoneTimeline: _archivePhoneTimeline,
          onDeletePhoneTimeline: _deletePhoneTimeline,
          onGenerateChunkTimeline: _generateChunkTimeline,
          onActivateChunkTimeline: _activateChunkTimeline,
          onArchiveChunkTimeline: _archiveChunkTimeline,
          onDeleteChunkTimeline: _deleteChunkTimeline,
        ),
      ),
    );
  }

  Future<void> _playOccurrence(Map<String, dynamic> occurrence) async {
    final expectedFingerprint =
        occurrence['media_fingerprint_snapshot'] as String;
    if (expectedFingerprint != playerController.mediaFingerprint) {
      String? sourcePath;
      final linkedMediaId = occurrence['media_id'] as String?;
      if (linkedMediaId != null) {
        try {
          final linkedMedia = await api!.readMedia(linkedMediaId);
          final linkedPath = linkedMedia['path'] as String;
          if (await File(linkedPath).exists()) sourcePath = linkedPath;
        } catch (_) {
          sourcePath = null;
        }
      }
      if (sourcePath == null) {
        const group = XTypeGroup(label: 'source media');
        final file = await openFile(acceptedTypeGroups: [group]);
        if (file == null) return;
        if (await api!.fingerprintFile(file.path) != expectedFingerprint) {
          setState(
            () =>
                status = 'Selected file does not match the source fingerprint',
          );
          return;
        }
        await api!.registerMedia(file.path);
        sourcePath = file.path;
      }
      await _openMediaPath(sourcePath);
    }
    final start = Duration(
      milliseconds: occurrence['start_ms_snapshot'] as int,
    );
    final end = Duration(milliseconds: occurrence['end_ms_snapshot'] as int);
    playerController.setSourceLoop(start, end);
    subtitleController.setLoopCue(false);
    await adapter.seek(start);
    await adapter.play();
  }

  Future<void> _loopPhoneticRange(int startMs, int endMs, String label) async {
    final start = Duration(milliseconds: startMs);
    final end = Duration(milliseconds: endMs);
    if (start >= end) return;
    playerController.setSourceLoop(start, end);
    subtitleController.setLoopCue(false);
    if (mounted) setState(() => status = label);
    await adapter.seek(start);
    await adapter.play();
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
    await _loopPhoneticRange(start, end, 'Looping sound-line evidence');
  }

  Future<void> _loopRhythmCue(
    Duration start,
    Duration end,
    String label,
  ) async {
    await _loopPhoneticRange(
      start.inMilliseconds,
      end.inMilliseconds,
      'Looping listening rhythm: $label',
    );
  }

  Future<void> _setSoundPatternDisplayMode(String mode) async {
    if (settingsController.soundPatternDisplayMode == mode) return;
    if (mode != 'actual' && mounted) {
      setState(() => _phoneEvidenceExpanded = false);
    }
    await settingsController.update(
      settingsController.settings.copyWith(soundPatternDisplayMode: mode),
    );
  }

  Future<void> _savePhoneticFindingFeedback(
    PhoneticFinding finding,
    String value,
  ) async {
    final service = api;
    if (service == null) return;
    try {
      await service.updatePhoneticFindingFeedback(
        findingId: finding.id,
        value: value,
      );
      if (mounted) {
        setState(() => status = 'Audio finding feedback saved: $value');
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => status = 'Could not save audio finding feedback: $error',
        );
      }
    }
  }

  Future<void> _exportVocabulary() async {
    final service = api;
    if (service == null) return;
    final location = await getSaveLocation(
      suggestedName: 'LLPlayerNext-vocabulary-v1.json',
    );
    if (location == null) return;
    final bundle = await service.exportVocabulary();
    await File(
      location.path,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(bundle));
    setState(() => status = 'Exported vocabulary assets');
  }

  Future<void> _importVocabulary() async {
    final service = api;
    if (service == null) return;
    const group = XTypeGroup(label: 'JSON', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    final bundle =
        jsonDecode(await File(file.path).readAsString())
            as Map<String, dynamic>;
    await service.importVocabulary(bundle);
    await _loadWordEntries();
    await _loadPhraseEntries();
    setState(() => status = 'Imported vocabulary assets');
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
      setState(() => status = error.message);
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
    setState(() => status = 'Imported word list: $result');
  }

  Future<void> _archiveCurrentMedia() async {
    if (api == null || playerController.mediaId == null) return;
    await api!.setMediaAvailability(playerController.mediaId!, 'archived');
    setState(
      () =>
          status = 'Archived current media record; vocabulary assets preserved',
    );
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
        settingsController,
        downloadController,
      ]),
      builder: (context, _) => AppControllers(
        player: playerController,
        subtitle: subtitleController,
        learning: learningController,
        settings: settingsController,
        api: api!,
        child: CallbackShortcuts(
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
                onOpenMedia: _openMedia,
                onOpenOnline: _openOnline,
                onImportPrimarySubtitle: () =>
                    unawaited(_openSubtitle(secondary: false)),
                onGeneratePrimarySubtitles: () =>
                    unawaited(_generateSubtitles(secondary: false)),
                onSearchPrimarySubtitles: () =>
                    unawaited(_searchOpenSubtitles(secondary: false)),
                onImportSecondarySubtitle: () =>
                    unawaited(_openSubtitle(secondary: true)),
                onGenerateSecondarySubtitles: () =>
                    unawaited(_generateSubtitles(secondary: true)),
                onSearchSecondarySubtitles: () =>
                    unawaited(_searchOpenSubtitles(secondary: true)),
                onImportEmbeddedSubtitle: () =>
                    unawaited(_importEmbeddedSubtitle()),
                onOpenSettings: () => unawaited(_openSettings()),
                onExportLogs: () => unawaited(_exportLogs()),
                onExportVocabulary: () => unawaited(_exportVocabulary()),
                onImportVocabulary: () => unawaited(_importVocabulary()),
                onImportWordList: () => unawaited(_importWordList()),
                onArchiveMedia: () => unawaited(_archiveCurrentMedia()),
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
                            Expanded(flex: 3, child: _playerSurface()),
                            if (subtitleController.primaryTrack != null ||
                                learningController.selectedLexicalDetails !=
                                    null ||
                                learningController.sidePanel == 1)
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

  Widget _playerSurface() => LayoutBuilder(
    builder: (context, constraints) {
      final primarySize = responsiveSubtitleSize(
        width: constraints.maxWidth,
        scale: subtitleController.primaryFontSize,
        preset: subtitleController.preset,
        textLength: subtitleController.currentPrimaryCue?.text.length ?? 1,
      );
      final secondarySize = responsiveSubtitleSize(
        width: constraints.maxWidth,
        scale: subtitleController.secondaryFontSize,
        preset: subtitleController.preset,
        textLength: subtitleController.currentSecondaryCue?.text.length ?? 1,
        secondary: true,
      );
      final backgroundFactor = subtitleController.preset == 'watching'
          ? 0.45
          : subtitleController.preset == 'compact'
          ? 0.3
          : 1.0;
      final subtitlePosition = Offset(
        subtitleController.positionX,
        subtitleController.positionY,
      );
      return Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black,
              child: PlayerSurface(adapter: adapter),
            ),
          ),
          if (subtitleController.visible &&
              (subtitleController.currentPrimaryCue != null ||
                  (subtitleController.secondaryVisible &&
                      subtitleController.currentSecondaryCue != null)))
            Align(
              alignment: Alignment(
                subtitlePosition.dx * 2 - 1,
                subtitlePosition.dy * 2 - 1,
              ),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanUpdate: (details) {
                    subtitleController.movePosition(
                      details.delta.dx,
                      details.delta.dy,
                      constraints.biggest.width,
                      constraints.biggest.height,
                    );
                  },
                  onPanEnd: (_) => unawaited(_saveSettings()),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.82,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(
                          alpha:
                              subtitleController.backgroundOpacity *
                              backgroundFactor,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: subtitleController.preset == 'compact'
                              ? 10
                              : 18,
                          vertical: subtitleController.preset == 'compact'
                              ? 6
                              : 12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subtitleController.currentPrimaryCue != null)
                              GestureDetector(
                                onTap: () => _seekCue(
                                  subtitleController.currentPrimaryCue,
                                ),
                                child: TokenLine(
                                  cue: subtitleController.currentPrimaryCue!,
                                  profiles: learningController.wordEntries,
                                  phraseCandidates:
                                      learningController.phraseCandidates,
                                  phraseEntries:
                                      learningController.phraseEntries,
                                  showStyles:
                                      subtitleController.statusStylesVisible,
                                  fontSize: primarySize,
                                  fontFamily: _subtitleFont(
                                    subtitleController.primaryFontFamily,
                                  ),
                                  baseColor: settingsController.primaryColor,
                                  currentTokenIndex:
                                      subtitleController.currentWordToken,
                                  chunkPartition:
                                      settingsController.showChunkGrouping
                                      ? subtitleController
                                            .chunkPartitionsBySentence[subtitleController
                                            .currentPrimaryCue!
                                            .id]
                                      : null,
                                  currentChunkIndex:
                                      settingsController.highlightCurrentChunk
                                      ? subtitleController.currentChunkIndex
                                      : null,
                                  chunkDisplayStyle:
                                      settingsController.chunkDisplayStyle,
                                  chunkHighlightStyle:
                                      settingsController.chunkHighlightStyle,
                                  currentWordStyle:
                                      settingsController.wordHighlightStyle,
                                  currentWordIntensity:
                                      settingsController.wordAnimationIntensity,
                                  onWord: _openWord,
                                  onPhrase: _openPhrase,
                                  onChunk: _seekChunk,
                                ),
                              ),
                            if (settingsController.phonemeRibbonVisible &&
                                subtitleController.currentPrimaryCue != null)
                              Builder(
                                builder: (_) {
                                  final cueId =
                                      subtitleController.currentPrimaryCue!.id;
                                  final analysis = subtitleController
                                      .phoneticAnalysisBySentence[cueId];
                                  final phones = buildLearningPhones(
                                    pronunciation: subtitleController
                                        .pronunciationBySentence[cueId]
                                        ?.toJson(),
                                    wordTimings: subtitleController
                                        .timingsBySentence[cueId],
                                    observedPhones:
                                        analysis?.detectedPhones ?? const [],
                                    allowObservedOnlyFallback: false,
                                  );
                                  if (phones.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: PhonemeRibbon(
                                      phones: phones,
                                      position: playerController.position,
                                      fontSize: primarySize * 0.45,
                                      height: primarySize * 1.1,
                                      style:
                                          settingsController.phonemeRibbonStyle,
                                      tooltip: l.text('textPhonemeRibbonHint'),
                                    ),
                                  );
                                },
                              ),
                            if (settingsController.soundPatternRibbonVisible &&
                                subtitleController.currentPrimaryCue != null)
                              Builder(
                                builder: (_) {
                                  final cueId =
                                      subtitleController.currentPrimaryCue!.id;
                                  final analysis = subtitleController
                                      .phoneticAnalysisBySentence[cueId];
                                  final pronunciation = subtitleController
                                      .pronunciationBySentence[cueId];
                                  final soundAnalysis = analysis?.soundAnalysis;
                                  final rhythmFrame =
                                      subtitleController.llTimelineDocument
                                          ?.rhythmFrameForSentence(cueId) ??
                                      soundAnalysis?.rhythmFrame;
                                  final phones = soundAnalysis == null
                                      ? const <DetectedPhone>[]
                                      : buildSoundPatternPhones(soundAnalysis);
                                  final findings = soundAnalysis == null
                                      ? const <PhonemeRibbonFinding>[]
                                      : buildPhonemeRibbonFindings(
                                          rawFindings:
                                              analysis?.findings
                                                  .map(
                                                    (value) => value.toJson(),
                                                  )
                                                  .toList(growable: false) ??
                                              const [],
                                          phones: phones,
                                          soundAnalysis: soundAnalysis,
                                        );
                                  final hasPhoneEvidence = phones.isNotEmpty;
                                  Widget soundPatternLayer(
                                    Widget child, {
                                    bool offerPhoneEvidence = false,
                                  }) => Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          fit: FlexFit.loose,
                                          child: child,
                                        ),
                                        if (offerPhoneEvidence) ...[
                                          const SizedBox(width: 4),
                                          Tooltip(
                                            message: hasPhoneEvidence
                                                ? l.text(
                                                    _phoneEvidenceExpanded
                                                        ? 'hidePhoneEvidence'
                                                        : 'showPhoneEvidence',
                                                  )
                                                : l.text(
                                                    'soundPatternUnavailableTooltip',
                                                  ),
                                            child: IconButton(
                                              onPressed: hasPhoneEvidence
                                                  ? () => setState(
                                                      () => _phoneEvidenceExpanded =
                                                          !_phoneEvidenceExpanded,
                                                    )
                                                  : null,
                                              icon: Icon(
                                                _phoneEvidenceExpanded
                                                    ? Icons.graphic_eq
                                                    : Icons.graphic_eq_outlined,
                                              ),
                                              isSelected:
                                                  _phoneEvidenceExpanded,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              constraints:
                                                  BoxConstraints.tightFor(
                                                    width: primarySize * 0.95,
                                                    height: primarySize * 0.95,
                                                  ),
                                              padding: EdgeInsets.zero,
                                              iconSize: primarySize * 0.52,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 4),
                                        RhythmReferenceToggle(
                                          mode: settingsController
                                              .soundPatternDisplayMode,
                                          citationTooltip: l.text(
                                            'rhythmReferenceCitationTooltip',
                                          ),
                                          connectedTooltip: l.text(
                                            'rhythmReferenceConnectedTooltip',
                                          ),
                                          actualTooltip: l.text(
                                            'rhythmReferenceActualTooltip',
                                          ),
                                          semanticsLabel: l.text(
                                            'soundPatternDisplayMode',
                                          ),
                                          size: primarySize * 0.95,
                                          onChanged: (value) => unawaited(
                                            _setSoundPatternDisplayMode(value),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );

                                  final mode = settingsController
                                      .soundPatternDisplayMode;
                                  if (mode == 'citation') {
                                    return soundPatternLayer(
                                      pronunciation == null
                                          ? SoundPatternUnavailableRibbon(
                                              message: l.text(
                                                'citationPronunciationUnavailable',
                                              ),
                                              fontSize: primarySize * 0.34,
                                              height: primarySize * 0.9,
                                            )
                                          : ExpectedPronunciationReference(
                                              analysis: pronunciation,
                                              title: l.text(
                                                'rhythmReferenceCitation',
                                              ),
                                              currentTokenIndex:
                                                  subtitleController
                                                      .currentWordToken,
                                              fontSize: primarySize * 0.34,
                                              height: primarySize * 0.86,
                                              tooltip: l.text(
                                                'expectedPronunciationTooltip',
                                              ),
                                            ),
                                    );
                                  }

                                  final connectedReferences =
                                      rhythmFrame?.connectedSpeechRefs
                                          .where(
                                            (reference) => reference
                                                .signalSources
                                                .contains('text_prior'),
                                          )
                                          .toList(growable: false) ??
                                      const <RhythmConnectedSpeechRef>[];
                                  if (mode == 'connected') {
                                    return soundPatternLayer(
                                      connectedReferences.isEmpty
                                          ? SoundPatternUnavailableRibbon(
                                              message: l.text(
                                                'connectedSpeechUnavailable',
                                              ),
                                              fontSize: primarySize * 0.34,
                                              height: primarySize * 0.9,
                                            )
                                          : ConnectedSpeechReferenceRibbon(
                                              references: connectedReferences,
                                              tokens: subtitleController
                                                  .currentPrimaryCue!
                                                  .tokens,
                                              title: l.text(
                                                'connectedSpeechReference',
                                              ),
                                              currentTokenIndex:
                                                  subtitleController
                                                      .currentWordToken,
                                              fontSize: primarySize * 0.44,
                                              height: primarySize * 1.1,
                                              tooltip: l.text(
                                                'connectedSpeechReferenceTooltip',
                                              ),
                                            ),
                                    );
                                  }

                                  if (rhythmFrame == null) {
                                    return soundPatternLayer(
                                      SoundPatternUnavailableRibbon(
                                        message: l.text(
                                          'rhythmFrameUnavailable',
                                        ),
                                        tooltip: l.text(
                                          'soundPatternUnavailableTooltip',
                                        ),
                                        fontSize: primarySize * 0.34,
                                        height: primarySize * 0.9,
                                      ),
                                      offerPhoneEvidence: true,
                                    );
                                  }
                                  final predicted = !rhythmFrameHasAudioSupport(
                                    rhythmFrame,
                                  );
                                  final actualView = RhythmFrameRibbon(
                                    frame: rhythmFrame,
                                    pronunciation: pronunciation,
                                    position: playerController.position,
                                    title: l.text('rhythmReferenceActual'),
                                    anchorLabel: l.text('stressAnchors'),
                                    weakGroupLabel: l.text('weakGroups'),
                                    compressionLabel: l.text('compressedSpans'),
                                    hotspotLabel: l.text('listeningHotspots'),
                                    fontSize: primarySize * 0.44,
                                    height: primarySize * 1.15,
                                    tooltip: predicted
                                        ? l.text('listeningPredictedTooltip')
                                        : l.text('rhythmRibbonHint'),
                                    predicted: predicted,
                                    predictedLabel: l.text(
                                      'listeningPredictedBadge',
                                    ),
                                    onLoopCue: (start, end, label) => unawaited(
                                      _loopRhythmCue(start, end, label),
                                    ),
                                  );
                                  return soundPatternLayer(
                                    _phoneEvidenceExpanded &&
                                            hasPhoneEvidence &&
                                            soundAnalysis != null
                                        ? Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              actualView,
                                              const SizedBox(height: 4),
                                              PhonemeRibbon(
                                                phones: phones,
                                                position:
                                                    playerController.position,
                                                fontSize: primarySize * 0.42,
                                                height: primarySize,
                                                style: settingsController
                                                    .phonemeRibbonStyle,
                                                syllables:
                                                    soundAnalysis.syllables,
                                                prosodicPhrases: soundAnalysis
                                                    .prosodicPhrases,
                                                findings: findings,
                                                lane: PhonemeRibbonLane.sound,
                                                tooltip: l.text(
                                                  'soundPatternRibbonHint',
                                                ),
                                                onLoopFinding: (finding) =>
                                                    unawaited(
                                                      _loopSoundRibbonFinding(
                                                        finding,
                                                        phones,
                                                      ),
                                                    ),
                                              ),
                                            ],
                                          )
                                        : actualView,
                                    offerPhoneEvidence: true,
                                  );
                                },
                              ),
                            if (subtitleController.secondaryVisible &&
                                subtitleController.currentSecondaryCue != null)
                              GestureDetector(
                                onTap: () => adapter.seek(
                                  subtitleController.secondaryCursor.mediaStart(
                                    subtitleController.currentSecondaryCue!,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    subtitleController
                                        .currentSecondaryCue!
                                        .text,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: secondarySize,
                                      fontFamily: _subtitleFont(
                                        subtitleController.secondaryFontFamily,
                                      ),
                                      color: settingsController.secondaryColor,
                                    ),
                                  ),
                                ),
                              )
                            // Secondary enabled but no track at all: say so, so an
                            // empty secondary line is not silently confusing.
                            // A gap within an existing track stays intentionally
                            // empty.
                            else if (subtitleController.secondaryVisible &&
                                subtitleController.secondaryTrack == null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  l.text('noSecondarySubtitle'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: secondarySize * 0.7,
                                    fontFamily: _subtitleFont(
                                      subtitleController.secondaryFontFamily,
                                    ),
                                    color: settingsController.secondaryColor
                                        .withAlpha(140),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (playerController.mediaPath == null)
            Center(
              child: FilledButton.icon(
                onPressed: _openMedia,
                icon: const Icon(Icons.folder_open),
                label: Text(l.text('openVideoAudio')),
              ),
            ),
        ],
      );
    },
  );

  String? _subtitleFont(String value) => switch (value) {
    'serif' => 'Georgia',
    'monospace' => 'Menlo',
    _ => null,
  };

  String _timingQuality(String sentenceId) {
    final first = subtitleController.timingsBySentence[sentenceId]!.first;
    return '${first.source.replaceAll('_', ' ')} · ${first.provider}';
  }

  Widget _sidePanel() => Material(
    color: const Color(0xff151a20),
    child: Column(
      children: [
        SegmentedButton<int>(
          segments: [
            ButtonSegment(
              value: 0,
              icon: const Icon(Icons.subtitles),
              label: Text(l.text('transcript')),
            ),
            ButtonSegment(
              value: 1,
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(l.text('subtitleResources')),
            ),
            ButtonSegment(
              value: 2,
              icon: const Icon(Icons.menu_book),
              label: Text(l.text('wordLearning')),
            ),
            ButtonSegment(
              value: 3,
              icon: const Icon(Icons.analytics_outlined),
              label: Text(l.text('diagnosis')),
            ),
          ],
          selected: {learningController.sidePanel},
          onSelectionChanged: (value) =>
              learningController.selectSidePanel(value.first),
          showSelectedIcon: false,
        ),
        Expanded(
          child: switch (learningController.sidePanel) {
            1 => _subtitleResources(),
            2 =>
              learningController.selectedLexicalDetails == null
                  ? Center(child: Text(l.text('noWordSelected')))
                  : WordLearningPanel(
                      details: learningController.selectedLexicalDetails!,
                      dictionary: learningController.selectedDictionary,
                      pronunciation: learningController.selectedPronunciation,
                      languageProfile:
                          learningController.currentLanguageProfile,
                      onStatus: _setSelectedWordStatus,
                      onSave: _saveSelectedLearningContent,
                      onSource: _playOccurrence,
                      onHeard: () => _observeSelected(true),
                      onNotHeard: () => _observeSelected(false),
                    ),
            3 =>
              learningController.diagnosis == null
                  ? Center(child: Text(l.text('diagnosis')))
                  : _diagnosisCard(),
            _ => _transcript(),
          },
        ),
      ],
    ),
  );

  Widget _transcript() => TranscriptPanel(
    track: subtitleController.primaryTrack,
    scrollController: transcriptController,
    itemExtent: transcriptItemExtent,
    currentCue: subtitleController.currentPrimaryCue,
    wordEntries: learningController.wordEntries,
    showStyles: subtitleController.statusStylesVisible,
    baseColor: settingsController.primaryColor,
    onWord: _openWord,
    onSeekCue: _seekCue,
  );

  Widget _subtitleResources() => SubtitleResourceManagerPanel(
    mediaId: playerController.mediaId,
    resources: subtitleController.subtitleResources,
    capabilities: subtitleController.subtitleResourceCapabilities,
    activeTrack: subtitleController.primaryTrack,
    timelineDocument: subtitleController.llTimelineDocument,
    wordTimelineSummaries: subtitleController.wordTimelineSummaries,
    phoneTimelineSummaries: subtitleController.phoneTimelineSummaries,
    chunkTimelineSummaries: subtitleController.chunkTimelineSummaries,
    activeWordTimingCount: _activeWordTimingCount(),
    timelineResourceError: subtitleController.timelineResourceError,
    onImportSubtitle: () async => _openSubtitle(secondary: false),
    onImportLLTimeline: _openLLTimelineResource,
    onRefreshResources: _refreshSubtitleResources,
    onActivateSubtitle: _activateSubtitleResource,
    onArchiveSubtitle: _archiveSubtitleResource,
    onRestoreSubtitle: _restoreSubtitleResource,
    onDeleteSubtitle: _deleteSubtitleResource,
    onExportSubtitle: _exportSubtitleResource,
    onLanguageChanged: _changeTrackLanguage,
    availableLanguages: learningController.availableLanguages,
    onExportLLTimeline: _exportLLTimelineResource,
    onActivateWordTimeline: _activateWordTimeline,
    onManualReviewTimeline: _openManualReviewTimeline,
    onActivatePhoneTimeline: _activatePhoneTimeline,
    onArchivePhoneTimeline: _archivePhoneTimeline,
    onDeletePhoneTimeline: _deletePhoneTimeline,
    onGenerateChunkTimeline: _generateChunkTimeline,
    onActivateChunkTimeline: _activateChunkTimeline,
    onArchiveChunkTimeline: _archiveChunkTimeline,
    onDeleteChunkTimeline: _deleteChunkTimeline,
  );

  Widget _diagnosisCard() => DiagnosisCard(
    diagnosis: learningController.diagnosis!,
    pronunciation: subtitleController.currentPrimaryCue == null
        ? null
        : subtitleController.pronunciationBySentence[subtitleController
              .currentPrimaryCue!
              .id],
    ruleHintsLevel: settingsController.ruleHintsLevel,
    pronunciationProviders: subtitleController.pronunciationProviders,
    timingQuality:
        subtitleController.currentPrimaryCue == null ||
            (subtitleController.timingsBySentence[subtitleController
                        .currentPrimaryCue!
                        .id] ??
                    const [])
                .isEmpty
        ? null
        : _timingQuality(subtitleController.currentPrimaryCue!.id),
    phoneticAnalysis: subtitleController.currentPrimaryCue == null
        ? null
        : subtitleController.phoneticAnalysisBySentence[subtitleController
              .currentPrimaryCue!
              .id],
    currentDetectedPhone: subtitleController.currentDetectedPhone,
    onAnalyzePhonetics: settingsController.phoneticAnalysisPreference == 'off'
        ? null
        : () => unawaited(_analyzePhonetics(wholeTrack: false)),
    onAnalyzeTrackPhonetics:
        settingsController.phoneticAnalysisPreference == 'off'
        ? null
        : () => unawaited(_analyzePhonetics(wholeTrack: true)),
    onLoopDetectedPhone: (phone) => unawaited(
      _loopPhoneticRange(
        phone.start.inMilliseconds,
        phone.end.inMilliseconds,
        'Looping detected phone ${phone.displayIpa}',
      ),
    ),
    onLoopFinding: (finding) => unawaited(
      _loopPhoneticRange(
        finding.audioStartMs,
        finding.audioEndMs,
        'Looping audio finding evidence',
      ),
    ),
    onFindingFeedback: (finding, value) =>
        unawaited(_savePhoneticFindingFeedback(finding, value)),
  );

  Widget _controls() {
    if (playerController.mediaPath == null) return _noMediaControls();
    final currentChunk = _currentChunkRef();
    return PlaybackControls(
      adapter: adapter,
      position: playerController.position,
      duration: playerController.duration,
      playing: playerController.playing,
      loopCue: subtitleController.loopCue,
      sourceLoopStart: playerController.sourceLoopStart,
      statusStylesVisible: subtitleController.statusStylesVisible,
      subtitlesVisible: subtitleController.visible,
      secondarySubtitlesVisible: subtitleController.secondaryVisible,
      secondarySubtitlesAvailable: subtitleController.secondaryTrack != null,
      rate: playerController.rate,
      volume: playerController.volume,
      muted: playerController.muted,
      audioTracks: playerController.audioTracks,
      selectedAudioId: playerController.selectedAudioId,
      embeddedSubtitleTracks: playerController.embeddedSubtitleTracks,
      selectedEmbeddedSubtitleId: playerController.selectedEmbeddedSubtitleId,
      primarySubtitleOffset: subtitleController.primarySubtitleOffset,
      secondarySubtitleOffset: subtitleController.secondarySubtitleOffset,
      status: status,
      taskStatuses: taskStatuses.values.toList(growable: false),
      onSeek: (value) => adapter.seek(value),
      onSeekToPreviousCue: () => _seekCue(
        subtitleController.primaryCursor.previous(
          subtitleController.currentPrimaryCue,
        ),
      ),
      onSeekToZero: () => adapter.seek(Duration.zero),
      onPlayPause: adapter.playOrPause,
      onStop: adapter.stop,
      onSeekToNextCue: () => _seekCue(
        subtitleController.primaryCursor.next(
          subtitleController.currentPrimaryCue,
        ),
      ),
      chunkControlsEnabled: currentChunk != null,
      chunkLoopActive:
          playerController.sourceLoopStart != null &&
          currentChunk?.start == playerController.sourceLoopStart,
      onSeekToPreviousChunk: () => _seekAdjacentChunk(-1),
      onSeekToNextChunk: () => _seekAdjacentChunk(1),
      onLoopCurrentChunk: _loopCurrentChunk,
      onLoopExpandedChunk: _loopExpandedChunk,
      onLoopCueChanged: (value) {
        subtitleController.setLoopCue(value);
        if (value) playerController.setSourceLoop(null, null);
      },
      onStopSourceLoop: () => playerController.setSourceLoop(null, null),
      onStatusStylesChanged: (value) {
        subtitleController.setStatusStylesVisible(value);
        unawaited(_saveSettings());
      },
      onSubtitlesVisibleChanged: (value) {
        subtitleController.setVisible(value);
        unawaited(_saveSettings());
      },
      onSecondaryVisibleChanged: (value) {
        subtitleController.setSecondaryVisible(value);
        unawaited(_saveSettings());
      },
      onRateChanged: (value) {
        playerController.setRate(value);
        adapter.setRate(value);
        unawaited(_saveSettings());
      },
      onVolumeChanged: (value) {
        playerController.setVolume(value);
        if (!playerController.muted) adapter.setVolume(value);
        unawaited(_saveSettings());
      },
      onMuteToggle: () {
        final newMuted = !playerController.muted;
        playerController.setMuted(newMuted);
        adapter.setVolume(newMuted ? 0 : playerController.volume);
      },
      onAudioTrackChanged: (track) {
        playerController.setSelectedAudioId(track.id);
        adapter.selectAudio(track);
      },
      onEmbeddedSubtitleTrackChanged: (track) {
        playerController.setSelectedEmbeddedSubtitleId(track.id);
        adapter.selectSubtitle(track);
      },
      onPrimaryOffsetChanged: (offset) {
        subtitleController.setPrimarySubtitleOffset(offset);
        unawaited(_saveSettings());
      },
      onSecondaryOffsetChanged: (offset) {
        subtitleController.setSecondarySubtitleOffset(offset);
        unawaited(_saveSettings());
      },
    );
  }

  Widget _noMediaControls() => Material(
    color: const Color(0xff11161c),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${l.text('noMediaControlsHint')} · $status',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.secondary),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: _openMedia,
            icon: const Icon(Icons.folder_open),
            label: Text(l.text('openVideoAudio')),
          ),
        ],
      ),
    ),
  );

  _ChunkRef? _currentChunkRef() {
    final cue = subtitleController.currentPrimaryCue;
    if (cue == null) return null;
    final partition = subtitleController.chunkPartitionsBySentence[cue.id];
    if (partition == null || partition.chunks.isEmpty) return null;
    final index =
        subtitleController.currentChunkIndex ??
        currentChunkAtPosition(
          partition,
          playerController.position,
          offset: subtitleController.primarySubtitleOffset,
        );
    if (index == null) return null;
    for (final chunk in partition.chunks) {
      if (chunk.index == index) return _ChunkRef(cue, chunk, partition);
    }
    return null;
  }

  _ChunkRef? _chunkRefAt(Cue cue, int chunkIndex) {
    final partition = subtitleController.chunkPartitionsBySentence[cue.id];
    if (partition == null || partition.chunks.isEmpty) return null;
    if (chunkIndex < 0 || chunkIndex >= partition.chunks.length) return null;
    return _ChunkRef(cue, partition.chunks[chunkIndex], partition);
  }

  Future<void> _seekChunk(DisplayChunk chunk) async {
    final start = _mediaTime(chunk.start);
    await adapter.seek(start);
    playerController.setPosition(start);
  }

  Future<void> _seekAdjacentChunk(int delta) async {
    final current = _currentChunkRef();
    final cue = current?.cue ?? subtitleController.currentPrimaryCue;
    if (cue == null) return;
    final localIndex = current == null
        ? 0
        : current.partition.chunks.indexWhere(
            (chunk) => chunk.index == current.chunk.index,
          );
    var target = _chunkRefAt(cue, localIndex + delta);
    if (target == null && delta < 0) {
      final previousCue = subtitleController.primaryCursor.previous(cue);
      final previousPartition = previousCue == null
          ? null
          : subtitleController.chunkPartitionsBySentence[previousCue.id];
      if (previousCue != null &&
          previousPartition != null &&
          previousPartition.chunks.isNotEmpty) {
        target = _ChunkRef(
          previousCue,
          previousPartition.chunks.last,
          previousPartition,
        );
      }
    }
    if (target == null && delta > 0) {
      final nextCue = subtitleController.primaryCursor.next(cue);
      target = nextCue == null ? null : _chunkRefAt(nextCue, 0);
    }
    if (target == null) return;
    await _seekChunk(target.chunk);
  }

  Future<void> _loopCurrentChunk() async {
    final current = _currentChunkRef();
    if (current == null) return;
    final start = _mediaTime(current.chunk.start);
    final end = _mediaTime(current.chunk.end);
    if (end <= start) return;
    playerController.setSourceLoop(start, end);
    subtitleController.setLoopCue(false);
    await adapter.seek(start);
    await adapter.play();
  }

  Future<void> _loopExpandedChunk() async {
    final current = _currentChunkRef();
    if (current == null) return;
    final localIndex = current.partition.chunks.indexWhere(
      (chunk) => chunk.index == current.chunk.index,
    );
    final next =
        localIndex >= 0 && localIndex + 1 < current.partition.chunks.length
        ? current.partition.chunks[localIndex + 1]
        : null;
    final start = _mediaTime(current.chunk.start);
    final end = _mediaTime(next?.end ?? current.cue.end);
    if (end <= start) return;
    playerController.setSourceLoop(start, end);
    subtitleController.setLoopCue(false);
    await adapter.seek(start);
    await adapter.play();
  }

  Duration _mediaTime(Duration subtitleTime) {
    final value = subtitleTime + subtitleController.primarySubtitleOffset;
    return value.isNegative ? Duration.zero : value;
  }

  Widget _downloadStatusBar(DownloadStatusSnapshot downloadStatus) =>
      DownloadStatusBar(
        status: downloadStatus,
        onCancel: () {
          downloadController.cancel();
          setState(() => status = l.text('downloadCancelled'));
        },
        onOpenMediaPath: () {
          final path = downloadStatus.downloadedMediaPath;
          if (path != null) {
            downloadController.dismiss();
            unawaited(_openMediaPath(path));
          }
        },
        onDismiss: downloadController.dismiss,
      );
}

class _ChunkRef {
  const _ChunkRef(this.cue, this.chunk, this.partition);

  final Cue cue;
  final DisplayChunk chunk;
  final SentenceChunkPartition partition;

  Duration get start => chunk.start;
}
