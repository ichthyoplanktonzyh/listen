import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../models/timeline.dart';
import '../models/types.dart';
import '../services/api_service.dart';
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
  });

  final PlayerController player;
  final SubtitleController subtitle;
  final SpeechEnhancementWorkflowController speechEnhancement;

  late LocalApi? Function() getApi;
  late bool Function() isMounted;
  late Future<void> Function(String trackId) reloadSpeechEnhancements;
  late Future<void> Function(SubtitleTrack track, {required String nextStatus})
  activatePrimaryTrack;
  late Future<void> Function() reloadLearningEntries;

  void bind({
    required LocalApi? Function() getApi,
    required bool Function() isMounted,
    required Future<void> Function(String trackId) reloadSpeechEnhancements,
    required Future<void> Function(
      SubtitleTrack track, {
      required String nextStatus,
    })
    activatePrimaryTrack,
    required Future<void> Function() reloadLearningEntries,
  }) {
    this.getApi = getApi;
    this.isMounted = isMounted;
    this.reloadSpeechEnhancements = reloadSpeechEnhancements;
    this.activatePrimaryTrack = activatePrimaryTrack;
    this.reloadLearningEntries = reloadLearningEntries;
  }

  // ── Timeline resource loading ──

  Future<void> loadTimelineResource(String trackId) async {
    final service = getApi();
    if (service == null) return;
    final result = await speechEnhancement.loadTimelineResource(
      service: service,
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
    final service = getApi();
    if (service == null) return;
    ContentDifficultyProfile? profile;
    try {
      profile = await service.trackContentFit(trackId);
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
    final trackId = subtitle.primaryTrack?.id;
    if (trackId == null) return;
    await loadTimelineResource(trackId);
    if (isMounted()) player.setStatus('Timeline resource refreshed');
  }

  // ── Subtitle resource list / capabilities ──

  Future<void> loadSubtitleResources({bool updateStatus = true}) async {
    final service = getApi();
    final mediaId = player.mediaId;
    if (service == null || mediaId == null) {
      subtitle.setSubtitleResources(const []);
      subtitle.setSubtitleResourceCapabilities(const {});
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
      if (!isMounted() || player.mediaId != mediaId) return;
      subtitle.setSubtitleResources(tracks);
      subtitle.setSubtitleResourceCapabilities(capabilities);
      if (updateStatus) player.setStatus('Subtitle resources refreshed');
    } catch (error) {
      if (isMounted() && updateStatus) {
        player.setStatus('Subtitle resources unavailable: $error');
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
        player.setStatus('Subtitle activation failed: $error');
      }
    }
  }

  Future<void> archiveSubtitleResource(SubtitleTrack track) async {
    final service = getApi();
    if (service == null) return;
    try {
      await service.archiveSubtitle(track.id);
      _clearPrimaryTrackIfMatches(track);
      await loadSubtitleResources(updateStatus: false);
      if (isMounted()) player.setStatus('Archived subtitle resource');
    } catch (error) {
      if (isMounted()) player.setStatus('Subtitle archive failed: $error');
    }
  }

  Future<void> restoreSubtitleResource(SubtitleTrack track) async {
    final service = getApi();
    if (service == null) return;
    try {
      await service.restoreSubtitle(track.id);
      await loadSubtitleResources(updateStatus: false);
      if (isMounted()) player.setStatus('Restored subtitle resource');
    } catch (error) {
      if (isMounted()) player.setStatus('Subtitle restore failed: $error');
    }
  }

  /// Deletion is destructive; the host must confirm with the user before
  /// calling this.
  Future<void> deleteSubtitleResource(SubtitleTrack track) async {
    final service = getApi();
    if (service == null) return;
    try {
      await service.deleteSubtitle(track.id);
      _clearPrimaryTrackIfMatches(track);
      await loadSubtitleResources(updateStatus: false);
      if (isMounted()) player.setStatus('Deleted subtitle resource');
    } catch (error) {
      if (isMounted()) player.setStatus('Subtitle delete failed: $error');
    }
  }

  void _clearPrimaryTrackIfMatches(SubtitleTrack track) {
    if (subtitle.primaryTrack?.id != track.id) return;
    subtitle.setPrimaryTrack(null);
    subtitle.setCurrentPrimaryCue(null);
    subtitle.clearSpeechEnhancements();
  }

  Future<void> exportSubtitleSrt(SubtitleTrack track) async {
    final service = getApi();
    if (service == null) return;
    try {
      final location = await getSaveLocation(
        suggestedName: '${track.source}-${track.id}.srt',
      );
      if (location == null) return;
      final srt = await service.exportSubtitleSrt(track.id);
      await File(location.path).writeAsString(srt);
      if (isMounted()) player.setStatus('Exported SRT subtitle resource');
    } catch (error) {
      if (isMounted()) player.setStatus('Subtitle export failed: $error');
    }
  }

  Future<void> exportLLTimelineResource(SubtitleTrack track) async {
    final service = getApi();
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
      if (isMounted()) player.setStatus('Exported LLTimeline resource');
    } catch (error) {
      if (isMounted()) player.setStatus('LLTimeline export failed: $error');
    }
  }

  Future<void> changeTrackLanguage(SubtitleTrack track, String language) async {
    final service = getApi();
    if (service == null) return;
    try {
      await service.updateTrackLanguage(track.id, language);
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
      if (isMounted()) player.setStatus('Language set to $language');
    } catch (error) {
      if (isMounted()) {
        player.setStatus('Failed to update language: $error');
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
      action: (service, _) => service.activateWordTimeline(timelineId),
    );
  }

  Future<void> generateChunkTimeline() async {
    await _runTimelineAction(
      workingStatus: 'Generating ChunkTimeline...',
      doneStatus: 'ChunkTimeline generated',
      failurePrefix: 'ChunkTimeline generation failed',
      action: (service, trackId) =>
          service.generateChunkTimeline(trackId, status: 'active'),
    );
  }

  Future<void> activateChunkTimeline(String timelineId) async {
    await _runTimelineAction(
      workingStatus: 'Activating ChunkTimeline...',
      doneStatus: 'ChunkTimeline activated',
      failurePrefix: 'ChunkTimeline activation failed',
      action: (service, _) => service.activateChunkTimeline(timelineId),
    );
  }

  Future<void> archiveChunkTimeline(String timelineId) async {
    await _runTimelineAction(
      doneStatus: 'ChunkTimeline archived',
      failurePrefix: 'ChunkTimeline archive failed',
      action: (service, _) => service.archiveChunkTimeline(timelineId),
    );
  }

  Future<void> deleteChunkTimeline(String timelineId) async {
    await _runTimelineAction(
      doneStatus: 'ChunkTimeline deleted',
      failurePrefix: 'ChunkTimeline delete failed',
      action: (service, _) => service.deleteChunkTimeline(timelineId),
    );
  }

  Future<void> activatePhoneTimeline(String timelineId) async {
    await _runTimelineAction(
      workingStatus: 'Activating PhoneTimeline...',
      doneStatus: 'PhoneTimeline activated',
      failurePrefix: 'PhoneTimeline activation failed',
      action: (service, _) => service.activatePhoneTimeline(timelineId),
    );
  }

  Future<void> archivePhoneTimeline(String timelineId) async {
    await _runTimelineAction(
      doneStatus: 'PhoneTimeline archived',
      failurePrefix: 'PhoneTimeline archive failed',
      action: (service, _) => service.archivePhoneTimeline(timelineId),
    );
  }

  Future<void> deletePhoneTimeline(String timelineId) async {
    await _runTimelineAction(
      doneStatus: 'PhoneTimeline deleted',
      failurePrefix: 'PhoneTimeline delete failed',
      action: (service, _) => service.deletePhoneTimeline(timelineId),
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
    required Future<void> Function(LocalApi service, String trackId) action,
  }) async {
    final service = getApi();
    final trackId = subtitle.primaryTrack?.id;
    if (service == null || trackId == null) return;
    try {
      if (workingStatus != null) player.setStatus(workingStatus);
      await action(service, trackId);
      if (!isMounted() || subtitle.primaryTrack?.id != trackId) return;
      await reloadSpeechEnhancements(trackId);
      if (refreshResources) {
        await loadSubtitleResources(updateStatus: false);
      }
      if (isMounted()) player.setStatus(doneStatus);
    } catch (error) {
      if (isMounted()) {
        player.setStatus('$failurePrefix: $error');
      }
    }
  }
}
