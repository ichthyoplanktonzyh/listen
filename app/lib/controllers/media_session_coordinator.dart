import 'dart:async';

import '../data/repositories/media_session_repository.dart';
import '../data/repositories/subtitle_analysis_repository.dart';
import '../models/timeline.dart';
import '../player_adapter.dart';
import '../services/media_import_file_service.dart';
import 'learning_controller.dart';
import 'player_controller.dart';
import 'resource_actions_coordinator.dart';
import 'settings_controller.dart';
import 'speech_enhancement_workflow_controller.dart';
import 'subtitle_controller.dart';

/// Owns the media/session flows: opening media, importing subtitle and
/// LLTimeline files, activating a primary track, loading generated tracks and
/// speech enhancements. Context-free: dialogs (fingerprint-mismatch confirm)
/// and localized status composition stay with the host and enter via [bind].
class MediaSessionCoordinator {
  MediaSessionCoordinator({
    required this.adapter,
    required this.player,
    required this.subtitle,
    required this.learning,
    required this.settings,
    required this.speechEnhancement,
    required this.resourceActions,
    required this.repository,
    required this.subtitleAnalysis,
    this.importFiles = const LocalMediaImportFileService(),
  });

  final DesktopPlayerAdapter adapter;
  final PlayerController player;
  final SubtitleController subtitle;
  final LearningController learning;
  final SettingsController settings;
  final SpeechEnhancementWorkflowController speechEnhancement;
  final ResourceActionsCoordinator resourceActions;
  final MediaSessionRepository repository;
  final SubtitleAnalysisRepository subtitleAnalysis;
  final MediaImportFileService importFiles;

  late bool Function() isMounted;
  late String Function(String key) text;
  late Future<bool> Function({
    required String resourceFingerprint,
    required String currentFingerprint,
  })
  confirmLLTimelineMismatch;
  late void Function() onMediaSwitched;
  late Future<void> Function() reloadLearningEntries;
  late Future<void> Function(Cue? cue) loadPhraseCandidates;
  late String Function(SpeechEnhancementLoadResult? result)
  generatedPrimaryStatus;

  void bind({
    required bool Function() isMounted,
    required String Function(String key) text,
    required Future<bool> Function({
      required String resourceFingerprint,
      required String currentFingerprint,
    })
    confirmLLTimelineMismatch,
    required void Function() onMediaSwitched,
    required Future<void> Function() reloadLearningEntries,
    required Future<void> Function(Cue? cue) loadPhraseCandidates,
    required String Function(SpeechEnhancementLoadResult? result)
    generatedPrimaryStatus,
  }) {
    this.isMounted = isMounted;
    this.text = text;
    this.confirmLLTimelineMismatch = confirmLLTimelineMismatch;
    this.onMediaSwitched = onMediaSwitched;
    this.reloadLearningEntries = reloadLearningEntries;
    this.loadPhraseCandidates = loadPhraseCandidates;
    this.generatedPrimaryStatus = generatedPrimaryStatus;
  }

  // ── Media open ──

  Future<void> openMedia() async {
    final path = await importFiles.pickMedia();
    if (path == null) return;
    await openMediaPath(path);
  }

