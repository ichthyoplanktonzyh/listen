import 'dart:async';

import '../data/repositories/learning_material_repository.dart';
import '../data/repositories/media_session_repository.dart';
import '../data/repositories/subtitle_analysis_repository.dart';
import '../models/learning_material.dart';
import '../models/timeline.dart';
import '../models/types.dart';
import '../player_adapter.dart';
import '../services/managed_asset_store.dart';
import '../services/media_import_file_service.dart';
import 'learning_controller.dart';
import 'player_controller.dart';
import 'resource_actions_coordinator.dart';
import 'settings_controller.dart';
import 'speech_enhancement_workflow_controller.dart';
import 'subtitle_controller.dart';

/// Owns the media/session flows: opening media, importing subtitle and
/// LLTimeline files, activating a primary track, and the retention decision
/// (Keep / reference in place / unretain). Context-free: dialogs
/// (fingerprint-mismatch confirm) and localized status composition stay with
/// the host and enter via [bind].
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
    required this.managedStore,
    required this.materialRepository,
    this.onLibraryChanged,
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
  final ManagedAssetStoreService managedStore;
  final MediaImportFileService importFiles;

  /// Notified after membership or registration changes that affect the
  /// library list (open, Keep, reference, unretain), so the library surface
  /// can refresh itself instead of showing a stale snapshot. Best-effort:
  /// a missing or failing refresh never fails the session flow.
  final Future<void> Function()? onLibraryChanged;

  /// The learning material bound to the current media, when one was resolved
  /// from Core. Material retention is the session's membership authority:
  /// once a material is bound, Keep/unretain membership flows act on it.
  ///
  /// Nullable on purpose: no media, Core unreachable, or a failed resolution
  /// all leave it null, and the session then falls back to the media-level
  /// membership evidence from registration.
  MaterialDetails? currentMaterial;

  /// The learning-material boundary. Required: the composition root always
  /// injects it, and every retention/membership flow reads it rather than the
  /// legacy media-level projection.
  final LearningMaterialRepository materialRepository;

  /// Session generation. Every async open, material resolve, and retention
  /// result application captures the epoch it started under and validates
  /// before touching state, so a newer local open or an external online clear
  /// ([beginExternalMediaSwitch]) can never be overwritten by a late
  /// completion from an older session.
  int _sessionEpoch = 0;

  bool _isStale(int epoch) => epoch != _sessionEpoch;

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
  }) {
    this.isMounted = isMounted;
    this.text = text;
    this.confirmLLTimelineMismatch = confirmLLTimelineMismatch;
    this.onMediaSwitched = onMediaSwitched;
    this.reloadLearningEntries = reloadLearningEntries;
    this.loadPhraseCandidates = loadPhraseCandidates;
    // The session's material is bound to the player's media identity. Every
    // media switch — a local open ([openMediaPath]) or a switch that runs
    // through another flow, such as the online import clearing the player
    // directly ([beginExternalMediaSwitch]) — drops the material and bumps
    // the session epoch synchronously, before any async resolution or
    // retention result can repopulate it.
  }

  /// A media switch that runs entirely outside [openMediaPath] — the online
  /// import flow clears the player directly. Narrow and synchronous: it bumps
  /// the session epoch (invalidating every in-flight open, material resolve,
  /// and retention result application) and drops the session's material before
  /// the player is cleared.
  void beginExternalMediaSwitch() {
    _sessionEpoch++;
    currentMaterial = null;
  }

  // ── Media open ──

  Future<void> openMedia() async {
    final path = await importFiles.pickMedia();
    if (path == null) return;
    await openMediaPath(path);
  }

  Future<void> openMediaPath(String path) async {
    final sessionEpoch = ++_sessionEpoch;
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
    // A different media has a different material graph; drop the previous
    // session's material synchronously with the media switch.
    currentMaterial = null;
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
      if (isMounted() && !_isStale(sessionEpoch)) {
        player.setStatus(
          text('statusPlaybackFailed'),
          error: true,
          failure: repository.failureDetail(error),
        );
      }
      return;
    }
    if (_isStale(sessionEpoch)) return;
    Object? coreError;
    Duration? saved;
    final coreAvailable = repository.isAvailable;
    try {
      await previousProgressSave;
      if (_isStale(sessionEpoch)) return;
      if (repository.isAvailable) {
        // Opening local media is Temporary Material: playable immediately, but
        // never a Personal Library membership by itself (CONTEXT.md Retention
        // Decision — the learner's explicit Keep adds membership later).
        final media = await repository.registerMedia(path, retain: false);
        if (_isStale(sessionEpoch)) return;
        final id = media.id;
        saved = await repository.readProgress(id);
        if (_isStale(sessionEpoch)) return;
        player.setMedia(
          id: id,
          path: path,
          title: media.title,
          fingerprint: media.fingerprint,
        );
        player.setMediaRetained(media.retainedAtMs != null);
      }
    } catch (error) {
      if (_isStale(sessionEpoch)) return;
      coreError = error;
    }
    if (_isStale(sessionEpoch)) return;
    try {
      // Playback starts before the restore seek, and the restore seek runs
      // before the subtitle auto-select. A paused seek is applied by the
      // player but its position is not observable until playback renders, and
      // the auto-select's disableNativeSubtitles() (setActiveTracks([]))
      // resets a paused seek to zero — the same call during playback does
      // not. (Real incident: progress restore always restarted at 0:00.)
      await adapter.play();
      if (_isStale(sessionEpoch)) return;
      if (saved != null && saved > Duration.zero) {
        await adapter.seek(saved);
        if (_isStale(sessionEpoch)) return;
        player.setPosition(saved);
      }
      if (coreAvailable && coreError == null) {
        // Registration creates (or resolves) the deterministic material graph,
        // so the media resolves to a material immediately. Material retention
        // is the session's membership authority from here on.
        await _refreshCurrentMaterial();
        if (_isStale(sessionEpoch)) return;
        await resourceActions.loadSubtitleResources(updateStatus: false);
        if (_isStale(sessionEpoch)) return;
        // A newly registered media changes the library; refresh it instead of
        // leaving a stale snapshot behind. Never gating, never blocking the
        // workbench.
        unawaited(_notifyLibraryChanged());
        if (_isStale(sessionEpoch)) return;
        try {
          // The workbench owns "does this media have a learning transcript".
          // After the resource list lands, pick the single obvious candidate —
          // never guess when there are several, and never leave the user
          // staring at an empty panel when the core already holds the answer.
          await reconcileLearningTranscript();
        } catch (_) {
          // Convenience, not a gate: a failed auto-select must not turn the
          // media-open status into a core failure. The readiness surface
          // still shows the chooser/prepare path from the loaded resources.
        }
        if (_isStale(sessionEpoch)) return;
      }
      if (isMounted() && !_isStale(sessionEpoch)) {
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
      if (isMounted() && !_isStale(sessionEpoch)) {
        player.setStatus(
          text('statusPlaybackFailed'),
          error: true,
          failure: repository.failureDetail(error),
        );
      }
    }
  }

  // ── Material resolution ──

  /// Resolves the learning material bound to the current media and makes it
  /// the session's membership authority.
  ///
  /// Deliberately non-gating: a resolution failure never blocks playback or
  /// the media-open status (which reports registration round-trips, not
  /// enrichment reads). It only clears [currentMaterial] — the session then
  /// falls back to the media-level membership evidence from the successful
  /// registration — and the stable unable state covers retention flows that
  /// need a material.
  Future<void> _refreshCurrentMaterial() async {
    final mediaId = player.mediaId;
    if (mediaId == null || !materialRepository.isAvailable) {
      currentMaterial = null;
      return;
    }
    final sessionEpoch = _sessionEpoch;
    try {
      final details = await materialRepository.resolveMaterialForMedia(mediaId);
      if (_isStale(sessionEpoch)) return;
      currentMaterial = details;
      player.setMediaRetained(details.material.retainedAtMs != null);
    } catch (_) {
      if (!_isStale(sessionEpoch)) currentMaterial = null;
    }
  }

  /// Best-effort library refresh after a membership or registration change.
  /// A missing callback or a failing refresh never fails the caller.
  Future<void> _notifyLibraryChanged() async {
    final refresh = onLibraryChanged;
    if (refresh == null) return;
    try {
      await refresh();
    } on Object {
      // Library refresh is a background concern; the session outcome is
      // already reported.
    }
  }

  // ── Retention: Keep / reference in place / unretain ──

  /// The default Keep: copy the current Temporary Material into the managed
  /// store (the original is left untouched), verify the copy byte-for-byte,
  /// then re-register the managed path with retain true. Only after the copy
  /// is verified and Core accepted it does the session rebind to the managed
  /// path — media identity is fingerprint-derived, so the id, learning state
  /// and position all survive the rebind.
  ///
  /// A new copy is deleted only in two cases: Core registration fails after
  /// this operation created it (the media stays Temporary), or the session
  /// went stale before registration started (a newer open or online clear owns
  /// the player, and the never-registered copy is orphaned). Once registration
  /// with retain true succeeds, the copy is real Personal Library membership:
  /// no later material resolve, state write, or status failure deletes it, and
  /// a late successful registration keeps that membership without rebinding
  /// the newer session's player. A pre-existing deduplication target is shared
  /// and is never deleted. Every failure branch is epoch-safe: a stale session
  /// never writes its failure into the newer session's status.
  Future<void> keepCurrentMedia() async {
    final path = player.mediaPath;
    final mediaId = player.mediaId;
    if (path == null || mediaId == null) {
      player.setStatus(text('statusOpenMediaFirst'));
      return;
    }
    if (player.mediaRetained == true || player.retentionInFlight) return;
    final sessionEpoch = _sessionEpoch;
    player.setRetentionInFlight(true);
    late String keptTitle;
    try {
      final copy = await managedStore.copyIntoStore(sourcePath: path);
      if (_isStale(sessionEpoch)) {
        // The session moved on while the copy ran and registration never
        // happened: the copy is orphaned. Remove only what this operation
        // created; a pre-existing deduplication target is never touched.
        if (copy.createdNew) {
          await managedStore.deleteStoreCopy(copy.path);
        }
        return;
      }
      // The registration round-trip alone is the rollback boundary: only its
      // failure may remove the new copy. A successful return makes the copy
      // real membership, and nothing after it — a stale session, a failed
      // material resolve, a failed state write — may delete it or rebind the
      // player of a session that has since moved on.
      MediaItem media;
      try {
        media = await repository.registerMedia(
          copy.path,
          retain: true,
          title: player.mediaTitle,
          kind: copy.mediaKind,
        );
      } catch (error) {
        // Only a failed registration may remove the new copy. A pre-existing
        // deduplication target is shared and is never deleted.
        if (copy.createdNew) {
          await managedStore.deleteStoreCopy(copy.path);
        }
        if (_isStale(sessionEpoch)) return;
        player.setStatus(
          text('statusKeepFailed'),
          error: true,
          failure: repository.failureDetail(error),
        );
        return;
      }
      if (_isStale(sessionEpoch)) return;
      keptTitle = media.title;
      player.setMedia(
        id: media.id,
        path: copy.path,
        title: media.title,
        fingerprint: media.fingerprint,
      );
      player.setMediaRetained(media.retainedAtMs != null);
      // The managed rebind keeps the same fingerprint-derived media id, so
      // the bound material keeps its id and revision while membership
      // evidence moves to the material. A resolution failure here is
      // non-gating: the media-level membership evidence from the registration
      // stays, the copy stays, and the Keep still reports success.
      await _refreshCurrentMaterial();
      if (_isStale(sessionEpoch)) return;
      settings.recordRecentMedia(
        path: copy.path,
        title: keptTitle,
        positionMs: player.position.inMilliseconds,
        durationMs: player.duration.inMilliseconds,
        subtitleCount: subtitle.subtitleResources.length,
      );
      player.setStatus(text('statusMediaKept'), playback: true);
      unawaited(_notifyLibraryChanged());
    } on ManagedStoreUnavailable {
      if (_isStale(sessionEpoch)) return;
      player.setStatus(text('statusManagedStoreUnavailable'), error: true);
    } on ManagedStoreCopyFailed {
      // Local copy failures deliberately carry no raw path/OS text. The
      // learner sees the stable failure while the current material remains
      // playable and Temporary.
      if (_isStale(sessionEpoch)) return;
      player.setStatus(text('statusKeepFailed'), error: true);
    } catch (error) {
      if (_isStale(sessionEpoch)) return;
      player.setStatus(
        text('statusKeepFailed'),
        error: true,
        failure: repository.failureDetail(error),
      );
    } finally {
      // The in-flight flag is session-independent: clearing it never reports
      // into a session, so it is always reset.
      player.setRetentionInFlight(false);
    }
  }

  /// The secondary Keep: retain the current media without copying it. The
  /// original file stays exactly where it is; only Personal Library membership
  /// changes. Never the default — a reference can disappear when its file
  /// moves, which is why the default Keep manages a copy.
  /// Membership is material membership through the learning-material boundary:
  /// [LearningMaterialRepository.retainLearningMaterial] runs against the
  /// bound material and the session's state is updated from the returned
  /// details. The legacy media-level retain is never called. Without a
  /// resolved material — or when the boundary is unavailable — the stable keep
  /// failure is reported without raw text and the media stays exactly as it
  /// is.
  Future<void> referenceCurrentMediaInPlace() async {
    final mediaId = player.mediaId;
    if (mediaId == null) {
      player.setStatus(text('statusOpenMediaFirst'));
      return;
    }
    if (player.mediaRetained == true || player.retentionInFlight) return;
    final material = currentMaterial;
    if (material == null || !materialRepository.isAvailable) {
      // No canonical material identity to retain, or the boundary is down:
      // report the stable failure without inventing an id and without leaking
      // transport text. The media stays exactly as it is.
      player.setStatus(text('statusKeepFailed'), error: true);
      return;
    }
    final sessionEpoch = _sessionEpoch;
    player.setRetentionInFlight(true);
    try {
      final updated = await materialRepository.retainLearningMaterial(
        material.material.id,
      );
      if (_isStale(sessionEpoch)) return;
      currentMaterial = updated;
      player.setMediaRetained(updated.material.retainedAtMs != null);
      player.setStatus(text('statusMediaKeptInPlace'), playback: true);
      unawaited(_notifyLibraryChanged());
    } catch (error) {
      if (_isStale(sessionEpoch)) return;
      player.setStatus(
        text('statusKeepFailed'),
        error: true,
        failure: materialRepository.failureDetail(error),
      );
    } finally {
      player.setRetentionInFlight(false);
    }
  }

  /// Removes the current media's material from the Personal Library. Unretain
  /// is material membership through the learning-material boundary: neither
  /// the original file nor a managed copy, nor any revision, binding, resource
  /// or learning state is touched. Managed-file deletion is a separate action
  /// and is never coupled to this one.
  Future<void> unretainCurrentMedia() async {
    final mediaId = player.mediaId;
    if (mediaId == null) {
      player.setStatus(text('statusOpenMediaFirst'));
      return;
    }
    if (player.mediaRetained != true || player.retentionInFlight) return;
    final sessionEpoch = _sessionEpoch;
    player.setRetentionInFlight(true);
    try {
      final material = currentMaterial;
      if (material == null || !materialRepository.isAvailable) {
        // No canonical material to unretain: report the stable unkeep failure
        // without inventing a material identity and without leaking transport
        // text. The media stays exactly as it is.
        player.setStatus(text('statusUnkeepFailed'), error: true);
        return;
      }
      final updated = await materialRepository.unretainLearningMaterial(
        material.material.id,
      );
      if (_isStale(sessionEpoch)) return;
      currentMaterial = updated;
      player.setMediaRetained(updated.material.retainedAtMs != null);
      player.setStatus(text('statusMediaUnkept'), playback: true);
      unawaited(_notifyLibraryChanged());
    } catch (error) {
      if (_isStale(sessionEpoch)) return;
      player.setStatus(
        text('statusUnkeepFailed'),
        error: true,
        failure: materialRepository.failureDetail(error),
      );
    } finally {
      player.setRetentionInFlight(false);
    }
  }

  /// Selects the one unambiguous learning transcript for the current media,
  /// or leaves the choice to the workbench.
  ///
  /// Cases, in order:
  ///
  /// * a track is already selected — keep it, never replace;
  /// * exactly one usable track exists — select it automatically, because
  ///   asking the user to pick from one option is a dead tap;
  /// * several usable tracks exist — select nothing; the workbench shows a
  ///   chooser instead of guessing (no quality ordering exists yet);
  /// * no usable track exists — select nothing; the workbench shows the
  ///   prepare surface.
  ///
  /// Usability is the domain model's own rule ([SubtitleTrack.usableForLearning]):
  /// archived/withheld tracks are never candidates, whatever their content.
  Future<void> reconcileLearningTranscript() async {
    if (!isMounted() || subtitle.primaryTrack != null) return;
    final usable = subtitle.subtitleResources
        .where((track) => track.usableForLearning)
        .toList(growable: false);
    if (usable.length != 1) return;
    await usePrimarySubtitleTrack(
      usable.single,
      nextStatus: text('statusLearningTranscriptSelected'),
    );
    await resourceActions.loadSubtitleResources(updateStatus: false);
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
