import '../data/repositories/resource_repository.dart';
import '../models/api_failure.dart';
import '../models/timeline.dart';
import '../models/types.dart';
import '../services/resource_export_file_service.dart';
import 'player_controller.dart';
import 'speech_enhancement_workflow_controller.dart';
import 'subtitle_controller.dart';

/// Owns the subtitle-resource and timeline-resource actions that panels
/// trigger (activate/archive/restore/delete/export, word/chunk/phone timeline
/// lifecycle, resource refresh). Context-free: confirmation and format-picker
/// dialogs stay with the host widget, which then calls the action here.
///
/// The host binds its runtime hooks once via [bind]; every action guards on
/// [isMounted] after awaits, mirroring the original `State.mounted` checks.
class ResourceActionsCoordinator {
  ResourceActionsCoordinator({
    required this.player,
    required this.subtitle,
    required this.speechEnhancement,
    required this.repository,
    this.exportFiles = const LocalResourceExportFileService(),
  });

  final PlayerController player;
  final SubtitleController subtitle;
  final SpeechEnhancementWorkflowController speechEnhancement;
  final ResourceRepository repository;
  final ResourceExportFileService exportFiles;

  late bool Function() isMounted;
  String Function(String key)? text;

  String _t(String key) => text?.call(key) ?? key;
  late Future<void> Function(String trackId) reloadSpeechEnhancements;
  late Future<void> Function(SubtitleTrack track, {required String nextStatus})
  activatePrimaryTrack;
  late Future<void> Function() reloadLearningEntries;

  void bind({
    required bool Function() isMounted,
    String Function(String key)? text,
    required Future<void> Function(String trackId) reloadSpeechEnhancements,
    required Future<void> Function(
      SubtitleTrack track, {
      required String nextStatus,
    })
    activatePrimaryTrack,
    required Future<void> Function() reloadLearningEntries,
  }) {
    this.isMounted = isMounted;
    this.text = text;
    this.reloadSpeechEnhancements = reloadSpeechEnhancements;
    this.activatePrimaryTrack = activatePrimaryTrack;
    this.reloadLearningEntries = reloadLearningEntries;
  }

  // ── Timeline resource loading ──

  Future<void> loadTimelineResource(String trackId) async {
    if (!speechEnhancement.repository.isAvailable) return;
    final result = await speechEnhancement.loadTimelineResource(
      trackId: trackId,
      previous: existingTimelineResourceState(),
    );
    if (!isMounted() || subtitle.primaryTrack?.id != trackId) return;
    applyTimelineResource(result);
    await loadContentFit(trackId);
  }

  /// Content fit is decoration, never a gate (ADR 0018): failures clear the
  /// card silently instead of surfacing as a resource error.
  Future<void> loadContentFit(String trackId) async {
    if (!repository.isAvailable) return;
    ContentDifficultyProfile? profile;
    try {
      profile = await repository.contentFit(trackId);
    } catch (_) {
      profile = null;
    }
    if (!isMounted() || subtitle.primaryTrack?.id != trackId) return;
    subtitle.setContentFit(profile);
  }

  /// Snapshot of the currently-loaded timeline resource state; also used by
  /// the host's speech-enhancement flow as the stale-preserving baseline.
  ExistingTimelineResourceState existingTimelineResourceState() =>
      ExistingTimelineResourceState(
        wordSummaries: subtitle.wordTimelineSummaries,
        phoneSummaries: subtitle.phoneTimelineSummaries,
        chunkSummaries: subtitle.chunkTimelineSummaries,
        document: subtitle.llTimelineDocument,
      );

  void applyTimelineResource(TimelineResourceLoadResult result) {
    if (result.unavailable) {
      subtitle.setTimelineResourceError(result.error ?? '');
      return;
    }
    subtitle.setTimelineResource(
      summaries: result.wordSummaries,
      phoneSummaries: result.phoneSummaries,
      chunkSummaries: result.chunkSummaries,
      document: result.document,
      error: result.error,
    );
  }

