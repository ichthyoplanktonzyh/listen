import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/api_failure.dart';
import '../models/learning_material.dart';
import '../models/material_capability.dart';
import '../models/timeline.dart';
import '../models/composition.dart';
import '../services/composition_transcript_bridge.dart';
import 'material_capability_coordinator.dart';
import 'media_session_coordinator.dart';
import 'subtitle_controller.dart';

/// What the workbench shows for "does this media have a learning transcript".
///
/// These are product states, not package-lifecycle states: a user who just
/// opened a media file should never have to know that behind the scenes a
/// package was generated, installed and adopted.
enum TranscriptReadinessPhase {
  /// A learning transcript is selected and the normal transcript UI is up.
  ready,

  /// Several usable transcripts exist and none is selected; the user picks.
  choosing,

  /// No usable transcript exists; offer to prepare one (or import a file).
  missing,

  /// A preparation run (request → generate → install → adopt) is in flight.
  preparing,

  /// The last preparation run failed. The failure is typed and retryable per
  /// the generator's own semantics; it never silently changes the selection.
  failed,

  /// No usable transcript exists and automatic preparation is not possible on
  /// this machine right now (no configured generator / no media round-trip).
  unavailable,
}

/// The one prerequisite currently preventing automatic preparation.
///
/// This stays product-shaped and specific enough to act on: the UI no longer
/// claims Core and Gen are both unavailable when only one local component is
/// missing.
enum TranscriptPreparationAvailability {
  ready,
  coreUnavailable,
  generatorUnavailable,
  pythonUnavailable,
  whisperUnavailable,
  whisperModelUnavailable,
  mediaToolsUnavailable,
  mediaRegistrationUnavailable,
  mediaUnavailable,
}

/// User-facing stage of an in-flight preparation, derived from the coordinator
/// run stage. Kept product-shaped: the UI never sees stage identifiers.
enum TranscriptPreparationStage {
  starting,
  checkingMedia,
  readingMedia,
  preparingAudio,
  transcribing,
  organizing,
  importing,
}

@immutable
class TranscriptReadinessState {
  TranscriptReadinessState({
    this.phase = TranscriptReadinessPhase.missing,
    this.preparationStage,
    this.failure,
    this.fingerprintMismatch = false,
    this.canCancel = false,
    this.canRetry = false,
    this.unavailableReason,
    List<SubtitleTrack> usableTracks = const [],
  }) : _usableTracks = List.unmodifiable(usableTracks);

  final TranscriptReadinessPhase phase;

  /// Non-null while [phase] is [TranscriptReadinessPhase.preparing].
  final TranscriptPreparationStage? preparationStage;

  /// Typed failure detail behind [TranscriptReadinessPhase.failed]. Kept off
  /// the main surface: the workbench shows a sentence, not identifiers.
  final ApiFailure? failure;

  /// Whether the failure is a media-fingerprint mismatch, which must stay an
  /// explicit failure rather than being retried or force-imported.
  final bool fingerprintMismatch;
  final bool canCancel;
  final bool canRetry;
  final TranscriptPreparationAvailability? unavailableReason;
  final List<SubtitleTrack> _usableTracks;
  List<SubtitleTrack> get usableTracks => List.unmodifiable(_usableTracks);
}

/// App-layer projection that owns "the current media's learning transcript"
/// as a product journey.
///
/// It reuses [MaterialCapabilityCoordinator] for the whole completion flow
/// (resolution, generation through the pinned bundle, installation and
/// adoption) and projects its run onto readiness states.
class TranscriptReadinessViewModel extends ChangeNotifier {
  TranscriptReadinessViewModel({
    required this.subtitle,
    required this.mediaSession,
    required this.preparationAvailability,
    required this.coordinator,
    required this.currentMaterial,
    this.bridge,
    this.resolveComposition,
    Listenable? refreshTrigger,
  })
    // The public seam stays an explicit `refreshTrigger` parameter rather than
    // a private initializing formal, whose call-site name would depend on the
    // `private-named-parameters` language feature.
    // ignore: prefer_initializing_formals
    : _refreshTrigger = refreshTrigger {
    subtitle.store.addListener(_recompute);
    coordinator.addListener(_recompute);
    _refreshTrigger?.addListener(_recompute);
    _recompute();
  }

  final SubtitleController subtitle;
  final MediaSessionCoordinator mediaSession;

  /// Resolves the complete local preparation chain to one actionable state.
  /// This selects the explanatory copy; it does not hide or disable the
  /// learner's generation intent. A request may still resolve an already
  /// installed edition, or produce a precise typed failure.
  final TranscriptPreparationAvailability Function() preparationAvailability;