  Future<void> openMediaPath(String path) async {
    final previousMediaId = player.mediaId;
    final previousPosition = player.position;
    final previousProgressSave = previousMediaId == null
        ? Future<void>.value()
        : repository.isAvailable
        ? repository.saveProgress(previousMediaId, previousPosition)
        : Future<void>.value();
    player.setStatus(
      text(
        'statusOpeningFile',
      ).replaceAll('{name}', importFiles.basename(path)),
    );
    onMediaSwitched();
    player.clearMedia();
    player.setMediaPath(path);
    player.setPosition(Duration.zero);
    player.setDuration(Duration.zero);
    subtitle.setPrimaryTrack(null);
    subtitle.setSecondaryTrack(null);
    subtitle.setCurrentPrimaryCue(null);
    subtitle.setCurrentSecondaryCue(null);
    subtitle.setSubtitleResources(const []);
    subtitle.setSubtitleResourceCapabilities(const {});
    subtitle.clearSpeechEnhancements();
    player.setSourceLoop(null, null);
    try {
      await adapter.open(path, play: false);
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          text('statusPlaybackFailed'),
          error: true,
          failure: repository.failureDetail(error),
        );
      }
      return;
    }
    Object? coreError;
    try {
      await previousProgressSave;
      if (repository.isAvailable) {
        final media = await repository.registerMedia(path);
        final id = media.id;
        final saved = await repository.readProgress(id);
        player.setMedia(
          id: id,
          path: path,
          title: media.title,
          fingerprint: media.fingerprint,
        );
        if (saved != null && saved > Duration.zero) {
          await adapter.seek(saved);
          player.setPosition(saved);
        }
        await resourceActions.loadSubtitleResources(updateStatus: false);
      }
    } catch (error) {
      coreError = error;
    }
    try {
      await adapter.play();
      if (isMounted()) {
        // Only the healthy branch is playback chatter; the degraded one
        // reports on the core, so health indicators must keep showing it.
        player.setStatus(
          coreError == null
              ? text(
                  'statusPlayingFile',
                ).replaceAll('{name}', importFiles.basename(path))
              : text('statusPlayingCoreUnavailable'),
          playback: coreError == null,
          // The file is playing; only the core round-trip failed. The sentence
          // says that much, and the exception behind it — which was being
          // interpolated into the status line one `catch` away from where it
          // was raised — stays typed.
          failure: coreError == null
              ? null
              : repository.failureDetail(coreError),
        );
      }
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          text('statusPlaybackFailed'),
          error: true,
          failure: repository.failureDetail(error),
        );
      }
    }
  }

  // ── Subtitle import ──

  Future<void> openSubtitle({required bool secondary}) async {
    if (player.mediaId == null || !repository.isAvailable) {
      player.setStatus(text('statusOpenMediaAndCoreFirst'));
      return;
    }
    final path = await importFiles.pickSubtitle();
    if (path == null) return;
    await openSubtitlePath(path, secondary: secondary);
  }

  Future<void> openSubtitlePath(String path, {required bool secondary}) async {
    try {
      final imported = await repository.importSubtitle(player.mediaId!, path);
      await adapter.disableNativeSubtitles();
      if (secondary) {
        subtitle.setSecondaryTrack(imported);
        subtitle.setCurrentSecondaryCue(
          subtitle.secondaryCursor.current(player.position),
        );
        player.setStatus(
          text(
            'statusSecondarySubtitleLoaded',
          ).replaceAll('{name}', importFiles.basename(path)),
        );
      } else {
        await usePrimarySubtitleTrack(
          imported,
          nextStatus: 'Loaded primary subtitle: ${importFiles.basename(path)}',
        );
      }
      await resourceActions.loadSubtitleResources(updateStatus: false);
    } catch (error) {
      player.setStatus(
        text('statusSubtitleImportFailed'),
        error: true,
        failure: repository.failureDetail(error),
      );
    }
  }

  // ── LLTimeline import ──

  Future<void> openLLTimelineResource() async {
    final mediaId = player.mediaId;
    if (!repository.isAvailable || mediaId == null) {
      player.setStatus(text('statusOpenMediaAndCoreFirst'));
      return;
    }
    try {
      player.setStatus(text('statusImportingLLTimeline'));
      final selected = await importFiles.pickTimeline();
      if (selected == null) return;
      final decoded = selected.document;
      final resourceFingerprint = _llTimelineMediaFingerprint(decoded);
      final currentFingerprint = player.mediaFingerprint;
      var allowMismatch = false;
      if (resourceFingerprint != null &&
          currentFingerprint != null &&
          resourceFingerprint != currentFingerprint) {
        allowMismatch = await confirmLLTimelineMismatch(
          resourceFingerprint: resourceFingerprint,
          currentFingerprint: currentFingerprint,
        );
        if (!allowMismatch) {
          if (isMounted()) {
            player.setStatus(text('statusLLTimelineImportCancelled'));
          }
          return;
        }
      }
      final imported = await repository.importTimeline(
        mediaId: mediaId,
        document: decoded,
        allowMismatch: allowMismatch,
      );
      await usePrimarySubtitleTrack(
        imported,
        nextStatus:
            'Imported LLTimeline resource: ${importFiles.basename(selected.path)}',
      );
      subtitle.setTimelineResource(
        summaries: subtitle.wordTimelineSummaries,
        phoneSummaries: subtitle.phoneTimelineSummaries,
        chunkSummaries: subtitle.chunkTimelineSummaries,
        document: LLTimelineDocument.fromJson(decoded),
        error: subtitle.timelineResourceError,
      );
      await resourceActions.loadSubtitleResources(updateStatus: false);
    } catch (error) {
      player.setStatus(
        text('statusLLTimelineImportFailed'),
        error: true,
        failure: repository.failureDetail(error),
      );
    }
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

  // ── Primary track activation and enhancements ──

  Future<SpeechEnhancementLoadResult?> usePrimarySubtitleTrack(
    SubtitleTrack track, {
    required String nextStatus,
  }) async {
    await adapter.disableNativeSubtitles();
    if (!isMounted()) return null;
    subtitle.clearSpeechEnhancements();
    subtitle.setPrimaryTrack(track);
    subtitle.setCurrentPrimaryCue(
      subtitle.primaryCursor.current(player.position),
    );
    player.setStatus(nextStatus);
    await reloadLearningEntries();
    await loadPhraseCandidates(subtitle.currentPrimaryCue);
    unawaited(_analyzeSyntaxWhenAvailable(track.id));
    return loadSpeechEnhancements(track.id);
  }

  Future<void> _analyzeSyntaxWhenAvailable(String trackId) async {
    if (!subtitleAnalysis.isAvailable) return;
    try {
      if (await subtitleAnalysis.syntaxReady()) {
        await subtitleAnalysis.analyzeTrackSyntax(trackId);
      }
    } catch (_) {
      // Optional enhancement: never disturb subtitle import or playback.
    }
  }

  Future<void> loadGeneratedTrack(
    SubtitleTrack imported,
    bool secondary,
  ) async {
    await adapter.disableNativeSubtitles();
    if (!isMounted()) return;
    if (secondary) {
      subtitle.setSecondaryTrack(imported);
      subtitle.setCurrentSecondaryCue(
        subtitle.secondaryCursor.current(player.position),
      );
      player.setStatus(text('generatedSecondarySubtitleLoaded'));
    } else {
      final result = await usePrimarySubtitleTrack(
        imported,
        nextStatus: text('loadingGeneratedPrimarySubtitle'),
      );
      if (isMounted() && subtitle.primaryTrack?.id == imported.id) {
        player.setStatus(generatedPrimaryStatus(result));
      }
    }
    await resourceActions.loadSubtitleResources(updateStatus: false);
  }

  Future<SpeechEnhancementLoadResult?> loadSpeechEnhancements(
    String trackId,
  ) async {
    if (!speechEnhancement.repository.isAvailable) return null;
    final result = await speechEnhancement.loadSpeechEnhancements(
      trackId: trackId,
      previousTimeline: resourceActions.existingTimelineResourceState(),
    );
    if (!isMounted() || subtitle.primaryTrack?.id != trackId) {
      return null;
    }
    resourceActions.applyTimelineResource(result.timeline);
    subtitle.setSpeechEnhancements(
      timingsBySentence: result.timingsBySentence,
      chunkPartitionsBySentence: result.chunkPartitionsBySentence,
      senseGroupsBySentence: result.senseGroupsBySentence,
      pronunciationBySentence: result.pronunciationBySentence,
      pronunciationProviders: result.pronunciationProviders,
      phoneticAnalysisBySentence: result.phoneticAnalysisBySentence,
    );
    subtitle.updateCurrentWord(
      player.position,
      enabled: settings.wordSyncVisible,
      chunkEnabled: settings.chunkHighlightActive,
    );
    subtitle.updateCurrentDetectedPhone(
      player.position,
      enabled:
          settings.settings.phonemeRibbonVisible ||
          settings.settings.soundPatternRibbonVisible,
    );
    if (result.errors.isNotEmpty && isMounted()) {
      // This one was invisible to the source gate: the exceptions reached the
      // status line as `result.errors`, six loaders and one `join('; ')` away
      // from the `catch` that raised them. They are typed now, so only the
      // named state is left to print.
      player.setStatus(
        text('statusSpeechEnhancementsPartial'),
        error: true,
        failure: result.errors.first,
      );
    }
    return result;
  }
}