  Future<void> refreshTimelineResource() async {
    // The user-facing refresh arrives via [refreshSubtitleResources], whose
    // loadSubtitleResources step already reported a missing core/media; this
    // guard only keeps the "refreshed" claim below honest, so it stays silent.
    if (!repository.isAvailable) return;
    final trackId = subtitle.primaryTrack?.id;
    // Without a primary track there is no timeline section to refresh; the
    // panel renders no timeline rows in that state, so the click stays silent.
    if (trackId == null) return;
    await loadTimelineResource(trackId);
    if (isMounted()) player.setStatus(_t('statusTimelineResourceRefreshed'));
  }

  // ── Subtitle resource list / capabilities ──

  Future<void> loadSubtitleResources({bool updateStatus = true}) async {
    final mediaId = player.mediaId;
    if (!repository.isAvailable || mediaId == null) {
      subtitle.setSubtitleResources(const []);
      subtitle.setSubtitleResourceCapabilities(const {});
      // [updateStatus] marks the user-triggered refresh path; internal
      // reloads pass false and stay silent by design.
      if (updateStatus) player.setStatus(_t('statusOpenMediaAndCoreFirst'));
      return;
    }
    try {
      final tracks = await repository.mediaSubtitles(mediaId);
      final capabilities = await _loadSubtitleResourceCapabilities(tracks);
      if (!isMounted() || player.mediaId != mediaId) return;
      subtitle.setSubtitleResources(tracks);
      subtitle.setSubtitleResourceCapabilities(capabilities);
      if (updateStatus) {
        player.setStatus(_t('statusSubtitleResourcesRefreshed'));
      }
    } catch (error) {
      if (isMounted() && updateStatus) {
        player.setStatus(
          _t('statusSubtitleResourcesUnavailable'),
          error: true,
          failure: repository.failureDetail(error),
        );
      }
    }
  }

  Future<Map<String, SubtitleResourceCapabilities>>
  _loadSubtitleResourceCapabilities(List<SubtitleTrack> tracks) async {
    final entries = await Future.wait(
      tracks.map((track) async {
        final failures = <ApiFailure>[];
        final wordTimings = await _loadOptionalResourceCapability(
          () => repository.wordTimings(track.id),
          failures,
        );
        final phoneSummaries = await _loadOptionalResourceCapability(
          () => repository.phoneTimelineSummaries(track.id),
          failures,
        );
        final chunkSummaries = await _loadOptionalResourceCapability(
          () => repository.chunkTimelineSummaries(track.id),
          failures,
        );
        return MapEntry(
          track.id,
          SubtitleResourceCapabilities.fromCounts(
            sentenceCount: track.cues.length,
            wordTimingCount: wordTimings.length,
            chunkCount: chunkSummaries.fold<int>(
              0,
              (total, summary) => total + summary.chunkCount,
            ),
            phoneCount: phoneSummaries.fold<int>(
              0,
              (total, summary) => total + summary.phoneCount,
            ),
            // The tooltip says only that some of this track's timeline
            // resources could not be read. Which loader failed, and what it
            // failed with, are in [failures] — diagnostics, not a tooltip.
            error: failures.isEmpty
                ? null
                : _t('statusTrackResourcesPartlyUnavailable'),
          ),
        );
      }),
    );
    return Map<String, SubtitleResourceCapabilities>.fromEntries(entries);
  }

  /// Runs one optional capability loader, recording the failure as a typed
  /// [ApiFailure] rather than as a sentence. A missing capability is a normal
  /// state for a track that has not been enhanced yet, so the caller degrades
  /// to an empty list either way.
  Future<List<T>> _loadOptionalResourceCapability<T>(
    Future<List<T>> Function() loader,
    List<ApiFailure> failures,
  ) async {
    try {
      return await loader();
    } catch (error) {
      failures.add(repository.failureDetail(error));
      return const [];
    }
  }

  Future<void> refreshSubtitleResources() async {
    await loadSubtitleResources();
    await refreshTimelineResource();
  }

  // ── Subtitle resource actions ──