  /// The deep completion coordinator.
  final MaterialCapabilityCoordinator coordinator;

  /// The current media's material, when one is registered.
  final MaterialDetails? Function() currentMaterial;

  /// Bridges the adopted composition into the subtitle-track surface so a
  /// prepared learning transcript appears in the workbench. Null on hosts
  /// without the composition surface (tests, minimal hosts).
  final CompositionTranscriptBridge? bridge;

  /// Resolves the material's adopted composition, so the optional analysis
  /// resources it carries can ride onto the bridged transcript. Null on hosts
  /// without the composition surface.
  final Future<ResolvedComposition?> Function(String materialId)?
  resolveComposition;

  final Listenable? _refreshTrigger;

  late String Function(String key) text;
  bool _disposed = false;
  bool _bridgeAttempted = false;
  bool _bridgeInFlight = false;
  String? _bridgeMaterialId;

  TranscriptReadinessState _state = TranscriptReadinessState();
  TranscriptReadinessState get state => _state;

  void bind({required String Function(String key) text}) {
    this.text = text;
  }

  List<SubtitleTrack> get _usableTracks => subtitle.subtitleResources
      .where((track) => track.usableForLearning)
      .toList(growable: false);

  Future<void> selectTrack(SubtitleTrack track) async {
    if (subtitle.primaryTrack?.id == track.id) return;
    try {
      await mediaSession.usePrimarySubtitleTrack(
        track,
        nextStatus: text('statusLearningTranscriptSelected'),
      );
      await mediaSession.resourceActions.loadSubtitleResources(
        updateStatus: false,
      );
      _recompute();
    } catch (error) {
      if (!_disposed) {
        mediaSession.player.setStatus(
          text('statusLearningTranscriptSelectionFailed'),
          error: true,
          failure: mediaSession.repository.failureDetail(error),
        );
      }
    }
  }

  Future<void> prepareLearningTranscript({
    bool forceRegenerate = false,
  }) async {
    final material = currentMaterial();
    if (material == null) {
      mediaSession.player.setStatus(
        text(
          mediaSession.player.mediaPath?.isNotEmpty ?? false
              ? 'statusMediaMaterialRegistrationUnavailable'
              : 'statusOpenMediaAndCoreFirst',
        ),
      );
      return;
    }
    await coordinator.requestCapability(
      material,
      MaterialCapability.read,
      forceProduce: forceRegenerate,
    );
    _recompute();
  }

  void cancel() {
    final material = currentMaterial();
    if (material == null) return;
    unawaited(
      coordinator.cancel(material.material.id, MaterialCapability.read),
    );
    _recompute();
  }

  Future<void> retry() async {
    final material = currentMaterial();
    if (material == null) return;
    _bridgeAttempted = false;
    await coordinator.requestCapability(material, MaterialCapability.read);
    _recompute();
  }

  Future<void> importSubtitle() => mediaSession.openSubtitle(secondary: false);

  /// Re-evaluates local prerequisites after the asynchronous tool locator
  /// completes without manufacturing a media or Core change event.
  void refreshAvailability() => _recompute();

  /// Re-projects the newly adopted immutable package onto the open media.
  /// Adoption may change every one of the eight resources while the Material
  /// identity stays the same, so the workbench must not wait for a media
  /// switch before reading the new composition.
  Future<void> refreshAdoptedComposition() async {
    final materialId = currentMaterial()?.material.id;
    if (materialId == null || _bridgeInFlight) return;
    _bridgeMaterialId = materialId;
    _bridgeAttempted = false;
    _bridgeInFlight = true;
    await _bridgePackageToTrack();
  }

