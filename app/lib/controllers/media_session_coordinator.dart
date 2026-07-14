import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../models/timeline.dart';
import '../player_adapter.dart';
import '../services/api_service.dart';
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
  });

  final DesktopPlayerAdapter adapter;
  final PlayerController player;
  final SubtitleController subtitle;
  final LearningController learning;
  final SettingsController settings;
  final SpeechEnhancementWorkflowController speechEnhancement;
  final ResourceActionsCoordinator resourceActions;

  late LocalApi? Function() getApi;
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
    required LocalApi? Function() getApi,
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
    this.getApi = getApi;
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
    const group = XTypeGroup(
      label: 'media',
      extensions: ['mp4', 'mkv', 'mov', 'webm', 'm4a', 'mp3', 'wav', 'flac'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    await openMediaPath(file.path);
  }

  Future<void> openMediaPath(String path) async {
    final api = getApi();
    final previousMediaId = player.mediaId;
    final previousPosition = player.position;
    final previousProgressSave = previousMediaId == null
        ? Future<void>.value()
        : api?.saveProgress(previousMediaId, previousPosition) ??
              Future<void>.value();
    player.setStatus('Opening ${path.split(Platform.pathSeparator).last}');
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
      if (isMounted()) player.setStatus('Playback failed: $error');
      return;
    }
    Object? coreError;
    try {
      await previousProgressSave;
      final media = await api?.registerMedia(path);
      if (media != null) {
        final id = media['id'] as String;
        final saved = await api?.readProgress(id);
        player.setMedia(
          id: id,
          path: path,
          title: media['title'] as String,
          fingerprint: media['fingerprint'] as String,
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
        player.setStatus(
          coreError == null
              ? 'Playing ${path.split(Platform.pathSeparator).last}'
              : 'Playing locally; core unavailable: $coreError',
        );
      }
    } catch (error) {
      if (isMounted()) player.setStatus('Playback failed: $error');
    }
  }

  // ── Subtitle import ──

  Future<void> openSubtitle({required bool secondary}) async {
    if (player.mediaId == null || getApi() == null) {
      player.setStatus('Open media and connect the local core first');
      return;
    }
    const group = XTypeGroup(label: 'subtitles', extensions: ['srt', 'vtt']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    await openSubtitlePath(file.path, secondary: secondary);
  }

  Future<void> openSubtitlePath(String path, {required bool secondary}) async {
    try {
      final value = await getApi()!.importSubtitle(player.mediaId!, path);
      await adapter.disableNativeSubtitles();
      final imported = SubtitleTrack.fromJson(value);
      if (secondary) {
        subtitle.setSecondaryTrack(imported);
        subtitle.setCurrentSecondaryCue(
          subtitle.secondaryCursor.current(player.position),
        );
        player.setStatus(
          'Loaded secondary subtitle: '
          '${path.split(Platform.pathSeparator).last}',
        );
      } else {
        await usePrimarySubtitleTrack(
          imported,
          nextStatus:
              'Loaded primary subtitle: '
              '${path.split(Platform.pathSeparator).last}',
        );
      }
      await resourceActions.loadSubtitleResources(updateStatus: false);
    } catch (error) {
      player.setStatus('Subtitle import failed: $error');
    }
  }

  // ── LLTimeline import ──

  Future<void> openLLTimelineResource() async {
    final service = getApi();
    final mediaId = player.mediaId;
    if (service == null || mediaId == null) {
      player.setStatus('Open media and connect the local core first');
      return;
    }
    const group = XTypeGroup(label: 'LLTimeline', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;
    try {
      player.setStatus('Importing LLTimeline resource...');
      final decoded = jsonDecode(await File(file.path).readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('LLTimeline JSON must be an object');
      }
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
          if (isMounted()) player.setStatus('LLTimeline import cancelled');
          return;
        }
      }
      final value = await service.importLLTimelineForMedia(
        mediaId,
        decoded,
        allowMismatch: allowMismatch,
      );
      final imported = SubtitleTrack.fromJson(value);
      await usePrimarySubtitleTrack(
        imported,
        nextStatus:
            'Imported LLTimeline resource: '
            '${file.path.split(Platform.pathSeparator).last}',
      );
      subtitle.setTimelineResource(
        summaries: subtitle.wordTimelineSummaries,
        phoneSummaries: subtitle.phoneTimelineSummaries,
        chunkSummaries: subtitle.chunkTimelineSummaries,
        document: LLTimelineDocument.fromJson(decoded),
        error: subtitle.timelineResourceError,
      );
      await resourceActions.loadSubtitleResources(updateStatus: false);
      learning.selectSidePanel(1);
    } catch (error) {
      player.setStatus('LLTimeline import failed: $error');
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
    final service = getApi();
    if (service == null) return;
    try {
      final capability = await service.syntaxCapability();
      if (capability.isReady) {
        await service.runTrackSyntaxAnalysis(trackId);
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
    final service = getApi();
    if (service == null) return null;
    final result = await speechEnhancement.loadSpeechEnhancements(
      service: service,
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
      player.setStatus(
        'Speech enhancements partially unavailable: '
        '${result.errors.join('; ')}',
      );
    }
    return result;
  }
}
