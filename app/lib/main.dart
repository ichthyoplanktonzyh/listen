import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'controllers/auxiliary_audio_controller.dart';
import 'controllers/backend_event_coordinator.dart';
import 'controllers/content_channel_coordinator.dart';
import 'controllers/discovery_view_model.dart';
import 'controllers/document_session_controller.dart';
import 'controllers/core_session_controller.dart';
import 'controllers/download_controller.dart';
import 'controllers/downloads_controller.dart';
import 'controllers/extensive_listening_controller.dart';
import 'controllers/hunting_actions_coordinator.dart';
import 'controllers/hunting_controller.dart';
import 'controllers/hunting_session_controller.dart';
import 'controllers/immersive_mode_controller.dart';
import 'controllers/learning_controller.dart';
import 'controllers/learning_edition_controller.dart';
import 'controllers/learning_assets_view_models.dart';
import 'controllers/learning_flow_view_models.dart';
import 'controllers/learning_workflow_controller.dart';
import 'controllers/listening_inbox_coordinator.dart';
import 'controllers/media_import_flow_controller.dart';
import 'controllers/media_library_coordinator.dart';
import 'controllers/media_library_scan_controller.dart';
import 'controllers/media_session_coordinator.dart';
import 'controllers/occurrence_media_resolver.dart';
import 'controllers/playback_actions_coordinator.dart';
import 'controllers/player_controller.dart';
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
import 'controllers/review_deck_controller.dart';
import 'controllers/coach_dashboard_controller.dart';
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
import 'controllers/transcript_readiness_view_model.dart';
import 'controllers/vocabulary_actions_coordinator.dart';
import 'controllers/vocabulary_view_model.dart';
import 'controllers/cold_start_marking_view_model.dart';
import 'controllers/writing_channel_coordinator.dart';
import 'controllers/writing_task_controller.dart';
import 'controllers/material_capability_coordinator.dart';
import 'data/repositories/core_repositories.dart';
import 'data/repositories/composite_discovery_repository.dart';
import 'data/repositories/discovery_repository.dart';
import 'data/repositories/feed_discovery_repository.dart';
import 'services/listen_gen_process_service.dart';
import 'services/composition_session_service.dart';
import 'services/composition_transcript_bridge.dart';
import 'services/listen_gen_release_service.dart';
import 'widgets/navigation/app_sidebar.dart';
import 'widgets/navigation/pane_segments.dart';
import 'widgets/navigation/shell_tools_menu.dart';
import 'widgets/layout/session_subtitle_menu.dart';
import 'widgets/home/home_pane.dart';
import 'widgets/flows/shell_learning_routes.dart';
import 'data/repositories/core_session_repository.dart';
import 'data/repositories/media_import_repository.dart';
import 'localization.dart';
import 'models/backend_event.dart';
import 'models/content_activity.dart';
import 'models/content_channel.dart';
import 'models/composition.dart';
import 'models/document_session.dart';
import 'models/workbench_study_mode.dart';
import 'models/personal_expression.dart';
import 'models/practice.dart';
import 'models/learning_material.dart';
import 'models/personal_library.dart';
import 'models/task_status.dart';
import 'models/timeline.dart';
import 'models/types.dart';
import 'player_adapter.dart';
import 'player_shortcuts.dart';
import 'services/anki_package_file_service.dart';
import 'services/core_transport_service.dart';
import 'services/content_generator_setup.dart';
import 'services/cover_art_cache.dart';
import 'services/desktop_playback_bootstrap.dart';
import 'services/diagnostic_log_export_service.dart';
import 'services/external_tools.dart';
import 'services/file_transfer_service.dart';
import 'services/fullscreen_window.dart';
import 'services/acquisition_ledger.dart';
import 'services/document_intake_flow.dart';
import 'services/document_intake_service.dart';
import 'services/document_reference_store.dart';
import 'services/capability_file_resolver.dart';
import 'services/document_source_resolver.dart';
import 'services/pdf_text_extractor.dart';
import 'services/subscription_store.dart';
import 'services/media_import_file_service.dart';
import 'services/media_library_scanner.dart';
import 'services/managed_asset_store.dart';
import 'services/platform_capabilities.dart';
import 'services/smoke_launch_configuration_service.dart';
import 'settings.dart';
import 'theme/listen_theme.dart';
import 'theme/spacing.dart';
import 'ui/core/app_controller_scope.dart';
import 'utils/format_duration.dart';
import 'widgets/app_bar/app_bar_capabilities.dart';
import 'widgets/app_bar/macos_menu_bar.dart';
import 'widgets/channels/reading_channel.dart';
import 'widgets/channels/speaking_channel.dart';
import 'widgets/channels/writing_channel.dart';
import 'widgets/common/listen_loading.dart';
import 'widgets/flows/content_speaking_activity_dialog.dart';
import 'widgets/flows/learning_flows.dart';
import 'widgets/flows/media_import_flows.dart';
import 'widgets/flows/reading_flows.dart';
import 'widgets/flows/speaking_flows.dart';
import 'widgets/flows/subtitle_resource_flows.dart';
import 'widgets/flows/writing_flows.dart';
import 'widgets/home/listening_home.dart';
import 'widgets/layout/content_channel_availability.dart';
import 'widgets/layout/desktop_drop_surface.dart';
import 'widgets/layout/document_workbench.dart';
import 'widgets/layout/media_workbench.dart';
import 'widgets/layout/playback_bar.dart';
import 'widgets/layout/player_overlays.dart';
import 'widgets/layout/player_stage.dart';
import 'widgets/layout/shell_recede.dart';
import 'widgets/layout/side_panel.dart';
import 'widgets/layout/listening_session_menu.dart';
import 'widgets/layout/study_menu.dart';
import 'widgets/layout/translation_mode_button.dart';
import 'widgets/panels/conversation_stage_shell.dart';
import 'widgets/panels/l1_specialty_dialog.dart';
import 'widgets/panels/learning_edition_panel.dart';
import 'widgets/panels/listening_inbox_panel.dart';
import 'widgets/panels/realtime_conversation_panel.dart';
import 'widgets/panels/sentence_analysis_window.dart';
import 'widgets/player/download_status_bar.dart';
import 'widgets/player/player_global_shortcuts.dart';
import 'widgets/player/retention_menu.dart';
import 'widgets/player/shortcut_cheat_sheet.dart';
import 'widgets/settings/settings_flow.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const FvpDesktopPlaybackBootstrap().initialize();
  // Cover art survives the launch it was fetched in only from here: every
  // other construction site defaults to keeping nothing, so no test writes
  // images into the developer's own support directory.
  CoverArtCache.instance = CoverArtCache.forCurrentUser();
  runApp(
    ListenApp(
      platformCapabilities: const LocalPlatformCapabilities(),
      pathHelper: const PlatformPathHelper(),
      smokeLaunchConfiguration:
          const EnvironmentSmokeLaunchConfigurationService(),
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

/// The disk half of the media-library scan's cheap identification layer.
///
/// Core stores a media's path and duration but neither its size nor its mtime,
/// so the stamps that let a scan skip probing an unchanged file can only be
/// read here. It lives in the composition root because the file system is not a
/// controller's to touch.
Future<KnownMediaStamp?> _readMediaStamp(String path) async {
  try {
    final stat = await File(path).stat();
    if (stat.type == FileSystemEntityType.notFound) return null;
    return KnownMediaStamp(
      path: path,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
    );
  } on FileSystemException {
    return null;
  }
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
  final currentRoute = ValueNotifier<AppRoute>(AppRoute.home);

  /// The resolved generation toolchain (whisper model, whisper-cli, ffprobe,
  /// ffmpeg), refreshed once after launch and re-read at every run through
  /// the provider-arguments closure. A setup resolved later (whisper model
  /// downloaded after the first launch) still applies to the next run.
  ContentGeneratorSetup _generatorSetup = unresolvedContentGeneratorSetup;

  Future<void> _resolveGeneratorToolchain() async {
    final setup = await ContentGeneratorLocator(
      ffprobePath: settingsController.ffprobePath,
      ffmpegPath: settingsController.ffmpegPath,
    ).resolve();
    if (!mounted) return;
    setState(() => _generatorSetup = setup);
    _transcriptReadiness?.refreshAvailability();
  }

  TranscriptPreparationAvailability _preparationAvailability() {
    if (!coreSessionController.state.isConnected) {
      return TranscriptPreparationAvailability.coreUnavailable;
    }
    if (!capabilityCoordinator.isConfigured) {
      return TranscriptPreparationAvailability.generatorUnavailable;
    }
    final toolchainBlocker = switch (_generatorSetup.state) {
      ContentGeneratorState.ready => null,
      ContentGeneratorState.generatorMissing =>
        TranscriptPreparationAvailability.generatorUnavailable,
      ContentGeneratorState.pythonMissing =>
        TranscriptPreparationAvailability.pythonUnavailable,
      ContentGeneratorState.whisperMissing =>
        TranscriptPreparationAvailability.whisperUnavailable,
      ContentGeneratorState.modelMissing =>
        TranscriptPreparationAvailability.whisperModelUnavailable,
      ContentGeneratorState.ffprobeMissing ||
      ContentGeneratorState.ffmpegMissing =>
        TranscriptPreparationAvailability.mediaToolsUnavailable,
    };
    if (toolchainBlocker != null) return toolchainBlocker;
    if (!(playerController.mediaPath?.isNotEmpty ?? false)) {
      return TranscriptPreparationAvailability.mediaUnavailable;
    }
    if (playerController.mediaId == null) {
      return TranscriptPreparationAvailability.mediaRegistrationUnavailable;
    }
    return TranscriptPreparationAvailability.ready;
  }

  // Segment selection lives beside the route because it has to be settable
  // from outside the pane that draws it: coach suggestions land on a specific
  // language segment, not just on the destination.
  final languageSegment = ValueNotifier<LanguageSegment>(
    LanguageSegment.vocabulary,
  );
  late final SubscriptionStore subscriptionStore =
      SubscriptionStore.forCurrentUser();
  /// The composition root is the only place that hands out a ledger backed by
  /// a real directory; everything else defaults to remembering nothing.
  ///
  /// One instance, because two would disagree: Discovery writes what it
  /// acquired and the downloads shelf reads it back, and a second in-memory
  /// copy would show an empty shelf beside a feed row that says "downloaded".
  late final AcquisitionLedger acquisitionLedger =
      AcquisitionLedger.forCurrentUser();

  late final DownloadsController downloadsController = DownloadsController(
    ledger: acquisitionLedger,
    repository: coreRepositories.mediaLibrary,
  );

  late final DiscoveryViewModel discoveryViewModel = DiscoveryViewModel(
    CompositeDiscoveryRepository(
      // One store across both sides: a subscription is a subscription, and
      // only the composition root hands out one backed by a real directory.
      FeedDiscoveryRepository(subscriptions: subscriptionStore),
      YoutubeDiscoveryRepository(subscriptions: subscriptionStore),
    ),
    importRepository: mediaImportRepository,
    mediaLibraryRepository: coreRepositories.mediaLibrary,
    ledger: acquisitionLedger,
    // Source Identity and the material boundary: intake records the canonical
    // key once a discovered item converges on a Material, and a later refresh
    // of the same feed item resolves the same Material instead of offering a
    // second download.
    sourceIdentity: coreRepositories.sourceIdentity,
    learningMaterial: coreRepositories.learningMaterial,
    // The article path shares the document intake a local file travels:
    // decode, managed binding, Core create, exact rendition match.
    // One persisted downloads location instead of a folder chooser that
    // reopened on the first acquisition of every launch.
    downloadsDirectory: () => settingsController.resolveDownloadsDirectory(
      confirmButtonText: 'Select',
    ),
    documentFileService: const LocalDocumentIntakeFileService(),
    documentIntake: DocumentIntakeFlow(
      materialRepository: coreRepositories.learningMaterial,
      codec: LocalDocumentIntakeCodec(
        pdfTextExtractor: PdfRxPdfTextExtractor(),
      ),
      store: managedAssetStore,
      referenceStore: DocumentReferenceStore(
        file: DocumentReferenceStore.fileFor(
          settingsController.settings.supportDirectory,
        ),
      ),
    ),
  )..load();
  late final coreSessionRepository = LocalCoreSessionRepository(coreTransport);
  late final coreRepositories = LocalCoreRepositories(coreTransport);

  /// Resolves adopted composition content for the composition session surface.
  late final compositionSessionService = CompositionSessionService(
    repository: coreRepositories.capability,
    resources: coreRepositories.resource,
  );
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

  /// The managed asset store: kept material is copied here, content-addressed
  /// by SHA-256. The root follows the settings verdict, so a missing custom
  /// location resolves to null and the store reports itself unavailable.
  late final managedAssetStore = LocalManagedAssetStoreService(
    resolveRoot: () => switch (settingsController.managedStoreLocation.state) {
      StorageLocationState.appManaged ||
      StorageLocationState.ready => settingsController.managedStoreLocation.path,
      StorageLocationState.missing => null,
    },
  );

  // ── Controllers ──
  final playerController = PlayerController();
  final subtitleController = SubtitleController();
  final learningController = LearningController();
  late final practiceController = PracticeController(
    repository: coreRepositories.practice,
  );
  final slicePlayerController = SlicePlayerController();

  /// The sentence-analysis panel's own single-sentence player, so its
  /// sound-reference ribbons can play and highlight the current sentence
  /// independently of the main stage.
  final voiceClipPlayer = SlicePlayerController();
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
    managedStore: managedAssetStore,
    materialRepository: coreRepositories.learningMaterial,
    // Keeping a download moves it off the downloads shelf and into the
    // library: both lists have to be re-read, or the same file shows up in
    // two places that mean opposite things.
    onLibraryChanged: () async {
      await mediaLibraryActions.loadMediaLibrary();
      await downloadsController.refresh();
    },
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
    materialRepository: coreRepositories.learningMaterial,
  );
  Future<String?> _mediaFilePathForRendition(MediaRendition rendition) async {
    final snapshot =
        mediaLibraryActions.mediaLibrary ?? const <MediaLibraryEntry>[];
    for (final entry in snapshot) {
      if (entry.media.id == rendition.mediaId) return entry.media.path;
    }
    // The snapshot can lag a freshly registered media (opening a file
    // registers it without entering any app-side list yet), and the media
    // library list only contains Personal Library rows. Core's single-media
    // read answers for every registered media, retained or not.
    try {
      final media = await coreRepositories.mediaLibrary.readMedia(
        rendition.mediaId ?? '',
      );
      if (media.id == rendition.mediaId) return media.path;
    } on Object {
      // Honest miss: the rendition travels without a blob path and the run
      // fails on the request rather than guessing.
    }
    return null;
  }

  late final capabilityCoordinator = MaterialCapabilityCoordinator(
    repository: coreRepositories.capability,
    generator: LocalListenGenProcessService(
      pythonExecutable: () => _generatorSetup.pythonPath,
      releaseService: LocalListenGenReleaseService(),
    ),
    mediaPathResolver: _mediaFilePathForRendition,
    subtitleTrackForMedia: (rendition) {
      final selected = subtitleController.primaryTrack;
      if (selected == null ||
          !selected.usableForLearning ||
          selected.mediaId != rendition.mediaId) {
        return null;
      }
      return selected;
    },
    // Document source bytes for a Gen run come from the same places direct
    // rendering reads them: the content-addressed managed store copy for
    // managed bindings, the learner-chosen referenced location (re-verified
    // at use) for reference-in-place bindings.
    fileResolver: LocalCapabilityFileResolver(
      managedStorePath: (asset) {
        final root = managedAssetStore.resolveRoot();
        if (root == null || root.isEmpty) return null;
        return '$root${Platform.pathSeparator}${asset.sha256Digest}';
      },
      referenceStore: DocumentReferenceStore(
        file: DocumentReferenceStore.fileFor(
          settingsController.settings.supportDirectory,
        ),
      ),
      mediaFilePath: _mediaFilePathForRendition,
    ),
    // Provider selection stays out of the request document: the toolchain is
    // located on this machine (whisper model, whisper-cli, ffprobe, ffmpeg)
    // and the run reads the latest resolved setup each time it starts.
    providerArguments: () => [
      ...contentGeneratorProviderArguments(_generatorSetup),
      '--tts-provider',
      'say',
    ],
  );
  late final learningEditionController = LearningEditionController(
    repository: coreRepositories.capability,
    onAdopted: _refreshAdoptedLearningEdition,
  );
  late final mediaLibraryScan = MediaLibraryScanController(
    scanner: MediaLibraryScanner(
      FfprobeMediaProbe(ffprobePath: settingsController.ffprobePath),
    ),
    repository: coreRepositories.mediaLibrary,
    resolveFolder: () async {
      // A custom location can go off disk between visits (unmounted volume,
      // rename), so the verdict is re-read at the start of every scan. The
      // default app-managed store is created on demand: a not-yet-existing
      // default store is an empty store, never the missing-folder story.
      await settingsController.refreshManagedStoreState();
      final location = settingsController.managedStoreLocation;
      if (location.state == StorageLocationState.appManaged) {
        final defaultStore = Directory(location.path);
        if (!await defaultStore.exists()) {
          await defaultStore.create(recursive: true);
        }
        return (path: location.path, state: StorageLocationState.ready);
      }
      return location;
    },
    registeredPaths: () => mediaLibraryActions.registeredMediaPaths,
    refreshLibrary: mediaLibraryActions.loadMediaLibrary,
    readStamp: _readMediaStamp,
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
  DocumentSessionController? _documentSession;
  VoidCallback? _documentSessionListener;
  String? _projectedDocumentReleaseId;
  String? _openedDocumentAudioReleaseId;
  String? _openingDocumentAudioReleaseId;
  TranscriptReadinessViewModel? _transcriptReadiness;

  /// How the listening transcript presents itself. A workbench-level display
  /// choice, not a channel, so it lives here beside the other local UI state
  /// rather than in [ContentChannelCoordinator].
  WorkbenchStudyMode _studyMode = WorkbenchStudyMode.normal;
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

  /// The folder scan follows the media surface, never the app launch: entering
  /// the surface brings the library up to date, leaving it stops the walk
  /// rather than letting it run behind a screen nobody is looking at.
  void _scanLibraryWhileVisible() {
    if (currentRoute.value == AppRoute.library) {
      unawaited(mediaLibraryScan.enterLibrary());
      // A download that landed while the learner was in Discovery has to be
      // on the shelf by the time they look at it. Arriving at the page is the
      // meaningful moment to re-ask; nothing polls.
      unawaited(downloadsController.refresh());
    } else {
      mediaLibraryScan.leaveLibrary();
    }
  }

  /// The media surface sends the user to the same picker Settings uses; a
  /// location that actually changed is scanned right away, because otherwise
  /// the surface would sit on the previous store until the next visit.
  Future<void> _chooseManagedStoreLocation() async {
    final before = settingsController.managedStoreLocation;
    final location = await settingsController.chooseManagedStoreLocation(
      confirmButtonText: l.text('managedStorePickerConfirm'),
    );
    if (!mounted) return;
    if (location.path == before.path) return;
    await mediaLibraryScan.refresh();
  }

  void _onMediaLibraryScanChanged() {
    if (mounted) setState(() {});
  }

  /// Keeps the extensive-listening played clock honest: it ticks only while
  /// the main player is actually playing (issue #3).
  void _trackExtensivePlayback() =>
      extensiveListeningController.notePlaybackState(playerController.playing);

  @override
  void initState() {
    super.initState();
    unawaited(_resolveGeneratorToolchain());
    playerController.addListener(_surfaceErrorStatus);
    playerController.addListener(_trackExtensivePlayback);
    currentRoute.addListener(_scanLibraryWhileVisible);
    mediaLibraryScan.addListener(_onMediaLibraryScanChanged);
    downloadsController.addListener(_onMediaLibraryScanChanged);
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
        // A different media has a different transcript story; drop the
        // previous media's readiness state (and cancel any in-flight
        // preparation) rather than letting it bleed into the next session.
        _transcriptReadiness?.dispose();
        _transcriptReadiness = null;
        unawaited(slicePlayerController.close());
        if (speakingActions.isOpen) {
          speakingChannel.closeL1Check();
          unawaited(speakingActions.close(restorePosition: false));
        }
        huntingSessionController.stop();
        final documentSession = _documentSession;
        final documentListener = _documentSessionListener;
        if (documentSession != null && documentListener != null) {
          documentSession.removeListener(documentListener);
        }
        setState(() {
          _documentSession = null;
          _documentSessionListener = null;
          _projectedDocumentReleaseId = null;
          _openedDocumentAudioReleaseId = null;
          _openingDocumentAudioReleaseId = null;
          taskStatuses.clear();
          _workbenchExpanded = true;
        });
        documentSession?.dispose();
        _workbenchAnimController.forward();
      },
      reloadLearningEntries: () async {
        await vocabularyActions.loadWordEntries();
        await vocabularyActions.loadPhraseEntries();
      },
      loadPhraseCandidates: vocabularyActions.loadPhraseCandidates,
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
      onReturnToReview: () => _openReviewQueue(),
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
      unawaited(downloadsController.refresh());
      unawaited(_runSmokeIfConfigured());
      // The first load may have run before Core was reachable and answered
      // "undetermined"; a fresh connected generation is a meaningful
      // invalidation, so re-ask for whatever entry is selected. No polling.
      unawaited(discoveryViewModel.refreshSelectedMediaAvailability());
    }
    setState(() {});
  }

  void _expandWorkbench() {
    setState(() => _workbenchExpanded = true);
    _workbenchAnimController.forward();
  }

  void _collapseWorkbench() {
    debugPrint(
      '[_collapseWorkbench] called; anim status='
      '${_workbenchAnimController.status} value=${_workbenchAnimController.value}',
    );
    unawaited(practiceActions.closePracticeWindow());
    _workbenchAnimController.reverse().then((_) {
      debugPrint(
        '[_collapseWorkbench] reverse settled; expanded=false; status='
        '${_workbenchAnimController.status}',
      );
      if (mounted) setState(() => _workbenchExpanded = false);
    });
  }

  /// Starts learning from a discovery entry: opens the media in the session
  /// and expands the workbench (a global layer above the route shell).
  Future<void> _startLearningFromDiscovery(String path) async {
    await mediaSession.openMediaPath(path);
    _expandWorkbench();
  }

  /// Opens an acquired article's Material in the document session: reads the
  /// Material, projects it as a library row, and hands it to the workbench
  /// through the same door the library uses — a discovered article is not a
  /// different kind of material, so it must not get a different entry.
  Future<void> _openMaterialFromDiscovery(String materialId) async {
    final details = await coreRepositories.learningMaterial
        .readLearningMaterial(materialId);
    await _openMaterialEntry(
      PersonalLibraryEntry(details: details, mediaEntries: const []),
    );
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
      currentPrimaryTrackId: () => subtitleController.primaryTrack?.id,
      loadWordEntries: vocabularyActions.loadWordEntries,
      loadTimelineResource: resourceActions.loadTimelineResource,
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
      enabled: settingsController.settings.phonemeHighlightVisible,
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  /// The workbench's "generate subtitles" action. Whole-media transcription
  /// jobs and the v1 package journey are gone; this requests the Read
  /// capability for the current media's material through the deep completion
  /// coordinator (resolve → derive through the pinned listen-gen bundle →
  /// install → adopt), and the readiness surface reflects the run.
  Future<void> _generateSubtitles({bool forceRegenerate = false}) async {
    await _readinessViewModel.prepareLearningTranscript(
      forceRegenerate: forceRegenerate,
    );
  }

  Future<void> _refreshAdoptedLearningEdition() async {
    final document = _documentSession;
    if (document != null) {
      await document.refreshComposition();
      return;
    }
    await _readinessViewModel.refreshAdoptedComposition();
  }

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

  /// Opens a document in the app's existing workbench layer. This deliberately
  /// does not push a route: text, audio, and video now differ only in what the
  /// workbench body mounts, not in which page hierarchy owns the session.
  Future<void> _openDocumentSession([PersonalLibraryEntry? entry]) async {
    final referenceStore = DocumentReferenceStore(
      file: DocumentReferenceStore.fileFor(
        settingsController.settings.supportDirectory,
      ),
    );
    final controller = DocumentSessionController(
      materialRepository: coreRepositories.learningMaterial,
      fileService: const LocalDocumentIntakeFileService(),
      intakeFlow: DocumentIntakeFlow(
        materialRepository: coreRepositories.learningMaterial,
        codec: LocalDocumentIntakeCodec(
          pdfTextExtractor: PdfRxPdfTextExtractor(),
        ),
        store: managedAssetStore,
        referenceStore: referenceStore,
      ),
      sourceResolver: LocalDocumentSourceResolver(
        store: managedAssetStore,
        referenceStore: referenceStore,
        resolveStoreRoot: managedAssetStore.resolveRoot,
      ),
      // The generated edition is part of this material's session, not a
      // separate destination: the workbench resolves it alongside the original
      // document and refreshes in place when a generation finishes.
      resolveComposition: compositionSessionService.resolveComposition,
      refreshLibrary: mediaLibraryActions.reconcileMembership,
    );
    if (entry != null) controller.openLibraryEntry(entry);
    await mediaSession.deactivateForMaterialSwitch();
    if (!mounted) {
      controller.dispose();
      return;
    }
    final previous = _documentSession;
    final previousListener = _documentSessionListener;
    if (previous != null && previousListener != null) {
      previous.removeListener(previousListener);
    }
    void documentListener() => _syncDocumentComposition(controller);
    controller.addListener(documentListener);
    setState(() {
      _documentSession = controller;
      _documentSessionListener = documentListener;
      _projectedDocumentReleaseId = null;
      _openedDocumentAudioReleaseId = null;
      _openingDocumentAudioReleaseId = null;
      _workbenchExpanded = true;
    });
    previous?.dispose();
    _workbenchAnimController.forward();
    _syncDocumentComposition(controller);
  }

  /// The one door into the workbench for a retained material.
  ///
  /// Which body the workbench mounts follows the material's real capabilities
  /// rather than a choice the library forced on the learner: a material with
  /// playable media opens its media session, a text-only material opens its
  /// document, and either way the adopted composition rides along inside that
  /// same session. Nothing is pushed and the material id never changes.
  Future<void> _openMaterialEntry(PersonalLibraryEntry entry) =>
      entry.canListenOrWatch
      ? mediaLibraryActions.openLibraryEntry(entry)
      : _openDocumentSession(entry);

  void _closeDocumentWorkbench() {
    final closing = _documentSession;
    if (closing == null) return;
    _workbenchAnimController.reverse().then((_) {
      if (!mounted || !identical(_documentSession, closing)) return;
      final listener = _documentSessionListener;
      if (listener != null) closing.removeListener(listener);
      unawaited(mediaSession.deactivateForMaterialSwitch());
      setState(() {
        _documentSession = null;
        _documentSessionListener = null;
        _projectedDocumentReleaseId = null;
        _openedDocumentAudioReleaseId = null;
        _openingDocumentAudioReleaseId = null;
        _workbenchExpanded = false;
      });
      closing.dispose();
    });
  }

  Widget _documentWorkbench(DocumentSessionController controller) {
    // Gen progress is not document state. Listen to both sources so resolving,
    // generation, install, adoption, cancellation and failure all update the
    // header while the source document remains untouched underneath.
    return ListenableBuilder(
      listenable: Listenable.merge([controller, capabilityCoordinator]),
      builder: (context, _) {
        final material = switch (controller.state) {
          DocumentSessionReady(:final details) => details,
          _ => null,
        };
        return DocumentWorkbench(
          controller: controller,
          mediaFraction: settingsController.workbenchMediaFraction,
          onMediaFractionChanged: _setWorkbenchMediaFraction,
          onCollapse: _closeDocumentWorkbench,
          onOpenSettings: () => unawaited(_openSettings()),
          timedLearningPanel: _sidePanel(),
          listenRun: material == null
              ? null
              : capabilityCoordinator.runViewFor(
                  material.material.id,
                  MaterialCapability.listen,
                ),
          onRequestListen: material == null
              ? null
              : () =>
                    unawaited(_generateListenForDocument(controller, material)),
          onCancelListen: material == null
              ? null
              : () => unawaited(
                  capabilityCoordinator.cancel(
                    material.material.id,
                    MaterialCapability.listen,
                  ),
                ),
          learningEditionAction: material == null
              ? null
              : _learningEditionAction(
                  materialId: material.material.id,
                  capability: MaterialCapability.listen,
                  onGenerate: () =>
                      _generateListenForDocument(controller, material),
                  onRegenerate: () => _generateListenForDocument(
                    controller,
                    material,
                    forceRegenerate: true,
                  ),
                ),
        );
      },
    );
  }

  /// Projects an adopted document composition onto the same transcript and
  /// transport state used by audio/video sessions.
  void _syncDocumentComposition(DocumentSessionController controller) {
    if (!mounted || !identical(_documentSession, controller)) return;
    final ready = controller.state;
    if (ready is! DocumentSessionReady) return;
    final composition = ready.composition;
    if (composition == null) return;

    // Edition identity is stable across repeated generation for one Material;
    // release identity changes with the adopted package. Keying this refresh
    // by edition would leave a supplemented transcript/audio invisible.
    if (_projectedDocumentReleaseId != composition.releaseId) {
      _projectedDocumentReleaseId = composition.releaseId;
      final track = composition.transcript;
      if (track != null) {
        subtitleController.setPrimaryTrack(track);
        subtitleController.setSubtitleResources([track]);
        final enhancements = composition.enhancements;
        subtitleController.setSpeechEnhancements(
          pronunciationBySentence: const {},
          timingsBySentence: enhancements.timingsBySentence,
          pronunciationProviders: const [],
          chunkPartitionsBySentence: enhancements.chunkPartitionsBySentence,
          senseGroupsBySentence: enhancements.senseGroupsBySentence,
          acousticsBySentence: enhancements.acousticsBySentence,
          prosodyAnchorsBySentence: enhancements.prosodyAnchorsBySentence,
          phonesBySentence: enhancements.phonesBySentence,
        );
        subtitleController.setSubtitleResourceCapabilities({
          track.id: SubtitleResourceCapabilities.fromCounts(
            sentenceCount: track.cues.length,
            wordTimingCount: enhancements.timingsBySentence.values.fold(
              0,
              (total, values) => total + values.length,
            ),
            chunkCount: enhancements.chunkPartitionsBySentence.values.fold(
              0,
              (total, value) => total + value.chunks.length,
            ),
            phoneCount: enhancements.phonesBySentence.values.fold(
              0,
              (total, values) => total + values.length,
            ),
          ),
        });
        subtitleController.updatePosition(playerController.position);
      }
    }

    final path = composition.derivedMediaPath;
    if (path == null ||
        _openedDocumentAudioReleaseId == composition.releaseId ||
        _openingDocumentAudioReleaseId == composition.releaseId) {
      return;
    }
    _openingDocumentAudioReleaseId = composition.releaseId;
    unawaited(_openDocumentCompositionAudio(controller, ready, composition));
  }

  Future<void> _openDocumentCompositionAudio(
    DocumentSessionController controller,
    DocumentSessionReady ready,
    ResolvedComposition composition,
  ) async {
    final path = composition.derivedMediaPath;
    if (path == null) return;
    try {
      await adapter.open(path, play: false);
      final current = controller.state;
      if (!mounted ||
          !identical(_documentSession, controller) ||
          current is! DocumentSessionReady ||
          current.composition?.releaseId != composition.releaseId) {
        return;
      }
      playerController.setMaterialPlaybackSource(
        path: path,
        title: ready.details.currentRevision.title,
        kind: 'audio',
      );
      playerController.setPosition(Duration.zero);
      _openedDocumentAudioReleaseId = composition.releaseId;
    } on Object catch (error) {
      if (mounted && identical(_documentSession, controller)) {
        playerController.setStatus(
          l.text('statusPlaybackFailed'),
          error: true,
          failure: coreRepositories.capability.failureDetail(error),
        );
      }
    } finally {
      if (_openingDocumentAudioReleaseId == composition.releaseId) {
        _openingDocumentAudioReleaseId = null;
      }
    }
  }

  /// Generates the Listen capability for the document on the workbench and
  /// refreshes that same session in place.
  ///
  /// The material id is the one already open and does not change: the produced
  /// speech is adopted as this material's composition, never registered as a
  /// second media. When the run finishes the session re-reads its adopted
  /// composition, so the audio and its sentence alignment simply appear —
  /// there is nothing for the learner to open.
  Future<void> _generateListenForDocument(
    DocumentSessionController controller,
    MaterialDetails material, {
    bool forceRegenerate = false,
  }) async {
    await capabilityCoordinator.requestCapability(
      material,
      MaterialCapability.listen,
      forceProduce: forceRegenerate,
    );
    if (!mounted || !identical(_documentSession, controller)) return;
    await controller.refreshComposition();
  }

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
    // Unavailable State (CONTEXT.md): the sidebar conversation entry is a
    // user click — a silent return left it as a dead button, so name the
    // reason instead.
    if (!widget.platformCapabilities.isMacOS) {
      playerController.setStatus(l.text('conversationMacOsOnly'));
      return;
    }
    if (!coreSessionController.state.isConnected) {
      playerController.setStatus(l.text('statusConnectLocalCoreFirst'));
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
          // The stage still covers the shell, so this door keeps the pushed
          // dictionary on top instead of swapping the route underneath.
          onOpenVocabulary: () => _showVocabulary(),
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
    if (source == null) {
      // The standing destination with no writing task attached: the route
      // shell hosts it. Only a deep link carrying a source (the debrief's
      // save-expression door) still pushes on top as a task.
      _openLanguage(LanguageSegment.expressions);
      return Future<void>.value();
    }
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
    learningController.setDiagnosisExpanded(true);
    await _refreshDiagnosis();
    if (mounted) {
      playerController.setStatus(l.text('statusPausedForListeningCheck'));
    }
  }

  /// The vocabulary book as a standing destination; `_showVocabulary` stays
  /// for parameterised deep links (initial entry, cross-modal review) that
  /// launch a task on top of whatever is on screen.
  void _openVocabulary() => _openLanguage(LanguageSegment.vocabulary);

  /// The "my language" destination, opened at a named segment. Every caller
  /// that wants vocabulary, expressions or review goes through here, so the
  /// pane can never be opened at the wrong one.
  void _openLanguage(LanguageSegment segment) {
    languageSegment.value = segment;
    currentRoute.value = AppRoute.language;
  }

  void _openLibrary() => currentRoute.value = AppRoute.library;

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

  void _openReviewQueue() => _openLanguage(LanguageSegment.review);

  /// Route-scoped controller bundles for the learning shell routes. The
  /// hosts own the lifecycle; these factories are the composition root, so
  /// repository access stays here and out of presentation.
  VocabularyRouteControllers? _createVocabularyRouteControllers() {
    if (!coreSessionController.state.isConnected) return null;
    return VocabularyRouteControllers(
      viewModel: VocabularyViewModel(
        repository: coreRepositories.lexical,
        language: settingsController.resolveLearningLanguage(
          subtitleController.primaryTrack?.language,
        ),
      ),
      semanticSearchViewModel: SemanticSearchViewModel(
        coreRepositories.semanticSearch,
      ),
      slicePlayer: SlicePlayerController(),
    );
  }

  ExpressionRouteControllers? _createExpressionRouteControllers() {
    if (!coreSessionController.state.isConnected) return null;
    return ExpressionRouteControllers(
      viewModel: PersonalExpressionViewModel(
        coreRepositories.personalExpression,
        language: settingsController.resolveLearningLanguage(
          subtitleController.primaryTrack?.language,
        ),
      ),
    );
  }

  ReviewRouteControllers? _createReviewRouteControllers() {
    if (!coreSessionController.state.isConnected) return null;
    return ReviewRouteControllers(
      controller: ReviewController(coreRepositories.review),
      deckController: ReviewDeckController(coreRepositories.review),
      resolver: OccurrenceMediaResolver(repository: coreRepositories.review),
      slicePlayer: SlicePlayerController(),
    );
  }

  CoachRouteControllers? _createCoachRouteControllers() {
    if (!coreSessionController.state.isConnected) return null;
    return CoachRouteControllers(
      controller: CoachDashboardController(coreRepositories.coachDashboard),
    );
  }

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

  /// Opens the adopted composition view of a library material: the produced
  /// reading structure with derived audio and alignment.
  TranscriptReadinessViewModel get _readinessViewModel =>
      _transcriptReadiness ??= TranscriptReadinessViewModel(
        subtitle: subtitleController,
        mediaSession: mediaSession,
        preparationAvailability: _preparationAvailability,
        coordinator: capabilityCoordinator,
        currentMaterial: () => mediaSession.currentMaterial,
        bridge: CompositionTranscriptBridge(
          readComposition: coreRepositories.capability.readAdoptedComposition,
          readResourcePayload:
              coreRepositories.capability.readCompositionResourcePayload,
          importSubtitle: (mediaId, path) =>
              coreRepositories.mediaSession.importSubtitle(mediaId, path),
        ),
        // Same resolver the document workbench uses: one material, one
        // adopted composition, whichever body the workbench has mounted.
        resolveComposition: compositionSessionService.resolveComposition,
        // The predicate reads core connectivity *and* live player identity.
        // Both can arrive after the workbench first builds, so the projection
        // must be invalidated by either source. Duration is deliberately not
        // a gate: Gen probes the source file itself.
        refreshTrigger: Listenable.merge([
          coreSessionController,
          playerController,
        ]),
      )..bind(text: (key) => l.text(key));

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

  /// (Re)opens the sentence-analysis panel's own player on the current
  /// sentence and starts playback, so the panel's sound-reference ribbons can
  /// highlight against a playback the reader drives there — without moving the
  /// main stage.
  Future<void> _playVoiceClip() async {
    final cue = subtitleController.currentPrimaryCue;
    final path = playerController.mediaPath;
    if (cue == null || path == null) return;
    final cursor = subtitleController.primaryCursor;
    await voiceClipPlayer.open(
      occurrence: {
        'start_ms_snapshot': cursor.mediaStart(cue).inMilliseconds,
        'end_ms_snapshot': cursor.mediaEnd(cue).inMilliseconds,
        'sentence_id': cue.id,
      },
      path: path,
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

  /// Plays from the tapped word: a single click on a transcript word seeks to
  /// that word's own start when the file has word-level timing, so the reader
  /// hears exactly where they pointed. Files without word timing fall back to
  /// the sentence start — the same place [_seekCue] lands — rather than
  /// pretending to a precision the timeline does not have.
  Future<void> _seekWord(SubtitleToken token, Cue cue) async {
    final timings = subtitleController.timingsBySentence[cue.id] ?? const [];
    final matches = timings.where((timing) => timing.tokenIndex == token.index);
    if (matches.isEmpty) {
      await _seekCue(cue);
      return;
    }
    subtitleController.setCurrentPrimaryCue(cue);
    unawaited(_refreshDiagnosis());
    await adapter.seek(
      subtitleController.primaryCursor.mediaAt(matches.first.start),
    );
  }

  @override
  void dispose() {
    unawaited(coreSessionController.shutdown());
    final documentSession = _documentSession;
    final documentListener = _documentSessionListener;
    if (documentSession != null && documentListener != null) {
      documentSession.removeListener(documentListener);
    }
    _documentSession?.dispose();
    _transcriptReadiness?.dispose();
    learningEditionController.dispose();
    coreSessionController.removeListener(_onCoreSessionStateChanged);
    playerController.removeListener(_surfaceErrorStatus);
    playerController.removeListener(_trackExtensivePlayback);
    currentRoute.removeListener(_scanLibraryWhileVisible);
    mediaLibraryScan.removeListener(_onMediaLibraryScanChanged);
    mediaLibraryScan.dispose();
    _workbenchAnimController.dispose();
    downloadController.dispose();
    mediaImportController.dispose();
    voiceClipPlayer.dispose();
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
    languageSegment.dispose();
    currentRoute.dispose();
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

  /// The homeless tools, at the foot of the rail. Everything else the shell
  /// app bar used to carry had another owner already.
  Widget _toolsMenu() => ShellToolsMenu(
    onOpenLearningAssets: () => unawaited(_openLearningAssets()),
    onOpenLearningResources: () => unawaited(_openLearningResources()),
    onExportLogs: () => unawaited(_exportLogs()),
    onExportVocabulary: () => unawaited(playbackActions.exportVocabulary()),
    onImportVocabulary: () => unawaited(playbackActions.importVocabulary()),
    onImportWordList: () => unawaited(_importWordList()),
  );

  /// Actions on the media currently on the workbench. Rendered inside the
  /// session header, which only exists while there is media — so nothing here
  /// needs a `canActOnMedia` gate.
  Widget _sessionSubtitleMenu() => SessionSubtitleMenu(
    onImportPrimarySubtitle: () =>
        unawaited(mediaSession.openSubtitle(secondary: false)),
    onGeneratePrimarySubtitles: () => unawaited(_generateSubtitles()),
    onSearchPrimarySubtitles: () =>
        unawaited(_searchOpenSubtitles(secondary: false)),
    onImportSecondarySubtitle: () =>
        unawaited(mediaSession.openSubtitle(secondary: true)),
    onSearchSecondarySubtitles: () =>
        unawaited(_searchOpenSubtitles(secondary: true)),
    onImportEmbeddedSubtitle: () => unawaited(_importEmbeddedSubtitle()),
    onArchiveMedia: () => unawaited(playbackActions.archiveCurrentMedia()),
  );

  Widget _learningEditionAction({
    required String materialId,
    required MaterialCapability capability,
    required Future<void> Function() onGenerate,
    Future<void> Function()? onRegenerate,
  }) => LearningEditionAction(
    onPressed: () => unawaited(
      showLearningEditionPanel(
        context: context,
        controller: learningEditionController,
        materialId: materialId,
        onGenerate: onGenerate,
        onRegenerate: onRegenerate,
        generationListenable: capabilityCoordinator,
        isGenerating: () =>
            capabilityCoordinator.runViewFor(materialId, capability)?.busy ??
            false,
        runView: () => capabilityCoordinator.runViewFor(materialId, capability),
        onCancelGeneration: () =>
            capabilityCoordinator.cancel(materialId, capability),
      ),
    ),
  );

  /// What each channel can and cannot do with the material that is loaded.
  /// A channel that cannot be entered is listed with its reason rather than
  /// hidden or offered as a clickable promise.
  Map<ContentChannel, ContentChannelAvailability> _channelAvailability() {
    final noTranscript = subtitleController.primaryTrack == null
        ? ContentChannelAvailability.unavailable(
            l.text('channelNeedsTranscript'),
          )
        : null;
    return {
      ContentChannel.listening: const ContentChannelAvailability.available(),
      ContentChannel.reading:
          noTranscript ?? const ContentChannelAvailability.available(),
      ContentChannel.speaking:
          noTranscript ??
          (widget.platformCapabilities.isMacOS
              ? const ContentChannelAvailability.available()
              : ContentChannelAvailability.unavailable(
                  l.text('channelUnavailable'),
                )),
      ContentChannel.writing:
          noTranscript ?? const ContentChannelAvailability.available(),
    };
  }

  /// The extensive-listening session. It was on the transport, among controls
  /// that act on the next 200ms; a session that spans a whole sitting belongs
  /// with the other facts about this sitting.
  Widget _listeningMenu() => ListeningSessionMenu(
    active: extensiveListeningController.active,
    huntingActive: huntingSessionController.state.enabled,
    markEnabled: subtitleController.currentPrimaryCue != null,
    inboxCount: extensiveListeningController.activeItemCount,
    onToggleListening: () => unawaited(_toggleExtensiveListening()),
    onToggleHunting: () => unawaited(huntingActions.toggleHuntingMode()),
    onCaptureInbox: () => unawaited(inboxActions.captureListeningInbox()),
    onViewInbox: () => unawaited(_openListeningInbox()),
    onHardInterrupt: () => unawaited(_hardInterruptListening()),
  );

  /// Opens the Listening Inbox — the box the `mark` action fills — as a modal
  /// sheet reachable straight from the session menu, so what was marked can be
  /// read back without hunting through the side panel. Mirrors how the vocab
  /// screen surfaces the Hunting List.
  Future<void> _openListeningInbox() async {
    await inboxActions.refreshListeningInbox();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: ListeningInboxPanel(
            controller: extensiveListeningController,
            onRefresh: inboxActions.refreshListeningInbox,
            onReplay: inboxActions.replayListeningInboxItem,
            onProcess: inboxActions.processListeningInboxItem,
          ),
        ),
      ),
    );
  }

  /// Switches the transcript between original, bilingual and translation.
  Widget _translationMenu() => TranslationModeButton(
    mode: settingsController.transcriptTranslation,
    onChanged: (mode) =>
        unawaited(settingsController.setTranscriptTranslation(mode)),
  );

  /// The retention affordance for the current media: Keep (copy into the
  /// managed store), reference in place, or unretain. The menu reads its
  /// state from the player, and the coordinator owns the work.
  Widget _retentionMenu() => RetentionMenu(
    player: playerController,
    onKeepCopy: () => unawaited(mediaSession.keepCurrentMedia()),
    onKeepReference: () =>
        unawaited(mediaSession.referenceCurrentMediaInPlace()),
    onUnretain: () => unawaited(mediaSession.unretainCurrentMedia()),
  );

  /// Ways of working the material on the workbench. One menu, because these
  /// were spread over a posture grid, a popup inside it, and two transport
  /// menus — four places to look for one decision.
  Widget _studyMenu() {
    final cue = subtitleController.currentPrimaryCue;
    return StudyMenu(
      selectedChannel: contentChannels.selected,
      channelAvailability: _channelAvailability(),
      onChannelSelected: (channel) =>
          unawaited(contentChannels.select(channel)),
      selectedMode: _studyMode,
      onModeSelected: _selectStudyMode,
      hasCue: cue != null,
      canCloze:
          cue != null &&
          (subtitleController.timingsBySentence[cue.id] ?? const []).isNotEmpty,
      canChunkDictation:
          cue != null &&
          (subtitleController
                  .chunkPartitionsBySentence[cue.id]
                  ?.chunks
                  .isNotEmpty ??
              false),
      onShadow: () => unawaited(practiceActions.startShadowingPractice()),
      onCloze: () => unawaited(practiceActions.startClozePractice()),
      onChunkDictation: () =>
          unawaited(practiceActions.startChunkDictationPractice()),
      onSentenceDictation: () =>
          unawaited(practiceActions.startSentenceDictationPractice()),
    );
  }

  /// Enters the listening channel in [mode]. The three reading displays are the
  /// listening channel — picking one from the study menu both selects it and
  /// sets how its transcript reads.
  void _selectStudyMode(WorkbenchStudyMode mode) {
    setState(() => _studyMode = mode);
    if (contentChannels.selected != ContentChannel.listening) {
      unawaited(contentChannels.select(ContentChannel.listening));
    }
  }

  // ── Shell panes ──
  //
  // Four destinations, one of which holds several surfaces as segments. The
  // segments are page state, not addresses: they do not belong in [AppRoute],
  // because nothing outside the shell should be able to link to "the review
  // tab" as though it were a place. What *does* need to reach them — the
  // coach's suggestions — goes through [_openLanguage].

  Widget _routePane(AppRoute route) => switch (route) {
    AppRoute.home => _homePane(),
    AppRoute.library => _libraryPane(),
    AppRoute.language => _languagePane(),
    AppRoute.coach => _coachPane(),
  };

  Widget _homePane() => HomePane(
    discovery: discoveryViewModel,
    recentMediaTitle: settingsController.lastMediaTitle.isEmpty
        ? null
        : settingsController.lastMediaTitle,
    recentMediaPath: settingsController.lastMediaPath.isEmpty
        ? null
        : settingsController.lastMediaPath,
    recentPosition: Duration(
      milliseconds: settingsController.lastMediaPositionMs,
    ),
    recentDuration: Duration(
      milliseconds: settingsController.lastMediaDurationMs,
    ),
    recentSubtitleCount: settingsController.lastMediaSubtitleCount,
    onContinue: _continueRecentMedia,
    onOpenMedia: mediaSession.openMedia,
    onPlayMedia: _startLearningFromDiscovery,
    onOpenDocument: (materialId) =>
        unawaited(_openMaterialFromDiscovery(materialId)),
  );

  void _continueRecentMedia() {
    if (_workbenchExpanded || playerController.mediaPath != null) {
      _expandWorkbench();
    } else {
      unawaited(mediaLibraryActions.continueRecentMedia());
    }
  }

  Widget _libraryPane() => ListeningHome(
    onOpenMedia: mediaSession.openMedia,
    onOpenOnline: _openOnline,
    onOpenDocument: () => unawaited(_openDocumentSession()),
    personalLibrary: mediaLibraryActions.personalLibrary,
    personalLibraryFailure: mediaLibraryActions.personalLibraryFailure,
    onRetryLibrary: () => unawaited(mediaLibraryActions.loadMediaLibrary()),
    offlineEntries: mediaLibraryActions.offlineLibrary,
    familiarSupplyEnabled: settingsController.familiarMaterialSuggestions,
    scan: mediaLibraryScan.state,
    onScanRefresh: () => unawaited(mediaLibraryScan.refresh()),
    onScanCancel: mediaLibraryScan.cancel,
    onRetryScanRegistrations: () =>
        unawaited(mediaLibraryScan.retryFailedRegistrations()),
    onChooseManagedStoreLocation: () =>
        unawaited(_chooseManagedStoreLocation()),
    onOpenLibraryEntry: (entry) => unawaited(_openMaterialEntry(entry)),
    onStartExtensiveEntry: (entry) =>
        unawaited(mediaLibraryActions.startExtensiveFromLibrary(entry)),
    onStartIntensiveEntry: (entry) =>
        unawaited(mediaLibraryActions.startIntensiveFromLibrary(entry)),
    onSetLibraryIntent: (entry, intent) =>
        unawaited(mediaLibraryActions.setLibraryTriageIntent(entry, intent)),
    onToggleFamiliarSupply: (enabled) =>
        unawaited(mediaLibraryActions.toggleFamiliarSupply(enabled)),
    capabilityCoordinator: capabilityCoordinator,
    onRequestCapability: (entry, capability) => unawaited(
      capabilityCoordinator.requestCapability(entry.details, capability),
    ),
    onCancelCapability: (entry, capability) =>
        unawaited(capabilityCoordinator.cancel(entry.materialId, capability)),
    downloads: downloadsController.entries,
    downloadsFailure: downloadsController.failure,
    onOpenDownload: (entry) =>
        unawaited(mediaSession.openMediaPath(entry.path)),
    onDeleteDownload: (entry) => unawaited(_deleteDownload(entry)),
  );

  /// Deleting a download removes a real file, so it asks first and reports
  /// when the disk did not cooperate.
  Future<void> _deleteDownload(DownloadedMedia entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.text('downloadsDeleteTitle')),
        content: Text('${entry.title}\n\n${l.text('downloadsDeleteBody')}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.text('downloadsDeleteConfirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final removed = await downloadsController.deleteDownload(entry);
    if (!mounted) return;
    if (!removed) {
      _showSnackBar(l.text('downloadsDeleteFailed'));
      return;
    }
    // The feed row for this item must stop saying "on this device".
    unawaited(discoveryViewModel.refreshSelectedMediaAvailability());
  }

  String get _routeLanguage => settingsController.resolveLearningLanguage(
    subtitleController.primaryTrack?.language,
  );

  Widget _languagePane() => ValueListenableBuilder<LanguageSegment>(
    valueListenable: languageSegment,
    builder: (context, segment, _) {
      final connected = coreSessionController.state.isConnected;
      return SegmentedPane<LanguageSegment>(
        selected: segment,
        onSelected: (value) => languageSegment.value = value,
        segments: [
          PaneSegment(
            value: LanguageSegment.vocabulary,
            label: l.text('sidebarVocabulary'),
            builder: (context) => VocabularyRouteHost(
              create: connected ? _createVocabularyRouteControllers : null,
              language: _routeLanguage,
              onExport: playbackActions.exportVocabulary,
              onImport: playbackActions.importVocabulary,
              huntingController: huntingController,
              auxiliaryAudio: auxiliaryAudioController,
              pauseBackgroundPlayback: _acquireAuxiliaryAudioFocus,
              onStartShadowing: practiceActions.startExternalShadowing,
            ),
          ),
          PaneSegment(
            value: LanguageSegment.expressions,
            label: l.text('sidebarExpression'),
            builder: (context) => ExpressionRouteHost(
              create: connected ? _createExpressionRouteControllers : null,
              language: _routeLanguage,
              createDetailViewModel: connected
                  ? (pattern) => PersonalExpressionDetailViewModel(
                      coreRepositories.personalExpression,
                      pattern: pattern,
                    )
                  : null,
              onPlaySource: _playPersonalExpressionSource,
              onStartSpeaking: _startPersonalExpressionSpeaking,
            ),
          ),
          PaneSegment(
            value: LanguageSegment.review,
            label: l.text('review'),
            builder: (context) => ReviewRouteHost(
              create: connected ? _createReviewRouteControllers : null,
              language: _routeLanguage,
              fileService: const LocalAnkiPackageFileService(),
              pauseBackgroundPlayback: _acquireAuxiliaryAudioFocus,
              onStartShadowing: _startReviewShadowing,
              onStartDelayedRetelling: _startDelayedRetelling,
            ),
          ),
        ],
      );
    },
  );

  Widget _coachPane() => CoachRouteHost(
    create: coreSessionController.state.isConnected
        ? _createCoachRouteControllers
        : null,
    language: _routeLanguage,
    // The coach's doors point at sibling destinations: swap the route (and
    // the segment it has to land on) instead of pushing a copy.
    onNavigate: (destination, _) {
      switch (destination.kind) {
        case 'review_queue':
          _openLanguage(LanguageSegment.review);
        case 'hunting_list':
          _openLanguage(LanguageSegment.vocabulary);
        case 'cross_modal_review':
          unawaited(_showVocabulary(openCrossModalReview: true));
        case 'personal_expression':
          _openLanguage(LanguageSegment.expressions);
        case 'content_home':
          _openLibrary();
      }
      return Future<void>.value();
    },
  );

  @override
  Widget build(BuildContext context) {
    final coreState = coreSessionController.state;
    if (!coreState.isConnected) {
      // The boot splash must keep rebuilding while the core session and the
      // status text change; otherwise a slow connect leaves the old frame
      // ("Starting local core...") on screen after the core is already up.
      return ListenableBuilder(
        listenable: Listenable.merge([coreSessionController, playerController]),
        builder: (context, _) {
          final state = coreSessionController.state;
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.isConnecting) const ListenLoading(),
                  const SizedBox(height: ListenSpacing.gap16),
                  Text(status, textAlign: TextAlign.center),
                  if (!state.isConnecting) ...[
                    const SizedBox(height: ListenSpacing.gap12),
                    FilledButton(
                      onPressed: () =>
                          unawaited(coreSessionController.connect()),
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
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
                    // No shell app bar. It was a fourth navigation: its
                    // content and learning menus repeated the native macOS
                    // menu bar, the rail and the pages themselves; its
                    // settings button and wordmark repeated the rail's own
                    // footer and header. What it alone carried moved to where
                    // it applies — subtitle sourcing to the workbench's
                    // session header, the tool centres to the rail's foot.
                    body: immersiveMode.immersive
                        ? _immersiveBody(shellVisible)
                        : DesktopDropSurface(
                            onDropped: subtitleSources.handleDrop,
                            child: Column(
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      ValueListenableBuilder<AppRoute>(
                                        valueListenable: currentRoute,
                                        builder: (context, route, _) {
                                          return Stack(
                                            children: [
                                              Row(
                                                children: [
                                                  AppSidebar(
                                                    // Destinations swap the
                                                    // pane in place; the
                                                    // conversation stage is
                                                    // pushed over the shell,
                                                    // so it arrives on its own
                                                    // callback.
                                                    currentRoute: route,
                                                    onRouteSelected: (route) =>
                                                        currentRoute.value =
                                                            route,
                                                    onOpenConversation: () =>
                                                        unawaited(
                                                          _openFreeConversation(),
                                                        ),
                                                    onOpenSettings: () =>
                                                        unawaited(
                                                          _openSettings(),
                                                        ),
                                                    toolsMenu: _toolsMenu(),
                                                  ),
                                                  Expanded(
                                                    child: _routePane(route),
                                                  ),
                                                ],
                                              ),
                                              // One workbench layer, two
                                              // bodies. A document and a media
                                              // session are mutually exclusive
                                              // by construction (opening media
                                              // clears the document session),
                                              // so this is a choice of body,
                                              // not a second surface.
                                              if (_documentSession
                                                  case final document?)
                                                SlideTransition(
                                                  position:
                                                      _workbenchSlideAnimation,
                                                  child: _documentWorkbench(
                                                    document,
                                                  ),
                                                )
                                              else if (playerController
                                                      .mediaPath !=
                                                  null)
                                                SlideTransition(
                                                  position:
                                                      _workbenchSlideAnimation,
                                                  child: MediaWorkbench(
                                                    learningEditionAction:
                                                        switch (mediaSession
                                                            .currentMaterial) {
                                                          final material? =>
                                                            _learningEditionAction(
                                                              materialId:
                                                                  material
                                                                      .material
                                                                      .id,
                                                              capability:
                                                                  MaterialCapability
                                                                      .read,
                                                              onGenerate:
                                                                  _generateSubtitles,
                                                              onRegenerate:
                                                                  () => _generateSubtitles(
                                                                    forceRegenerate:
                                                                        true,
                                                                  ),
                                                            ),
                                                          null => null,
                                                        },
                                                    subtitleMenu:
                                                        _sessionSubtitleMenu(),
                                                    studyMenu: _studyMenu(),
                                                    listeningMenu:
                                                        _listeningMenu(),
                                                    canShadow:
                                                        subtitleController
                                                            .currentPrimaryCue !=
                                                        null,
                                                    onShadow: () => unawaited(
                                                      practiceActions
                                                          .startShadowingPractice(),
                                                    ),
                                                    onOpenSettings: () =>
                                                        unawaited(
                                                          _openSettings(),
                                                        ),
                                                    retentionMenu:
                                                        _retentionMenu(),
                                                    translationMenu:
                                                        _translationMenu(),
                                                    mediaTitle: widget
                                                        .pathHelper
                                                        .basename(
                                                          playerController
                                                              .mediaPath!,
                                                        ),
                                                    showMediaPane:
                                                        playerController
                                                            .mediaKind !=
                                                        'audio',
                                                    playerStage: _playerStage(),
                                                    learningPanel: _sidePanel(),
                                                    selectedChannel:
                                                        contentChannels
                                                            .selected,
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
                                              // Back button removed
                                            ],
                                          );
                                        },
                                      ),
                                      if (_documentSession == null) ...[
                                        PlayerOverlays(
                                          practiceController:
                                              practiceController,
                                          slicePlayerController:
                                              slicePlayerController,
                                          huntingSessionController:
                                              huntingSessionController,
                                          subtitleController:
                                              subtitleController,
                                          playerController: playerController,
                                          practiceActions: practiceActions,
                                          huntingActions: huntingActions,
                                          onCloseSlicePlayback:
                                              _closeSlicePlayback,
                                        ),
                                        _analysisWindow(),
                                      ],
                                    ],
                                  ),
                                ),
                                if (downloadController.snapshot != null)
                                  _downloadStatusBar(
                                    downloadController.snapshot!,
                                  ),
                                // The transport belongs to whatever is on the
                                // workbench. A document that took the
                                // workbench paused the previous media and
                                // kept its state — but leaving that media's
                                // transport under an unrelated document
                                // advertises a session the workbench is not
                                // showing. It comes back with the media.
                                if (_documentSession == null ||
                                    playerController.mediaPath != null)
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
      onOpenVocabulary: _openVocabulary,
      onOpenReview: () => _openReviewQueue(),
      onOpenCoach: () => currentRoute.value = AppRoute.coach,
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
    onSaveSettings: _saveSettings,
    onOpenMedia: mediaSession.openMedia,
    onToggleFullscreen: () => unawaited(immersiveMode.toggle()),
  );

  Widget _sidePanel() => SidePanel(
    playerController: playerController,
    subtitleController: subtitleController,
    learningController: learningController,
    extensiveListeningController: extensiveListeningController,
    settingsController: settingsController,
    mediaSession: mediaSession,
    transcriptReadiness: _readinessViewModel,
    transcriptController: transcriptController,
    onOpenWord: vocabularyActions.openWord,
    onSeekCue: _seekCue,
    onSeekWord: _seekWord,
    onSetSelectedWordStatus: vocabularyActions.setSelectedWordStatus,
    onSetCapabilityOverride: vocabularyActions.setCapabilityOverride,
    onSaveSelectedLearningContent:
        vocabularyActions.saveSelectedLearningContent,
    onObserveSelected: vocabularyActions.observeSelected,
    onOpenSlicePlayback: _openSlicePlayback,
    onOpenListeningDictionary: _openListeningDictionaryEntry,
    onPlayPronunciationAudio: _playPronunciationAudio,
    onCorrectLemma: () => unawaited(_correctCurrentLemma()),
    onRefreshListeningInbox: inboxActions.refreshListeningInbox,
    onReplayListeningInboxItem: inboxActions.replayListeningInboxItem,
    onProcessListeningInboxItem: inboxActions.processListeningInboxItem,
    onStartColdStart: _openColdStartMarking,
    onRecordCurrentSource: vocabularyActions.recordCurrentSource,
    onReadingMark: readingController.isOpen
        ? (understood) => unawaited(_recordReadingMark(understood))
        : null,
    studyMode: _studyMode,
  );

  /// The draggable sentence-analysis window, floated centre-stage over the
  /// workbench. Its open/close flag is [LearningController.diagnosisExpanded] —
  /// the same flag the transcript's `解析` entry toggles — so it rebuilds when
  /// that, the current sentence, or a freshly loaded diagnosis changes.
  Widget _analysisWindow() => ListenableBuilder(
    listenable: Listenable.merge([learningController, subtitleController]),
    builder: (context, _) {
      if (!learningController.diagnosisExpanded) {
        return const SizedBox.shrink();
      }
      return SentenceAnalysisWindow(
        subtitleController: subtitleController,
        learningController: learningController,
        settingsController: settingsController,
        playbackActions: playbackActions,
        voiceClipPlayer: voiceClipPlayer,
        onRequestDiagnosis: _refreshDiagnosis,
        onPlayVoiceClip: _playVoiceClip,
        onSetSoundPatternDisplayMode: _setSoundPatternDisplayMode,
        onClose: () => learningController.setDiagnosisExpanded(false),
        onOpenListeningDictionary: _openListeningDictionaryEntry,
        onOpenL1Specialty: _openL1Specialty,
      );
    },
  );

  Widget _controls() => PlaybackBar(
    adapter: adapter,
    playerController: playerController,
    extensiveListeningController: extensiveListeningController,
    subtitleController: subtitleController,
    mediaSession: mediaSession,
    playbackActions: playbackActions,
    taskStatuses: taskStatuses.values.toList(growable: false),
    onSeekCue: _seekCue,
    onSaveSettings: _saveSettings,
    spaceTargetsPractice: practiceController.draft?.referenceMediaPath != null,
    isCompact:
        playerController.mediaPath != null &&
        !_workbenchExpanded &&
        !immersiveMode.immersive,
    mediaTitle: playerController.mediaPath == null
        ? null
        : playerController.mediaTitle ??
              widget.pathHelper.basename(playerController.mediaPath!),
    onExpand: _expandWorkbench,
    isFullscreen: immersiveMode.immersive,
    onToggleFullscreen:
        playerController.mediaPath == null ||
            playerController.mediaKind != 'video'
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