  /// Imports the adopted composition's structured reading as a subtitle
  /// track, once, through [CompositionTranscriptBridge]. The Core package
  /// surface and the subtitle-track surface do not share storage, so a
  /// freshly prepared learning transcript would otherwise stay invisible to
  /// the workbench transcript panel.
  Future<void> _bridgePackageToTrack() async {
    final bridge = this.bridge;
    final material = currentMaterial();
    final mediaId = mediaSession.player.mediaId;
    final materialId = material?.material.id;
    try {
      if (material == null || mediaId == null || materialId == null) return;
      // Prefer the package's exact tokenized timed-text resource. It already
      // has the cue ids consumed by word lookup, word timing, sense groups and
      // prosody, so routing it through SRT would throw those identities away.
      final composition = await resolveComposition?.call(materialId);
      if (!_isCurrentProjectionTarget(materialId, mediaId)) return;
      final exact = composition?.transcript;
      if (exact != null && _hasLookupTokens(exact)) {
        subtitle.setPrimaryTrack(exact);
        subtitle.setSubtitleResources([exact]);
        final enhancements = composition!.enhancements;
        subtitle.setSpeechEnhancements(
          pronunciationBySentence: const {},
          timingsBySentence: enhancements.timingsBySentence,
          pronunciationProviders: const [],
          chunkPartitionsBySentence: enhancements.chunkPartitionsBySentence,
          senseGroupsBySentence: enhancements.senseGroupsBySentence,
          acousticsBySentence: enhancements.acousticsBySentence,
          prosodyAnchorsBySentence: enhancements.prosodyAnchorsBySentence,
          phonesBySentence: enhancements.phonesBySentence,
        );
        subtitle.setSubtitleResourceCapabilities({
          exact.id: SubtitleResourceCapabilities.fromCounts(
            sentenceCount: exact.cues.length,
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
        subtitle.updatePosition(mediaSession.player.position);
        return;
      }

      // Older/partial editions may only have Structured Reading plus anchor
      // alignment. Keep the established Core import bridge for that honest
      // fallback; Core tokenizes the imported lines before the learning panel
      // receives them.
      if (bridge == null) return;
      final bridged = await bridge.bridge(materialId, mediaId);
      if (!_isCurrentProjectionTarget(materialId, mediaId)) return;
      if (bridged != null) {
        await mediaSession.resourceActions.loadSubtitleResources(
          updateStatus: false,
        );
        subtitle.setPrimaryTrack(bridged.track);
        if (!subtitle.subtitleResources.any(
          (track) => track.id == bridged.track.id,
        )) {
          subtitle.setSubtitleResources([
            ...subtitle.subtitleResources,
            bridged.track,
          ]);
        }
        await _applyCompositionEnhancements(materialId, bridged);
      }
    } on Object catch (error) {
      debugPrint('transcript bridge failed: $error');
    } finally {
      if (_bridgeMaterialId == materialId) {
        _bridgeAttempted = true;
        _bridgeInFlight = false;
        _recompute();
      }
    }
  }

  bool _isCurrentProjectionTarget(String materialId, String mediaId) =>
      currentMaterial()?.material.id == materialId &&
      mediaSession.player.mediaId == mediaId;

  static bool _hasLookupTokens(SubtitleTrack track) =>
      track.cues.isNotEmpty &&
      track.cues.every(
        (cue) => cue.tokens.any((token) => token.kind == 'word'),
      );

  /// Re-keys the composition's optional analysis resources onto the cues the
  /// bridge just created, and hands them to the transcript surface.
  ///
  /// The package keys these by *its* sentence ids; the workbench looks them up
  /// by cue id. Without the bridge's mapping they would key on ids no cue has
  /// and render nothing at all — silently, which is the worst version of it.
  /// So an absent mapping applies nothing, exactly like an absent resource.
  Future<void> _applyCompositionEnhancements(
    String materialId,
    BridgedTranscript bridged,
  ) async {
    final resolve = resolveComposition;
    if (resolve == null || bridged.cueIdBySentenceId.isEmpty) return;
    final composition = await resolve(materialId);
    final enhancements = composition?.enhancements;
    if (enhancements == null || enhancements.isEmpty) return;
    if (_disposed) return;
    subtitle.applyCompositionEnhancements(
      timingsBySentence: _rekey(
        enhancements.timingsBySentence,
        bridged.cueIdBySentenceId,
        (cueId, timings) => [
          for (final timing in timings) timing.copyWith(sentenceId: cueId),
        ],
      ),
      senseGroupsBySentence: _rekey(
        enhancements.senseGroupsBySentence,
        bridged.cueIdBySentenceId,
        (cueId, groups) => groups,
      ),
      chunkPartitionsBySentence: _rekey(
        enhancements.chunkPartitionsBySentence,
        bridged.cueIdBySentenceId,
        (cueId, partition) => partition,
      ),
      acousticsBySentence: _rekey(
        enhancements.acousticsBySentence,
        bridged.cueIdBySentenceId,
        (cueId, acoustics) => acoustics,
      ),
      prosodyAnchorsBySentence: _rekey(
        enhancements.prosodyAnchorsBySentence,
        bridged.cueIdBySentenceId,
        (cueId, anchors) => anchors,
      ),
      phonesBySentence: _rekey(
        enhancements.phonesBySentence,
        bridged.cueIdBySentenceId,
        (cueId, phones) => phones,
      ),
    );
  }

  /// Moves [source] from package sentence ids to cue ids, dropping anything
  /// the mapping does not cover.
  static Map<String, T> _rekey<T>(
    Map<String, T> source,
    Map<String, String> cueIdBySentenceId,
    T Function(String cueId, T value) adapt,
  ) {
    final result = <String, T>{};
    for (final entry in source.entries) {
      final cueId = cueIdBySentenceId[entry.key];
      if (cueId == null) continue;
      result[cueId] = adapt(cueId, entry.value);
    }
    return result;
  }

  void _recompute() {
    if (_disposed) return;
    final material = currentMaterial();
    final materialId = material?.material.id;
    if (_bridgeMaterialId != materialId) {
      _bridgeMaterialId = materialId;
      _bridgeAttempted = false;
      _bridgeInFlight = false;
    }
    final run = material == null
        ? null
        : coordinator.runViewFor(material.material.id, MaterialCapability.read);
    final runFailure = run?.failureCode;
    final projectionAvailable = bridge != null || resolveComposition != null;
    final completedNeedsProjection =
        subtitle.primaryTrack == null &&
        run?.phase == CapabilityRunPhase.completed &&
        projectionAvailable;
    if (completedNeedsProjection && !_bridgeAttempted && !_bridgeInFlight) {
      _bridgeInFlight = true;
      unawaited(_bridgePackageToTrack());
    }
    final projectionFailed =
        completedNeedsProjection && _bridgeAttempted && !_bridgeInFlight;
    final availability = preparationAvailability();
    final phase = switch (subtitle.primaryTrack) {
      != null => TranscriptReadinessPhase.ready,
      _ when completedNeedsProjection && !projectionFailed =>
        TranscriptReadinessPhase.preparing,
      _ when projectionFailed => TranscriptReadinessPhase.failed,
      // Minimal hosts without a composition bridge retain the old completion
      // projection; production always supplies a resolver and bridge.
      _ when run?.phase == CapabilityRunPhase.completed =>
        TranscriptReadinessPhase.ready,
      _ when run?.busy ?? false => TranscriptReadinessPhase.preparing,
      _ when run?.phase == CapabilityRunPhase.failed =>
        TranscriptReadinessPhase.failed,
      _ when _usableTracks.isNotEmpty => TranscriptReadinessPhase.choosing,
      _ when availability == TranscriptPreparationAvailability.ready =>
        TranscriptReadinessPhase.missing,
      _ => TranscriptReadinessPhase.unavailable,
    };
    final next = TranscriptReadinessState(
      phase: phase,
      preparationStage: phase == TranscriptReadinessPhase.preparing
          ? _preparationStageOf(run?.stage)
          : null,
      failure: projectionFailed
          ? const ApiFailure(raw: 'learning_material_projection_failed')
          : runFailure == null
          ? null
          : ApiFailure(raw: runFailure),
      fingerprintMismatch: false,
      canCancel: run?.busy ?? false,
      canRetry: projectionFailed || run?.phase == CapabilityRunPhase.failed,
      unavailableReason: phase == TranscriptReadinessPhase.unavailable
          ? availability
          : null,
      usableTracks: _usableTracks,
    );
    if (identical(next, _state) ||
        (next.phase == _state.phase &&
            next.preparationStage == _state.preparationStage &&
            next.fingerprintMismatch == _state.fingerprintMismatch &&
            next.canCancel == _state.canCancel &&
            next.canRetry == _state.canRetry &&
            next.unavailableReason == _state.unavailableReason &&
            next.failure?.raw == _state.failure?.raw &&
            _sameTracks(next.usableTracks, _state.usableTracks))) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  TranscriptPreparationStage? _preparationStageOf(String? stage) {
    if (stage == null) return TranscriptPreparationStage.starting;
    final lower = stage.toLowerCase();
    if (lower.contains('transcrib')) {
      return TranscriptPreparationStage.transcribing;
    }
    if (lower.contains('decoding') || lower.contains('read')) {
      return TranscriptPreparationStage.readingMedia;
    }
    if (lower.contains('normaliz') ||
        lower.contains('tts') ||
        lower.contains('synthesi')) {
      return TranscriptPreparationStage.preparingAudio;
    }
    if (lower.contains('validat') || lower.contains('prob')) {
      return TranscriptPreparationStage.checkingMedia;
    }
    if (lower.contains('build') || lower.contains('qualify')) {
      return TranscriptPreparationStage.organizing;
    }
    if (lower.contains('install') || lower.contains('adopt')) {
      return TranscriptPreparationStage.importing;
    }
    return TranscriptPreparationStage.starting;
  }

  bool _sameTracks(List<SubtitleTrack> a, List<SubtitleTrack> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].id != b[index].id) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    subtitle.store.removeListener(_recompute);
    coordinator.removeListener(_recompute);
    _refreshTrigger?.removeListener(_recompute);
    super.dispose();
  }
}