  Future<void> activateSubtitleResource(SubtitleTrack track) async {
    try {
      await activatePrimaryTrack(
        track,
        nextStatus: 'Activated subtitle resource',
      );
      await loadSubtitleResources(updateStatus: false);
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          _t('statusSubtitleActivationFailed'),
          error: true,
          failure: repository.failureDetail(error),
        );
      }
    }
  }

  Future<void> archiveSubtitleResource(SubtitleTrack track) async {
    if (!repository.isAvailable) {
      // Unavailable State (CONTEXT.md): all the panel row actions below are
      // direct clicks, so a missing core is reported, never swallowed.
      player.setStatus(_t('statusConnectLocalCoreFirst'));
      return;
    }
    try {
      await repository.archiveSubtitle(track.id);
      _clearPrimaryTrackIfMatches(track);
      await loadSubtitleResources(updateStatus: false);
      if (isMounted()) player.setStatus(_t('statusSubtitleArchived'));
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          _t('statusSubtitleArchiveFailed'),
          error: true,
          failure: repository.failureDetail(error),
        );
      }
    }
  }

  Future<void> restoreSubtitleResource(SubtitleTrack track) async {
    if (!repository.isAvailable) {
      player.setStatus(_t('statusConnectLocalCoreFirst'));
      return;
    }
    try {
      await repository.restoreSubtitle(track.id);
      await loadSubtitleResources(updateStatus: false);
      if (isMounted()) player.setStatus(_t('statusSubtitleRestored'));
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          _t('statusSubtitleRestoreFailed'),
          error: true,
          failure: repository.failureDetail(error),
        );
      }
    }
  }

  /// Deletion is destructive; the host must confirm with the user before
  /// calling this.
  Future<void> deleteSubtitleResource(SubtitleTrack track) async {
    if (!repository.isAvailable) {
      player.setStatus(_t('statusConnectLocalCoreFirst'));
      return;
    }
    try {
      await repository.deleteSubtitle(track.id);
      _clearPrimaryTrackIfMatches(track);
      await loadSubtitleResources(updateStatus: false);
      if (isMounted()) player.setStatus(_t('statusSubtitleDeleted'));
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          _t('statusSubtitleDeleteFailed'),
          error: true,
          failure: repository.failureDetail(error),
        );
      }
    }
  }

  void _clearPrimaryTrackIfMatches(SubtitleTrack track) {
    if (subtitle.primaryTrack?.id != track.id) return;
    subtitle.setPrimaryTrack(null);
    subtitle.setCurrentPrimaryCue(null);
    subtitle.clearSpeechEnhancements();
  }

  Future<void> exportSubtitleSrt(SubtitleTrack track) async {
    if (!repository.isAvailable) {
      player.setStatus(_t('statusConnectLocalCoreFirst'));
      return;
    }
    try {
      final srt = await repository.exportSubtitleSrt(track.id);
      if (!await exportFiles.saveText(
        suggestedName: '${track.source}-${track.id}.srt',
        content: srt,
      )) {
        return;
      }
      if (isMounted()) player.setStatus(_t('statusSubtitleExportedSrt'));
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          _t('statusSubtitleExportFailed'),
          error: true,
          failure: repository.failureDetail(error),
        );
      }
    }
  }

  Future<void> exportLLTimelineResource(SubtitleTrack track) async {
    if (!repository.isAvailable) {
      player.setStatus(_t('statusConnectLocalCoreFirst'));
      return;
    }
    try {
      final document = await repository.exportTimeline(track.id);
      if (!await exportFiles.saveJson(
        suggestedName: '${track.source}-${track.id}.lltimeline.json',
        document: document.toJson(),
      )) {
        return;
      }
      if (isMounted()) player.setStatus(_t('statusLLTimelineExported'));
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          _t('statusLLTimelineExportFailed'),
          error: true,
          failure: repository.failureDetail(error),
        );
      }
    }
  }

  Future<void> changeTrackLanguage(SubtitleTrack track, String language) async {
    if (!repository.isAvailable) {
      player.setStatus(_t('statusConnectLocalCoreFirst'));
      return;
    }
    try {
      await repository.updateTrackLanguage(track.id, language);
      await loadSubtitleResources(updateStatus: false);
      if (subtitle.primaryTrack?.id == track.id) {
        final updated = subtitle.subtitleResources
            .where((t) => t.id == track.id)
            .firstOrNull;
        if (updated != null) {
          subtitle.setPrimaryTrack(updated);
        }
        await reloadLearningEntries();
      }
      if (isMounted()) {
        player.setStatus(
          _t('statusLanguageSet').replaceAll('{language}', language),
        );
      }
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          _t('statusLanguageUpdateFailed'),
          error: true,
          failure: repository.failureDetail(error),
        );
      }
    }
  }

  // ── Word / chunk / phone timeline lifecycle ──

  Future<void> activateWordTimeline(String timelineId) async {
    await _runTimelineAction(
      workingStatus: 'Activating WordTimeline...',
      doneStatus: 'WordTimeline activated',
      failurePrefix: 'WordTimeline activation failed',
      refreshResources: false,
      action: (_) => repository.activateWordTimeline(timelineId),
    );
  }

  Future<void> generateChunkTimeline() async {
    await _runTimelineAction(
      workingStatus: 'Generating ChunkTimeline...',
      doneStatus: 'ChunkTimeline generated',
      failurePrefix: 'ChunkTimeline generation failed',
      action: repository.generateChunkTimeline,
    );
  }

  Future<void> activateChunkTimeline(String timelineId) async {
    await _runTimelineAction(
      workingStatus: 'Activating ChunkTimeline...',
      doneStatus: 'ChunkTimeline activated',
      failurePrefix: 'ChunkTimeline activation failed',
      action: (_) => repository.activateChunkTimeline(timelineId),
    );
  }

  Future<void> archiveChunkTimeline(String timelineId) async {
    await _runTimelineAction(
      doneStatus: 'ChunkTimeline archived',
      failurePrefix: 'ChunkTimeline archive failed',
      action: (_) => repository.archiveChunkTimeline(timelineId),
    );
  }

  Future<void> deleteChunkTimeline(String timelineId) async {
    await _runTimelineAction(
      doneStatus: 'ChunkTimeline deleted',
      failurePrefix: 'ChunkTimeline delete failed',
      action: (_) => repository.deleteChunkTimeline(timelineId),
    );
  }

  Future<void> activatePhoneTimeline(String timelineId) async {
    await _runTimelineAction(
      workingStatus: 'Activating PhoneTimeline...',
      doneStatus: 'PhoneTimeline activated',
      failurePrefix: 'PhoneTimeline activation failed',
      action: (_) => repository.activatePhoneTimeline(timelineId),
    );
  }

  Future<void> archivePhoneTimeline(String timelineId) async {
    await _runTimelineAction(
      doneStatus: 'PhoneTimeline archived',
      failurePrefix: 'PhoneTimeline archive failed',
      action: (_) => repository.archivePhoneTimeline(timelineId),
    );
  }

  Future<void> deletePhoneTimeline(String timelineId) async {
    await _runTimelineAction(
      doneStatus: 'PhoneTimeline deleted',
      failurePrefix: 'PhoneTimeline delete failed',
      action: (_) => repository.deletePhoneTimeline(timelineId),
    );
  }

  /// Shared skeleton for timeline lifecycle actions: guard on api + primary
  /// track, run the API call, then refresh speech enhancements (and the
  /// resource list unless [refreshResources] is false) while dropping stale
  /// results if the primary track changed mid-flight.
  Future<void> _runTimelineAction({
    String? workingStatus,
    required String doneStatus,
    required String failurePrefix,
    bool refreshResources = true,
    required Future<void> Function(String trackId) action,
  }) async {
    if (!repository.isAvailable) {
      // Timeline lifecycle buttons are direct clicks; report the missing core.
      player.setStatus(_t('statusConnectLocalCoreFirst'));
      return;
    }
    final trackId = subtitle.primaryTrack?.id;
    // The lifecycle buttons only render on the active primary track's
    // timeline rows, so a missing track here is a stale click; stay silent.
    if (trackId == null) return;
    try {
      if (workingStatus != null) player.setStatus(workingStatus);
      await action(trackId);
      if (!isMounted() || subtitle.primaryTrack?.id != trackId) return;
      await reloadSpeechEnhancements(trackId);
      if (refreshResources) {
        await loadSubtitleResources(updateStatus: false);
      }
      if (isMounted()) player.setStatus(doneStatus);
    } catch (error) {
      if (isMounted()) {
        player.setStatus(
          failurePrefix,
          error: true,
          failure: repository.failureDetail(error),
        );
      }
    }
  }
}
